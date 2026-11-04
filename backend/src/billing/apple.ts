import { createHash } from 'node:crypto';
import type { Purchase, PurchaseState } from '../model.js';
import { appleProducts } from '../products.js';

/** The decoded fields we use from a StoreKit 2 transaction (JWSTransactionDecodedPayload). */
export interface AppleTransaction {
  originalTransactionId?: string;
  transactionId?: string;
  productId?: string;
  type?: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
}

/** The decoded fields we use from renewal info (JWSRenewalInfoDecodedPayload). */
export interface AppleRenewalInfo {
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

/** Verifies Apple's signatures; production uses SignedDataVerifier (apple_verifier.ts). */
export interface AppleVerifier {
  transaction(jws: string): Promise<AppleTransaction>;
  renewalInfo(jws: string): Promise<AppleRenewalInfo>;
  notification(signedPayload: string): Promise<{
    notificationUUID?: string;
    notificationType?: string;
    subtype?: string;
    data?: { signedTransactionInfo?: string; signedRenewalInfo?: string };
  }>;
}

export class UnknownProductError extends Error {}

/** Apple's signature or certificate chain didn't verify. */
export class InvalidSignatureError extends Error {}

/**
 * A purchase from Apple's signed data. The state comes from the data
 * itself, not the notification type, so a replay or an out-of-order
 * notification can't move it backwards.
 */
export function purchaseFromApple(
  t: AppleTransaction,
  renewal: AppleRenewalInfo | null,
  now: number,
): Omit<Purchase, 'uid'> {
  const productId = t.productId ?? '';
  const plan = appleProducts[productId];
  if (!plan) throw new UnknownProductError(`unknown Apple product ${productId}`);
  const original = t.originalTransactionId ?? t.transactionId;
  if (!original) throw new Error('transaction has no id');
  let state: PurchaseState;
  if (t.revocationDate) {
    state = 'revoked';
  } else if (plan === 'lifetime') {
    state = 'active';
  } else if ((t.expiresDate ?? 0) > now) {
    state = 'active';
  } else if ((renewal?.gracePeriodExpiresDate ?? 0) > now) {
    state = 'grace';
  } else if (renewal?.isInBillingRetryPeriod) {
    state = 'billing_retry';
  } else {
    state = 'expired';
  }
  const graceEnd = state === 'grace' ? renewal?.gracePeriodExpiresDate ?? null : null;
  return {
    id: `apple:${original}`,
    store: 'apple',
    plan,
    productId,
    state,
    accountRef: t.appAccountToken?.toLowerCase() ?? null,
    expiresAt: plan === 'lifetime' ? null : graceEnd ?? t.expiresDate ?? null,
    environment: t.environment === 'Production' ? 'production' : 'sandbox',
    updatedAt: now,
  };
}

export function payloadHash(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}
