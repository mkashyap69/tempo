import request from 'supertest';
import { beforeEach, describe, expect, it } from 'vitest';
import { createApp, type Deps } from '../src/app.js';
import { BillingService } from '../src/billing/service.js';
import type { EventRow } from '../src/events.js';
import { MemoryRepo } from '../src/repo.js';
import { DAY, FakePlay, T0, appleTx, fakeApple, sign } from './fakes.js';

function setup(betaGrantUntil: number | null = null) {
  const repo = new MemoryRepo();
  const events: EventRow[] = [];
  const files: string[] = [];
  const billing = new BillingService({ repo, apple: fakeApple, play: new FakePlay(), packageName: 'dev.tempo.tempo', now: () => T0 });
  const deps: Deps = {
    repo,
    billing,
    verifier: {
      idToken: async (t) => {
        if (!t.startsWith('id:')) throw new Error('bad');
        return { uid: t.slice(3), anonymous: t.includes('anon'), email: null };
      },
      appCheck: async (t) => {
        if (t !== 'ok') throw new Error('bad');
      },
    },
    pubsubPush: async (a) => {
      if (a !== 'Bearer pubsub') throw new Error('bad');
    },
    events: async (rows) => void events.push(...rows),
    feedbackFiles: async (id, fs) => fs.map((f) => `gs://feedback/${id}/${f.name}`).map((p) => (files.push(p), p)),
    config: { minBuild: 1, switches: { sync: false }, betaGrantUntil },
    now: () => T0,
  };
  return { app: createApp(deps), repo, events, files };
}

const as = (uid: string) => ({ authorization: `Bearer id:${uid}`, 'x-firebase-appcheck': 'ok' });

describe('api', () => {
  let s: ReturnType<typeof setup>;
  beforeEach(() => (s = setup()));

  it('requires a token and App Check', async () => {
    await request(s.app).post('/account/init').expect(401);
    await request(s.app).post('/account/init').set({ authorization: 'Bearer id:a' }).expect(401);
    await request(s.app).post('/account/init').set({ authorization: 'Bearer nope', 'x-firebase-appcheck': 'ok' }).expect(401);
  });

  it('account init creates the user once; Free by default', async () => {
    const r = await request(s.app).post('/account/init').set(as('anon-1')).expect(200);
    expect(r.body).toMatchObject({ created: true, entitlement: { pro: false } });
    expect((await s.repo.getUser('anon-1'))!.anonymous).toBe(true);
    const again = await request(s.app).post('/account/init').set(as('anon-1')).expect(200);
    expect(again.body.created).toBe(false);
  });

  it('during the beta new accounts get Pro free', async () => {
    const b = setup(T0 + 60 * DAY);
    const r = await request(b.app).post('/account/init').set(as('tester')).expect(200);
    expect(r.body.entitlement).toMatchObject({ pro: true, source: 'beta_grant' });
  });

  it('verify, other account and restore', async () => {
    await request(s.app).post('/billing/apple/verify').set(as('alice')).send({ signedTransaction: sign(appleTx('alice')) }).expect(200);
    await request(s.app).post('/billing/apple/verify').set(as('bob')).send({ signedTransaction: sign(appleTx('alice')) }).expect(409);
    const r = await request(s.app).post('/billing/restore').set(as('bob')).send({ apple: [sign(appleTx('alice'))] }).expect(200);
    expect(r.body).toMatchObject({ entitlement: { pro: false }, otherAccount: ['apple:1000'] });
    await request(s.app).post('/billing/apple/verify').set(as('bob')).send({ signedTransaction: 'x' }).expect(400);
  });

  it('apple webhook needs a valid signature and is idempotent', async () => {
    await request(s.app).post('/webhooks/apple').send({ signedPayload: 'not-signed-by-apple-at-all' }).expect(400);
    const n = sign({ notificationUUID: 'u1', notificationType: 'TEST' });
    await request(s.app).post('/webhooks/apple').send({ signedPayload: n }).expect(200);
    await request(s.app).post('/webhooks/apple').send({ signedPayload: n }).expect(200);
    expect(s.repo.billingEvents.size).toBe(1);
  });

  it('Pub/Sub push needs its OIDC token; bad messages are acked', async () => {
    const data = Buffer.from(JSON.stringify({ packageName: 'dev.tempo.tempo', testNotification: { version: '1.0' } })).toString('base64');
    await request(s.app).post('/workers/play-rtdn').send({ message: { data, messageId: '1' } }).expect(401);
    await request(s.app).post('/workers/play-rtdn').set({ authorization: 'Bearer pubsub' }).send({ message: { data, messageId: '1' } }).expect(204);
    await request(s.app).post('/workers/play-rtdn').set({ authorization: 'Bearer pubsub' }).send({ nope: 1 }).expect(204);
  });

  it('events: refused without opt-in; health values never get through', async () => {
    await request(s.app).post('/account/init').set(as('a')).expect(200);
    const batch = {
      install_id: '0b0f4a6e-2f6b-4b57-9a5e-0c7d1f3b9e21',
      app_version: '1.0.0',
      platform: 'ios',
      events: [
        { name: 'paywall_view', at: T0, props: { entry: 'coach' } },
        { name: 'paywall_view', at: T0, props: { entry: 'coach', hrv: 54 } },
        { name: 'recovery_score', at: T0, props: { value: 71 } },
        { name: 'source_check', at: T0, props: { has_stages: true, has_hrv: false, hr_coverage: 'over_90', writer_count: 2 } },
      ],
    };
    await request(s.app).post('/events').set(as('a')).send(batch).expect(403);
    await request(s.app).post('/account/consent').set(as('a')).send({ diagnostics: false, events: true }).expect(200);
    const r = await request(s.app).post('/events').set(as('a')).send(batch).expect(200);
    expect(r.body).toEqual({ kept: 2, dropped: 2 });
    expect(JSON.stringify(s.events)).not.toMatch(/hrv"?:|value/);
  });

  it('feedback stores text and attachments the user chose', async () => {
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47]), Buffer.alloc(10)]).toString('base64');
    const r = await request(s.app)
      .post('/feedback')
      .set(as('a'))
      .send({ text: 'Sleep looks off', appVersion: '1.0.0', platform: 'android', screenshot: png, report: 'HR: OK' })
      .expect(201);
    expect(s.repo.feedback.get(r.body.id)).toMatchObject({ uid: 'a', text: 'Sleep looks off' });
    expect(s.files).toHaveLength(2);
    await request(s.app).post('/feedback').set(as('a')).send({ text: 'x', appVersion: '1', platform: 'ios', screenshot: 'aGVsbG8=' }).expect(400);
  });

  it('account delete is accepted and queued', async () => {
    await request(s.app).post('/account/delete').set(as('a')).expect(202);
    expect(await s.repo.pendingDeletions(10)).toEqual(['a']);
  });

  it('config and health check need no auth', async () => {
    expect((await request(s.app).get('/config').expect(200)).body).toEqual({ minBuild: 1, switches: { sync: false } });
    await request(s.app).get('/healthz').expect(200);
  });
});
