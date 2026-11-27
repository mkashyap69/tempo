// Production wiring of the interfaces the api depends on. Thin on purpose:
// the logic lives in the tested modules; these only call Google and Apple.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { Environment, SignedDataVerifier, VerificationException } from '@apple/app-store-server-library';
import type { App } from 'firebase-admin/app';
import { getAppCheck } from 'firebase-admin/app-check';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { OAuth2Client } from 'google-auth-library';
import { google } from 'googleapis';
import type { Verifier } from './auth.js';
import { InvalidSignatureError, type AppleVerifier } from './billing/apple.js';
import type { PlayApi } from './billing/google.js';
import type { EventRow } from './events.js';
import type { Entitlement, Grant, Purchase, UserDoc } from './model.js';
import type { Repo } from './repo.js';

export function firebaseVerifier(app: App): Verifier {
  return {
    async idToken(token) {
      const t = await getAuth(app).verifyIdToken(token, true);
      return { uid: t.uid, anonymous: t.firebase.sign_in_provider === 'anonymous', email: t.email ?? null };
    },
    async appCheck(token) {
      await getAppCheck(app).verifyToken(token);
    },
  };
}

/**
 * Apple's verifier for production and sandbox. Root certificates are
 * Apple's (AppleRootCA-G3.cer etc. from apple.com/certificateauthority),
 * shipped in the container image under APPLE_ROOT_CA_DIR.
 */
export function appleVerifier(opts: { rootCaDir: string; bundleId: string; appAppleId?: number }): AppleVerifier {
  const roots = readdirSync(opts.rootCaDir)
    .filter((f) => f.endsWith('.cer'))
    .map((f) => readFileSync(join(opts.rootCaDir, f)));
  const prod = new SignedDataVerifier(roots, true, Environment.PRODUCTION, opts.bundleId, opts.appAppleId);
  const sandbox = new SignedDataVerifier(roots, true, Environment.SANDBOX, opts.bundleId);
  // Try production first; TestFlight and review purchases are sandbox.
  async function either<T>(f: (v: SignedDataVerifier) => Promise<T>): Promise<T> {
    try {
      return await f(prod);
    } catch (e) {
      if (!(e instanceof VerificationException)) throw e;
      try {
        return await f(sandbox);
      } catch (e2) {
        if (e2 instanceof VerificationException) throw new InvalidSignatureError(`status ${e2.status}`);
        throw e2;
      }
    }
  }
  return {
    transaction: (j) => either((v) => v.verifyAndDecodeTransaction(j)),
    renewalInfo: (j) => either((v) => v.verifyAndDecodeRenewalInfo(j)),
    notification: (j) => either((v) => v.verifyAndDecodeNotification(j)),
  };
}

export function playApi(packageName: string): PlayApi {
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const ap = google.androidpublisher({ version: 'v3', auth });
  return {
    async subscription(token) {
      return (await ap.purchases.subscriptionsv2.get({ packageName, token })).data;
    },
    async product(productId, token) {
      return (await ap.purchases.products.get({ packageName, productId, token })).data;
    },
    async acknowledgeSubscription(subscriptionId, token) {
      await ap.purchases.subscriptions.acknowledge({ packageName, subscriptionId, token, requestBody: {} });
    },
    async acknowledgeProduct(productId, token) {
      await ap.purchases.products.acknowledge({ packageName, productId, token, requestBody: {} });
    },
  };
}

/** Pub/Sub push carries a Google-signed OIDC token for the push service account. */
export function pubsubPushVerifier(opts: { audience: string; serviceAccountEmail: string }) {
  const client = new OAuth2Client();
  return async (authorization: string | undefined) => {
    const token = authorization?.match(/^Bearer (.+)$/)?.[1];
    if (!token) throw new Error('no token');
    const t = await client.verifyIdToken({ idToken: token, audience: opts.audience });
    const p = t.getPayload();
    if (!p?.email_verified || p.email !== opts.serviceAccountEmail) throw new Error('wrong push identity');
  };
}

export function bigQueryEvents(opts: { projectId: string; dataset: string; table: string }) {
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/bigquery.insertdata'] });
  const bq = google.bigquery({ version: 'v2', auth });
  return async (rows: EventRow[]) => {
    await bq.tabledata.insertAll({
      projectId: opts.projectId,
      datasetId: opts.dataset,
      tableId: opts.table,
      requestBody: { skipInvalidRows: true, rows: rows.map((json) => ({ json: { ...json } })) },
    });
  };
}

export function feedbackFiles(app: App, bucket: string) {
  return async (id: string, files: { name: string; contentType: string; data: Buffer }[]) => {
    const b = getStorage(app).bucket(bucket);
    const paths: string[] = [];
    for (const f of files) {
      const path = `${id}/${f.name}`;
      await b.file(path).save(f.data, { contentType: f.contentType, resumable: false });
      paths.push(`gs://${bucket}/${path}`);
    }
    return paths;
  };
}

/**
 * Firestore layout (Backend plan → Data model). Purchases are keyed by a
 * hash-safe id: Firestore ids can't contain "/", which Play tokens can't
 * either, but are capped at 1500 bytes, so tokens are used as-is.
 */
export class FirestoreRepo implements Repo {
  constructor(
    private readonly db: Firestore,
    private readonly opts: { app: App; syncBucket: string },
  ) {}

  private pid(id: string) {
    return this.db.collection('purchases').doc(id.replace(/\//g, '_'));
  }

  async getUser(uid: string) {
    const s = await this.db.collection('users').doc(uid).get();
    return s.exists ? (s.data() as UserDoc) : null;
  }
  async createUserIfMissing(user: UserDoc) {
    try {
      await this.db.collection('users').doc(user.uid).create(user);
      return true;
    } catch (e) {
      if ((e as { code?: number }).code === 6) return false; // ALREADY_EXISTS
      throw e;
    }
  }
  async updateConsent(uid: string, consent: UserDoc['consent']) {
    await this.db.collection('users').doc(uid).set({ consent }, { merge: true });
  }
  async getPurchase(id: string) {
    const s = await this.pid(id).get();
    return s.exists ? (s.data() as Purchase) : null;
  }
  async putPurchase(p: Purchase) {
    await this.pid(p.id).set(p);
  }
  async purchasesFor(uid: string) {
    return (await this.db.collection('purchases').where('uid', '==', uid).get()).docs.map((d) => d.data() as Purchase);
  }
  async purchasesToRecheck(limit: number) {
    const q = await this.db
      .collection('purchases')
      .where('state', 'in', ['active', 'grace', 'billing_retry'])
      .where('plan', 'in', ['monthly', 'yearly'])
      .orderBy('updatedAt')
      .limit(limit)
      .get();
    return q.docs.map((d) => d.data() as Purchase);
  }
  async grantsFor(uid: string) {
    return (await this.db.collection('users').doc(uid).collection('grants').get()).docs.map((d) => d.data() as Grant);
  }
  async putGrant(uid: string, g: Grant) {
    await this.db.collection('users').doc(uid).collection('grants').add(g);
  }
  async getEntitlement(uid: string) {
    const s = await this.db.collection('entitlements').doc(uid).get();
    return s.exists ? (s.data() as Entitlement) : null;
  }
  async putEntitlement(uid: string, e: Entitlement) {
    await this.db.collection('entitlements').doc(uid).set(e);
  }
  async recordBillingEvent(id: string, ev: Record<string, unknown>) {
    try {
      await this.db.collection('billing_events').doc(id.replace(/\//g, '_')).create(ev);
      return true;
    } catch (e) {
      if ((e as { code?: number }).code === 6) return false;
      throw e;
    }
  }
  async putFeedback(id: string, doc: Record<string, unknown>) {
    await this.db.collection('feedback').doc(id).set(doc);
  }
  async requestDeletion(uid: string, at: number) {
    await this.db.collection('deletions').doc(uid).set({ requestedAt: at, completedAt: null, steps: [] }, { merge: true });
  }
  async pendingDeletions(limit: number) {
    return (await this.db.collection('deletions').where('completedAt', '==', null).limit(limit).get()).docs.map((d) => d.id);
  }
  async deleteUserData(uid: string, at: number) {
    const steps: string[] = [];
    await getStorage(this.opts.app).bucket(this.opts.syncBucket).deleteFiles({ prefix: `u/${uid}/`, force: true });
    steps.push('sync_bucket');
    for (const sub of ['grants']) {
      await this.db.recursiveDelete(this.db.collection('users').doc(uid).collection(sub));
    }
    await this.db.recursiveDelete(this.db.collection('devices').doc(uid));
    for (const c of ['users', 'entitlements', 'sync_manifests']) await this.db.collection(c).doc(uid).delete();
    steps.push('firestore');
    const purchases = await this.db.collection('purchases').where('uid', '==', uid).get();
    for (const d of purchases.docs) await d.ref.update({ uid: null });
    const feedback = await this.db.collection('feedback').where('uid', '==', uid).get();
    for (const d of feedback.docs) await d.ref.update({ uid: null });
    steps.push('anonymised');
    try {
      await getAuth(this.opts.app).deleteUser(uid);
    } catch (e) {
      if ((e as { code?: string }).code !== 'auth/user-not-found') throw e;
    }
    steps.push('auth');
    await this.db.collection('deletions').doc(uid).set({ completedAt: at, steps: FieldValue.arrayUnion(...steps) }, { merge: true });
  }
}
