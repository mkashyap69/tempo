import { beforeEach, describe, expect, it } from 'vitest';
import { purchaseFromApple } from '../src/billing/apple.js';
import { purchaseFromPlayProduct, purchaseFromPlaySubscription } from '../src/billing/google.js';
import { BillingService, OtherAccountError } from '../src/billing/service.js';
import { obfuscatedAccountId } from '../src/account_ids.js';
import { MemoryRepo } from '../src/repo.js';
import { DAY, FakePlay, T0, appleTx, fakeApple, playSub, sign } from './fakes.js';

describe('Apple normalisation', () => {
  it('maps subscription states from the signed data', () => {
    const t = appleTx('u');
    expect(purchaseFromApple(t, null, T0).state).toBe('active');
    expect(purchaseFromApple({ ...t, expiresDate: T0 - 1 }, { gracePeriodExpiresDate: T0 + DAY }, T0)).toMatchObject({ state: 'grace', expiresAt: T0 + DAY });
    expect(purchaseFromApple({ ...t, expiresDate: T0 - 1 }, { isInBillingRetryPeriod: true }, T0).state).toBe('billing_retry');
    expect(purchaseFromApple({ ...t, expiresDate: T0 - 1 }, {}, T0).state).toBe('expired');
    expect(purchaseFromApple({ ...t, revocationDate: T0 - 1 }, null, T0).state).toBe('revoked');
  });
  it('lifetime is active with no expiry; unknown products are refused', () => {
    expect(purchaseFromApple(appleTx('u', { productId: 'tempo.pro.lifetime', expiresDate: undefined, type: 'Non-Consumable' }), null, T0)).toMatchObject({
      plan: 'lifetime',
      state: 'active',
      expiresAt: null,
    });
    expect(() => purchaseFromApple(appleTx('u', { productId: 'other' }), null, T0)).toThrow();
  });
  it('keys purchases by original transaction, so renewals update one row', () => {
    expect(purchaseFromApple(appleTx('u', { transactionId: '2000' }), null, T0).id).toBe('apple:1000');
  });
});

describe('Play normalisation', () => {
  it('maps subscription states', () => {
    const s = playSub('u');
    expect(purchaseFromPlaySubscription('t', s, T0)).toMatchObject({ state: 'active', plan: 'yearly', environment: 'sandbox' });
    expect(purchaseFromPlaySubscription('t', { ...s, subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' }, T0).state).toBe('grace');
    expect(purchaseFromPlaySubscription('t', { ...s, subscriptionState: 'SUBSCRIPTION_STATE_ON_HOLD' }, T0).state).toBe('billing_retry');
    expect(purchaseFromPlaySubscription('t', { ...s, subscriptionState: 'SUBSCRIPTION_STATE_CANCELED' }, T0).state).toBe('active');
    expect(purchaseFromPlaySubscription('t', playSub('u', { subscriptionState: 'SUBSCRIPTION_STATE_CANCELED' }, 'yearly', T0 - 1), T0).state).toBe('expired');
  });
  it('maps one-time purchase states', () => {
    expect(purchaseFromPlayProduct('t', 'pro_lifetime', { purchaseState: 0 }, T0).state).toBe('active');
    expect(purchaseFromPlayProduct('t', 'pro_lifetime', { purchaseState: 2 }, T0).state).toBe('pending');
    expect(purchaseFromPlayProduct('t', 'pro_lifetime', { purchaseState: 1 }, T0).state).toBe('refunded');
    expect(() => purchaseFromPlayProduct('t', 'other', { purchaseState: 0 }, T0)).toThrow();
  });
});

describe('BillingService', () => {
  let repo: MemoryRepo;
  let play: FakePlay;
  let now: number;
  let svc: BillingService;
  beforeEach(() => {
    repo = new MemoryRepo();
    play = new FakePlay();
    now = T0;
    svc = new BillingService({ repo, apple: fakeApple, play, packageName: 'dev.tempo.tempo', now: () => now });
  });

  it('iOS purchase, then renewal and refund by notification', async () => {
    expect(await svc.verifyApple('alice', sign(appleTx('alice')))).toMatchObject({ pro: true, source: 'ios_sub' });
    now = T0 + 366 * DAY;
    const renewed = appleTx('alice', { transactionId: '1001', expiresDate: T0 + 731 * DAY });
    await svc.appleNotification(sign({ notificationUUID: 'n1', notificationType: 'DID_RENEW', data: { signedTransactionInfo: sign(renewed) } }));
    expect(await repo.getEntitlement('alice')).toMatchObject({ pro: true, expiresAt: T0 + 731 * DAY });
    await svc.appleNotification(sign({ notificationUUID: 'n2', notificationType: 'REFUND', data: { signedTransactionInfo: sign({ ...renewed, revocationDate: now }) } }));
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
  });

  it('a replayed notification changes nothing', async () => {
    await svc.verifyApple('alice', sign(appleTx('alice')));
    const refund = sign({ notificationUUID: 'n9', notificationType: 'REFUND', data: { signedTransactionInfo: sign(appleTx('alice', { revocationDate: T0 })) } });
    expect(await svc.appleNotification(refund)).toBe(true);
    // The user buys again; a replay of the old refund must not undo it.
    await svc.verifyApple('alice', sign(appleTx('alice')));
    expect(await svc.appleNotification(refund)).toBe(false);
    expect((await repo.getEntitlement('alice'))!.pro).toBe(true);
  });

  it('expiry and lapse: grace keeps Pro, then it ends', async () => {
    await svc.verifyApple('alice', sign(appleTx('alice', { expiresDate: T0 + DAY })));
    now = T0 + 2 * DAY;
    const lapsed = appleTx('alice', { expiresDate: T0 + DAY });
    await svc.appleNotification(sign({ notificationUUID: 'g', notificationType: 'DID_FAIL_TO_RENEW', subtype: 'GRACE_PERIOD', data: { signedTransactionInfo: sign(lapsed), signedRenewalInfo: sign({ gracePeriodExpiresDate: T0 + 5 * DAY }) } }));
    expect(await repo.getEntitlement('alice')).toMatchObject({ pro: true, inGrace: true });
    now = T0 + 6 * DAY;
    await svc.appleNotification(sign({ notificationUUID: 'e', notificationType: 'EXPIRED', data: { signedTransactionInfo: sign(lapsed), signedRenewalInfo: sign({}) } }));
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
  });

  it('a receipt from another account is refused, and moves only when asked', async () => {
    await svc.verifyApple('alice', sign(appleTx('alice')));
    await expect(svc.verifyApple('bob', sign(appleTx('alice')))).rejects.toBeInstanceOf(OtherAccountError);
    expect(await svc.verifyApple('bob', sign(appleTx('alice')), true)).toMatchObject({ pro: true });
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
  });

  it('a store account token for another uid is refused before first verify', async () => {
    await expect(svc.verifyApple('bob', sign(appleTx('alice')))).rejects.toBeInstanceOf(OtherAccountError);
  });

  it('Android subscription is verified and acknowledged once', async () => {
    play.subs.set('tok', playSub('alice'));
    expect(await svc.verifyGoogle('alice', 'pro', 'tok')).toMatchObject({ pro: true, source: 'android_sub' });
    await svc.verifyGoogle('alice', 'pro', 'tok');
    expect(play.acked).toEqual(['tok']);
  });

  it('a pending Android purchase is not acknowledged and gives no Pro', async () => {
    play.subs.set('tok', playSub('alice', { subscriptionState: 'SUBSCRIPTION_STATE_PENDING' }));
    expect((await svc.verifyGoogle('alice', 'pro', 'tok')).pro).toBe(false);
    expect(play.acked).toEqual([]);
  });

  it('cross-platform: an iOS lifetime unlocks the account on Android', async () => {
    const e = await svc.verifyApple('alice', sign(appleTx('alice', { productId: 'tempo.pro.lifetime', expiresDate: undefined, originalTransactionId: 'L1' })));
    expect(e).toMatchObject({ pro: true, source: 'lifetime_ios', expiresAt: null });
    // Android reads the same entitlements/{uid}.
    expect(await repo.getEntitlement('alice')).toMatchObject({ pro: true });
  });

  it('Play notifications: renewal, account hold, voided purchase', async () => {
    play.subs.set('tok', playSub('alice'));
    await svc.verifyGoogle('alice', 'pro', 'tok');
    play.subs.set('tok', playSub('alice', { subscriptionState: 'SUBSCRIPTION_STATE_ON_HOLD' }));
    await svc.playNotification('m1', { packageName: 'dev.tempo.tempo', subscriptionNotification: { notificationType: 5, purchaseToken: 'tok', subscriptionId: 'pro' } });
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
    play.subs.set('tok', playSub('alice', { subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE' }));
    await svc.playNotification('m2', { packageName: 'dev.tempo.tempo', subscriptionNotification: { notificationType: 1, purchaseToken: 'tok', subscriptionId: 'pro' } });
    expect((await repo.getEntitlement('alice'))!.pro).toBe(true);
    await svc.playNotification('m3', { packageName: 'dev.tempo.tempo', voidedPurchaseNotification: { purchaseToken: 'tok', productType: 1 } });
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
    // Replay of m2 is ignored.
    expect(await svc.playNotification('m2', { packageName: 'dev.tempo.tempo', subscriptionNotification: { notificationType: 1, purchaseToken: 'tok' } })).toBe(false);
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
  });

  it('notifications for another package are ignored', async () => {
    expect(await svc.playNotification('x', { packageName: 'com.other' })).toBe(false);
  });

  it('Play lifetime is acknowledged; upgrade from monthly to yearly keeps Pro', async () => {
    play.products.set('lt', { purchaseState: 0, acknowledgementState: 0, obfuscatedExternalAccountId: obfuscatedAccountId('alice') });
    expect(await svc.verifyGoogle('alice', 'pro_lifetime', 'lt')).toMatchObject({ source: 'lifetime_android' });
    expect(play.acked).toContain('lt');
    play.subs.set('m', playSub('bob', {}, 'monthly', T0 + 30 * DAY));
    await svc.verifyGoogle('bob', 'pro', 'm');
    play.subs.set('m', playSub('bob', { subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' }, 'monthly', T0));
    play.subs.set('y', playSub('bob', {}, 'yearly'));
    await svc.verifyGoogle('bob', 'pro', 'y');
    await svc.playNotification('m9', { packageName: 'dev.tempo.tempo', subscriptionNotification: { notificationType: 13, purchaseToken: 'm' } });
    expect(await repo.getEntitlement('bob')).toMatchObject({ pro: true, expiresAt: T0 + 365 * DAY });
  });

  it('the daily re-check expires a silent Apple subscription', async () => {
    await svc.verifyApple('alice', sign(appleTx('alice', { expiresDate: T0 + DAY })));
    now = T0 + 3 * DAY;
    await svc.recheck();
    expect((await repo.getEntitlement('alice'))!.pro).toBe(false);
  });
});
