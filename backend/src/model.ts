import type { Plan } from './products.js';

export type Store = 'apple' | 'google';

/**
 * Where a purchase stands. Subscriptions move between these; a lifetime
 * purchase is active, pending, refunded or revoked.
 * - grace: the store couldn't renew but keeps access during its grace period.
 * - billing_retry: the store is retrying payment and access is off (Apple's
 *   billing retry without grace; Play's account hold).
 */
export type PurchaseState =
  | 'active'
  | 'grace'
  | 'billing_retry'
  | 'pending'
  | 'expired'
  | 'refunded'
  | 'revoked';

export interface Purchase {
  /** apple:<originalTransactionId> or google:<purchaseToken>. */
  id: string;
  store: Store;
  plan: Plan;
  productId: string;
  state: PurchaseState;
  /** The uid the store says it was bought under, if it says. */
  accountRef: string | null;
  /** The uid that verified it with us; null once an account is deleted. */
  uid: string | null;
  /** Epoch ms; null for lifetime. */
  expiresAt: number | null;
  environment: 'sandbox' | 'production';
  updatedAt: number;
}

export type EntitlementSource =
  | 'lifetime_ios'
  | 'lifetime_android'
  | 'ios_sub'
  | 'android_sub'
  | 'beta_grant'
  | 'none';

export interface Entitlement {
  pro: boolean;
  source: EntitlementSource;
  /** Epoch ms when Pro ends without a renewal; null when it doesn't end. */
  expiresAt: number | null;
  inGrace: boolean;
  updatedAt: number;
}

export interface Grant {
  kind: 'beta_grant';
  /** Epoch ms; null for open-ended. */
  expiresAt: number | null;
}

export interface UserDoc {
  uid: string;
  createdAt: number;
  anonymous: boolean;
  email: string | null;
  country: string | null;
  consent: { diagnostics: boolean; events: boolean };
  deletedAt: number | null;
}
