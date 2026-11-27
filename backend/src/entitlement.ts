import type { Entitlement, EntitlementSource, Grant, Purchase } from './model.js';

/**
 * How far past a subscription's expiry we still trust "active" while the
 * renewal notification is on its way (stores renew a little before expiry;
 * notifications can lag). The daily re-check closes anything stale.
 */
export const expirySkewMs = 60 * 60 * 1000;

/**
 * Pro from purchases and grants (Backend plan → Entitlement). Pro when any of:
 * an unrevoked, unrefunded lifetime purchase; a subscription active (and not
 * past expiry plus skew) or in its grace period; an unexpired beta grant.
 * Billing retry without grace and Play's account hold give no access, as
 * both stores advise. The strongest source wins: lifetime, then
 * subscription, then grant.
 */
export function computeEntitlement(purchases: Purchase[], grants: Grant[], now: number): Entitlement {
  const lifetime = purchases.find((p) => p.plan === 'lifetime' && p.state === 'active');
  if (lifetime) {
    return {
      pro: true,
      source: lifetime.store === 'apple' ? 'lifetime_ios' : 'lifetime_android',
      expiresAt: null,
      inGrace: false,
      updatedAt: now,
    };
  }
  const live = purchases.filter(
    (p) =>
      p.plan !== 'lifetime' &&
      ((p.state === 'active' && (p.expiresAt === null || p.expiresAt + expirySkewMs > now)) || p.state === 'grace'),
  );
  if (live.length > 0) {
    const best = live.reduce((a, b) => ((b.expiresAt ?? Infinity) > (a.expiresAt ?? Infinity) ? b : a));
    const source: EntitlementSource = best.store === 'apple' ? 'ios_sub' : 'android_sub';
    return {
      pro: true,
      source,
      expiresAt: best.expiresAt,
      inGrace: live.every((p) => p.state === 'grace'),
      updatedAt: now,
    };
  }
  const grant = grants
    .filter((g) => g.expiresAt === null || g.expiresAt > now)
    .sort((a, b) => (b.expiresAt ?? Infinity) - (a.expiresAt ?? Infinity))[0];
  if (grant) {
    return { pro: true, source: 'beta_grant', expiresAt: grant.expiresAt, inGrace: false, updatedAt: now };
  }
  return { pro: false, source: 'none', expiresAt: null, inGrace: false, updatedAt: now };
}

/** True when the user holds a lifetime purchase and a renewing subscription (the app prompts to cancel it). */
export function lifetimeWithSubscription(purchases: Purchase[]): boolean {
  return (
    purchases.some((p) => p.plan === 'lifetime' && p.state === 'active') &&
    purchases.some((p) => p.plan !== 'lifetime' && (p.state === 'active' || p.state === 'grace'))
  );
}
