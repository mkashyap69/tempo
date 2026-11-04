// Store products (Backend plan → Billing on GCP → Products). The app's
// app/lib/src/billing/products.dart holds the same ids.

export type Plan = 'monthly' | 'yearly' | 'lifetime';

/** iOS product ids: auto-renewable subscriptions in group "Pro", and a non-consumable. */
export const appleProducts: Record<string, Plan> = {
  'tempo.pro.monthly': 'monthly',
  'tempo.pro.yearly': 'yearly',
  'tempo.pro.lifetime': 'lifetime',
};

/** Play: one subscription with two base plans, and a one-time product. */
export const playSubscriptionId = 'pro';
export const playBasePlans: Record<string, Plan> = { monthly: 'monthly', yearly: 'yearly' };
export const playLifetimeProductId = 'pro_lifetime';
