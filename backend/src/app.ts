import { randomUUID } from 'node:crypto';
import express, { type Request, type Response } from 'express';
import { z } from 'zod';
import { requireCaller, type Verifier } from './auth.js';
import { BillingService, OtherAccountError } from './billing/service.js';
import { InvalidSignatureError, UnknownProductError } from './billing/apple.js';
import { PlayProductError, type Rtdn } from './billing/google.js';
import { sanitiseEvents, type EventRow } from './events.js';
import type { Repo } from './repo.js';

export interface Config {
  /** Lowest app build that may run; older builds are asked to update. */
  minBuild: number;
  /** Feature switches the app reads at start, e.g. { sync: true }. */
  switches: Record<string, boolean>;
  /** During the beta every new account gets Pro free until this time (epoch ms), or null. */
  betaGrantUntil: number | null;
}

export interface Deps {
  repo: Repo;
  billing: BillingService;
  verifier: Verifier;
  /** Verifies the OIDC token Pub/Sub push attaches; throws when invalid. */
  pubsubPush: (authorization: string | undefined) => Promise<void>;
  events: (rows: EventRow[]) => Promise<void>;
  feedbackFiles: (id: string, files: { name: string; contentType: string; data: Buffer }[]) => Promise<string[]>;
  config: Config;
  now: () => number;
}

const verifyApple = z.object({ signedTransaction: z.string().min(20).max(20_000), move: z.boolean().optional() });
const verifyGoogle = z.object({
  productId: z.string().max(100),
  purchaseToken: z.string().min(10).max(4_000),
  move: z.boolean().optional(),
});
const restore = z.object({
  apple: z.array(z.string().max(20_000)).max(50).optional(),
  google: z.array(z.object({ productId: z.string().max(100), purchaseToken: z.string().max(4_000) })).max(50).optional(),
});
const feedback = z.object({
  text: z.string().min(1).max(5_000),
  appVersion: z.string().max(32),
  platform: z.enum(['ios', 'android']),
  /** base64 PNG or JPEG, at most ~2 MB. */
  screenshot: z.string().max(2_800_000).optional(),
  /** The Health data check report the user read before sending. */
  report: z.string().max(200_000).optional(),
});
const consent = z.object({ diagnostics: z.boolean(), events: z.boolean() });

export function createApp(d: Deps) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '3mb' }));
  const auth = requireCaller(d.verifier);

  const fail = (res: Response, e: unknown) => {
    if (e instanceof z.ZodError) return res.status(400).json({ error: 'bad_request' });
    if (e instanceof OtherAccountError) return res.status(409).json({ error: 'other_account' });
    if (e instanceof UnknownProductError || e instanceof PlayProductError) {
      return res.status(422).json({ error: 'unknown_product' });
    }
    // Never log payloads or tokens; the message only.
    console.error(JSON.stringify({ severity: 'ERROR', message: e instanceof Error ? e.message : 'error' }));
    return res.status(500).json({ error: 'server' });
  };

  app.get('/healthz', (_req, res) => res.json({ ok: true }));

  app.get('/config', (_req, res) => res.json({ minBuild: d.config.minBuild, switches: d.config.switches }));

  /** First call after sign-in (anonymous or not): creates users/{uid} and any beta grant (L-O2: no blocking function). */
  app.post('/account/init', auth, async (req: Request, res: Response) => {
    try {
      const c = req.caller!;
      const now = d.now();
      const created = await d.repo.createUserIfMissing({
        uid: c.uid,
        createdAt: now,
        anonymous: c.anonymous,
        email: c.email,
        country: req.header('x-appengine-country') ?? null,
        consent: { diagnostics: false, events: false },
        deletedAt: null,
      });
      if (created && d.config.betaGrantUntil !== null && d.config.betaGrantUntil > now) {
        await d.repo.putGrant(c.uid, { kind: 'beta_grant', expiresAt: d.config.betaGrantUntil });
      }
      res.json({ created, entitlement: await d.billing.refreshEntitlement(c.uid) });
    } catch (e) {
      fail(res, e);
    }
  });

  app.post('/account/consent', auth, async (req, res) => {
    try {
      await d.repo.updateConsent(req.caller!.uid, consent.parse(req.body));
      res.json({ ok: true });
    } catch (e) {
      fail(res, e);
    }
  });

  app.post('/account/delete', auth, async (req, res) => {
    try {
      await d.repo.requestDeletion(req.caller!.uid, d.now());
      res.status(202).json({ ok: true });
    } catch (e) {
      fail(res, e);
    }
  });

  app.get('/billing/entitlement', auth, async (req, res) => {
    try {
      res.json(await d.billing.refreshEntitlement(req.caller!.uid));
    } catch (e) {
      fail(res, e);
    }
  });

  app.post('/billing/apple/verify', auth, async (req, res) => {
    try {
      const b = verifyApple.parse(req.body);
      res.json(await d.billing.verifyApple(req.caller!.uid, b.signedTransaction, b.move ?? false));
    } catch (e) {
      fail(res, e);
    }
  });

  app.post('/billing/google/verify', auth, async (req, res) => {
    try {
      const b = verifyGoogle.parse(req.body);
      res.json(await d.billing.verifyGoogle(req.caller!.uid, b.productId, b.purchaseToken, b.move ?? false));
    } catch (e) {
      fail(res, e);
    }
  });

  /** Re-verifies what the store says this device owns. Purchases under another account are listed, not moved. */
  app.post('/billing/restore', auth, async (req, res) => {
    try {
      const b = restore.parse(req.body);
      const uid = req.caller!.uid;
      const otherAccount: string[] = [];
      for (const jws of b.apple ?? []) {
        try {
          await d.billing.verifyApple(uid, jws);
        } catch (e) {
          if (e instanceof OtherAccountError) otherAccount.push(e.purchaseId);
          else if (!(e instanceof UnknownProductError)) throw e;
        }
      }
      for (const g of b.google ?? []) {
        try {
          await d.billing.verifyGoogle(uid, g.productId, g.purchaseToken);
        } catch (e) {
          if (e instanceof OtherAccountError) otherAccount.push(e.purchaseId);
          else if (!(e instanceof PlayProductError)) throw e;
        }
      }
      res.json({ entitlement: await d.billing.refreshEntitlement(uid), otherAccount });
    } catch (e) {
      fail(res, e);
    }
  });

  /** App Store Server Notifications V2. Apple signs the payload; no auth header. */
  app.post('/webhooks/apple', async (req, res) => {
    try {
      const signed = z.object({ signedPayload: z.string().min(20) }).parse(req.body).signedPayload;
      await d.billing.appleNotification(signed);
      res.status(200).end();
    } catch (e) {
      // A bad signature will never verify: 400 so Apple stops retrying.
      if (e instanceof z.ZodError || e instanceof InvalidSignatureError) return res.status(400).end();
      fail(res, e);
    }
  });

  /** Pub/Sub push of Play real-time developer notifications. */
  app.post('/workers/play-rtdn', async (req, res) => {
    try {
      await d.pubsubPush(req.header('authorization'));
    } catch {
      return res.status(401).end();
    }
    try {
      const msg = z
        .object({ message: z.object({ data: z.string(), messageId: z.string() }) })
        .parse(req.body).message;
      const n = JSON.parse(Buffer.from(msg.data, 'base64').toString('utf8')) as Rtdn;
      await d.billing.playNotification(msg.messageId, n);
      res.status(204).end();
    } catch (e) {
      // 4xx would make Pub/Sub drop it; a bad message is acked, a server error retried.
      if (e instanceof z.ZodError || e instanceof SyntaxError) return res.status(204).end();
      fail(res, e);
    }
  });

  /** Opt-in usage events. Accepted only when the account has opted in. */
  app.post('/events', auth, async (req, res) => {
    try {
      const u = await d.repo.getUser(req.caller!.uid);
      if (!u?.consent.events) return res.status(403).json({ error: 'not_opted_in' });
      const { rows, dropped } = sanitiseEvents(req.body, d.now());
      if (rows.length > 0) await d.events(rows);
      res.json({ kept: rows.length, dropped });
    } catch (e) {
      fail(res, e);
    }
  });

  app.post('/feedback', auth, async (req, res) => {
    try {
      const b = feedback.parse(req.body);
      const id = randomUUID();
      const files: { name: string; contentType: string; data: Buffer }[] = [];
      if (b.screenshot) {
        const data = Buffer.from(b.screenshot, 'base64');
        const png = data.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]));
        const jpg = data.subarray(0, 2).equals(Buffer.from([0xff, 0xd8]));
        if (!png && !jpg) return res.status(400).json({ error: 'bad_screenshot' });
        files.push({ name: png ? 'screenshot.png' : 'screenshot.jpg', contentType: png ? 'image/png' : 'image/jpeg', data });
      }
      if (b.report) files.push({ name: 'health-check.txt', contentType: 'text/plain', data: Buffer.from(b.report) });
      const paths = files.length ? await d.feedbackFiles(id, files) : [];
      await d.repo.putFeedback(id, {
        uid: req.caller!.uid,
        text: b.text,
        appVersion: b.appVersion,
        platform: b.platform,
        attachments: paths,
        createdAt: d.now(),
      });
      res.status(201).json({ id });
    } catch (e) {
      fail(res, e);
    }
  });

  return app;
}
