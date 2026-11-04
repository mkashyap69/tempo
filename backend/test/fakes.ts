import { appAccountToken, obfuscatedAccountId } from '../src/account_ids.js';
import { InvalidSignatureError, type AppleRenewalInfo, type AppleTransaction, type AppleVerifier } from '../src/billing/apple.js';
import type { PlayApi, PlayProduct, PlaySubscription } from '../src/billing/google.js';

export const DAY = 86_400_000;
export const T0 = Date.parse('2026-11-04T08:00:00Z');

/** "Signed" Apple data in tests is JSON with a prefix; the fake verifier decodes it. */
export const sign = (o: object) => `signed.${Buffer.from(JSON.stringify(o)).toString('base64url')}`;
const unsign = <T>(s: string): T => {
  if (!s.startsWith('signed.')) throw new InvalidSignatureError('bad signature');
  return JSON.parse(Buffer.from(s.slice(7), 'base64url').toString()) as T;
};

export const fakeApple: AppleVerifier = {
  transaction: async (j) => unsign<AppleTransaction>(j),
  renewalInfo: async (j) => unsign<AppleRenewalInfo>(j),
  notification: async (j) => unsign(j),
};

export function appleTx(uid: string, o: Partial<AppleTransaction> = {}): AppleTransaction {
  return {
    originalTransactionId: '1000',
    transactionId: '1000',
    productId: 'tempo.pro.yearly',
    type: 'Auto-Renewable Subscription',
    expiresDate: T0 + 365 * DAY,
    appAccountToken: appAccountToken(uid),
    environment: 'Sandbox',
    ...o,
  };
}

export class FakePlay implements PlayApi {
  subs = new Map<string, PlaySubscription>();
  products = new Map<string, PlayProduct>();
  acked: string[] = [];
  async subscription(token: string) {
    const s = this.subs.get(token);
    if (!s) throw new Error('not found');
    return s;
  }
  async product(_id: string, token: string) {
    const p = this.products.get(token);
    if (!p) throw new Error('not found');
    return p;
  }
  async acknowledgeSubscription(_id: string, token: string) {
    this.acked.push(token);
    const s = this.subs.get(token);
    if (s) s.acknowledgementState = 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED';
  }
  async acknowledgeProduct(_id: string, token: string) {
    this.acked.push(token);
    const p = this.products.get(token);
    if (p) p.acknowledgementState = 1;
  }
}

export function playSub(uid: string, o: Partial<PlaySubscription> = {}, basePlan = 'yearly', expiry = T0 + 365 * DAY): PlaySubscription {
  return {
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
    testPurchase: {},
    externalAccountIdentifiers: { obfuscatedExternalAccountId: obfuscatedAccountId(uid) },
    lineItems: [{ productId: 'pro', expiryTime: new Date(expiry).toISOString(), offerDetails: { basePlanId: basePlan } }],
    ...o,
  };
}
