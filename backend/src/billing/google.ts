import type { Purchase, PurchaseState } from '../model.js';
import { playBasePlans, playLifetimeProductId, playSubscriptionId } from '../products.js';

/** Fields we use from androidpublisher v3 purchases.subscriptionsv2.get. */
export interface PlaySubscription {
  subscriptionState?: string | null;
  acknowledgementState?: string | null;
  testPurchase?: object | null;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string | null } | null;
  lineItems?: Array<{
    productId?: string | null;
    expiryTime?: string | null;
    offerDetails?: { basePlanId?: string | null } | null;
  }> | null;
}

/** Fields we use from purchases.products.get. */
export interface PlayProduct {
  purchaseState?: number | null; // 0 purchased, 1 canceled, 2 pending
  acknowledgementState?: number | null; // 0 not yet, 1 acknowledged
  purchaseType?: number | null; // 0 test (licence tester)
  obfuscatedExternalAccountId?: string | null;
}

/** The Play Developer API calls the api makes; googleapis in production (google_play.ts). */
export interface PlayApi {
  subscription(token: string): Promise<PlaySubscription>;
  product(productId: string, token: string): Promise<PlayProduct>;
  acknowledgeSubscription(subscriptionId: string, token: string): Promise<void>;
  acknowledgeProduct(productId: string, token: string): Promise<void>;
}

export class PlayProductError extends Error {}

const subStates: Record<string, PurchaseState> = {
  SUBSCRIPTION_STATE_ACTIVE: 'active',
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: 'grace',
  SUBSCRIPTION_STATE_ON_HOLD: 'billing_retry',
  SUBSCRIPTION_STATE_PAUSED: 'expired',
  SUBSCRIPTION_STATE_EXPIRED: 'expired',
  SUBSCRIPTION_STATE_PENDING: 'pending',
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: 'expired',
};

export function purchaseFromPlaySubscription(token: string, s: PlaySubscription, now: number): Omit<Purchase, 'uid'> {
  const item = s.lineItems?.[0];
  if (!item || item.productId !== playSubscriptionId) {
    throw new PlayProductError(`unknown Play subscription ${item?.productId ?? '(none)'}`);
  }
  const plan = playBasePlans[item.offerDetails?.basePlanId ?? ''];
  if (!plan) throw new PlayProductError(`unknown base plan ${item.offerDetails?.basePlanId ?? '(none)'}`);
  const expiresAt = item.expiryTime ? Date.parse(item.expiryTime) : null;
  let state: PurchaseState;
  if (s.subscriptionState === 'SUBSCRIPTION_STATE_CANCELED') {
    // Cancelled means "won't renew": access runs to the end of the period.
    state = expiresAt !== null && expiresAt > now ? 'active' : 'expired';
  } else {
    state = subStates[s.subscriptionState ?? ''] ?? 'expired';
  }
  return {
    id: `google:${token}`,
    store: 'google',
    plan,
    productId: `${playSubscriptionId}:${plan}`,
    state,
    accountRef: s.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    expiresAt,
    environment: s.testPurchase ? 'sandbox' : 'production',
    updatedAt: now,
  };
}

export function purchaseFromPlayProduct(token: string, productId: string, p: PlayProduct, now: number): Omit<Purchase, 'uid'> {
  if (productId !== playLifetimeProductId) throw new PlayProductError(`unknown Play product ${productId}`);
  const state: PurchaseState = p.purchaseState === 0 ? 'active' : p.purchaseState === 2 ? 'pending' : 'refunded';
  return {
    id: `google:${token}`,
    store: 'google',
    plan: 'lifetime',
    productId,
    state,
    accountRef: p.obfuscatedExternalAccountId ?? null,
    expiresAt: null,
    environment: p.purchaseType === 0 ? 'sandbox' : 'production',
    updatedAt: now,
  };
}

/** A Play real-time developer notification, after base64-decoding the Pub/Sub message data. */
export interface Rtdn {
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: { notificationType?: number; purchaseToken?: string; subscriptionId?: string };
  oneTimeProductNotification?: { notificationType?: number; purchaseToken?: string; sku?: string };
  voidedPurchaseNotification?: { purchaseToken?: string; orderId?: string; productType?: number };
  testNotification?: { version?: string };
}
