import { describe, expect, it } from 'vitest';
import { computeEntitlement, expirySkewMs, lifetimeWithSubscription } from '../src/entitlement.js';
import type { Purchase } from '../src/model.js';
import { DAY, T0 } from './fakes.js';

const p = (o: Partial<Purchase>): Purchase => ({
  id: 'apple:1',
  store: 'apple',
  plan: 'yearly',
  productId: 'tempo.pro.yearly',
  state: 'active',
  accountRef: null,
  uid: 'u',
  expiresAt: T0 + 30 * DAY,
  environment: 'sandbox',
  updatedAt: T0,
  ...o,
});

describe('computeEntitlement', () => {
  it('nothing held: Free', () => {
    expect(computeEntitlement([], [], T0)).toMatchObject({ pro: false, source: 'none' });
  });
  it('an active subscription: Pro until it expires', () => {
    expect(computeEntitlement([p({})], [], T0)).toMatchObject({ pro: true, source: 'ios_sub', expiresAt: T0 + 30 * DAY, inGrace: false });
  });
  it('a subscription past expiry plus skew: Free, even if still marked active', () => {
    const e = computeEntitlement([p({ expiresAt: T0 - expirySkewMs - 1 })], [], T0);
    expect(e.pro).toBe(false);
  });
  it('grace period keeps Pro; billing retry and account hold do not', () => {
    expect(computeEntitlement([p({ state: 'grace' })], [], T0)).toMatchObject({ pro: true, inGrace: true });
    expect(computeEntitlement([p({ state: 'billing_retry' })], [], T0).pro).toBe(false);
  });
  it('refund and revocation end Pro', () => {
    for (const state of ['refunded', 'revoked', 'expired', 'pending'] as const) {
      expect(computeEntitlement([p({ state })], [], T0).pro).toBe(false);
    }
  });
  it('lifetime wins over a subscription and has no end', () => {
    const e = computeEntitlement([p({}), p({ id: 'google:x', store: 'google', plan: 'lifetime', expiresAt: null })], [], T0);
    expect(e).toMatchObject({ pro: true, source: 'lifetime_android', expiresAt: null });
  });
  it('a revoked lifetime gives nothing', () => {
    expect(computeEntitlement([p({ plan: 'lifetime', expiresAt: null, state: 'revoked' })], [], T0).pro).toBe(false);
  });
  it('two subscriptions (an upgrade mid-period): the later expiry counts', () => {
    const e = computeEntitlement([p({ id: 'a', expiresAt: T0 + 5 * DAY }), p({ id: 'b', store: 'google', expiresAt: T0 + 300 * DAY })], [], T0);
    expect(e).toMatchObject({ source: 'android_sub', expiresAt: T0 + 300 * DAY });
  });
  it('a beta grant gives Pro until it ends, below any purchase', () => {
    expect(computeEntitlement([], [{ kind: 'beta_grant', expiresAt: T0 + DAY }], T0)).toMatchObject({ pro: true, source: 'beta_grant' });
    expect(computeEntitlement([], [{ kind: 'beta_grant', expiresAt: T0 - 1 }], T0).pro).toBe(false);
    expect(computeEntitlement([p({})], [{ kind: 'beta_grant', expiresAt: null }], T0).source).toBe('ios_sub');
  });
  it('flags lifetime bought while subscribed', () => {
    expect(lifetimeWithSubscription([p({}), p({ id: 'l', plan: 'lifetime', expiresAt: null })])).toBe(true);
    expect(lifetimeWithSubscription([p({})])).toBe(false);
  });
});
