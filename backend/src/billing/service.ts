import { appAccountToken, obfuscatedAccountId } from '../account_ids.js';
import { computeEntitlement } from '../entitlement.js';
import type { Entitlement, Purchase } from '../model.js';
import type { Repo } from '../repo.js';
import { payloadHash, purchaseFromApple, type AppleVerifier } from './apple.js';
import { purchaseFromPlayProduct, purchaseFromPlaySubscription, type PlayApi, type Rtdn } from './google.js';
import { playLifetimeProductId, playSubscriptionId } from '../products.js';

/** The purchase was made under another account; the app offers to move it on restore. */
export class OtherAccountError extends Error {
  constructor(readonly purchaseId: string) {
    super('purchase belongs to another account');
  }
}

export interface BillingDeps {
  repo: Repo;
  apple: AppleVerifier;
  play: PlayApi;
  /** The Play package name we accept notifications for. */
  packageName: string;
  now: () => number;
}

export class BillingService {
  constructor(private readonly d: BillingDeps) {}

  /** Recomputes and stores a user's entitlement from everything they hold. */
  async refreshEntitlement(uid: string): Promise<Entitlement> {
    const [purchases, grants] = await Promise.all([this.d.repo.purchasesFor(uid), this.d.repo.grantsFor(uid)]);
    const e = computeEntitlement(purchases, grants, this.d.now());
    await this.d.repo.putEntitlement(uid, e);
    return e;
  }

  /**
   * Stores a verified purchase for [uid]. A purchase first verified by one
   * account stays with it: another account gets OtherAccountError unless
   * [move] is set (restore, after the user confirms), which re-points it and
   * refreshes both accounts.
   */
  private async attach(p: Omit<Purchase, 'uid'>, uid: string, move: boolean): Promise<Purchase> {
    const existing = await this.d.repo.getPurchase(p.id);
    let owner = existing?.uid ?? null;
    if (owner === null && p.accountRef) {
      const expected = p.store === 'apple' ? appAccountToken(uid) : obfuscatedAccountId(uid);
      if (p.accountRef !== expected && !move) throw new OtherAccountError(p.id);
      owner = uid;
    }
    if (owner !== null && owner !== uid && !move) throw new OtherAccountError(p.id);
    const stored: Purchase = { ...p, uid };
    await this.d.repo.putPurchase(stored);
    if (owner !== null && owner !== uid) await this.refreshEntitlement(owner);
    return stored;
  }

  async verifyApple(uid: string, signedTransaction: string, move = false) {
    const t = await this.d.apple.transaction(signedTransaction);
    const p = purchaseFromApple(t, null, this.d.now());
    await this.attach(p, uid, move);
    return this.refreshEntitlement(uid);
  }

  async verifyGoogle(uid: string, productId: string, token: string, move = false) {
    const now = this.d.now();
    let p: Omit<Purchase, 'uid'>;
    if (productId === playSubscriptionId) {
      const s = await this.d.play.subscription(token);
      p = purchaseFromPlaySubscription(token, s, now);
      await this.attach(p, uid, move);
      // Unacknowledged purchases are refunded after 3 days.
      if (s.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && p.state !== 'pending') {
        await this.d.play.acknowledgeSubscription(playSubscriptionId, token);
      }
    } else {
      const pr = await this.d.play.product(productId, token);
      p = purchaseFromPlayProduct(token, productId, pr, now);
      await this.attach(p, uid, move);
      if (pr.acknowledgementState === 0 && p.state === 'active') {
        await this.d.play.acknowledgeProduct(productId, token);
      }
    }
    return this.refreshEntitlement(uid);
  }

  /**
   * App Store Server Notifications V2. Idempotent: the notification id is
   * stored first, and a replay changes nothing. Returns false for a replay.
   */
  async appleNotification(signedPayload: string): Promise<boolean> {
    const n = await this.d.apple.notification(signedPayload);
    const id = `apple:${n.notificationUUID ?? payloadHash(signedPayload)}`;
    const fresh = await this.d.repo.recordBillingEvent(id, {
      store: 'apple',
      type: n.notificationType ?? 'UNKNOWN',
      subtype: n.subtype ?? null,
      payloadHash: payloadHash(signedPayload),
      at: this.d.now(),
    });
    if (!fresh) return false;
    const st = n.data?.signedTransactionInfo;
    if (!st) return true; // TEST, CONSUMPTION_REQUEST and others carry no transaction.
    const t = await this.d.apple.transaction(st);
    const r = n.data?.signedRenewalInfo ? await this.d.apple.renewalInfo(n.data.signedRenewalInfo) : null;
    await this.applyStoreUpdate(purchaseFromApple(t, r, this.d.now()));
    return true;
  }

  /** Play real-time developer notification (Pub/Sub). Re-fetches the purchase; never trusts the message body for state. */
  async playNotification(messageId: string, n: Rtdn): Promise<boolean> {
    if (n.packageName && n.packageName !== this.d.packageName) return false;
    const fresh = await this.d.repo.recordBillingEvent(`google:${messageId}`, {
      store: 'google',
      type: n.subscriptionNotification
        ? `subscription:${n.subscriptionNotification.notificationType}`
        : n.oneTimeProductNotification
          ? `one_time:${n.oneTimeProductNotification.notificationType}`
          : n.voidedPurchaseNotification
            ? 'voided'
            : 'test',
      subtype: null,
      payloadHash: payloadHash(JSON.stringify(n)),
      at: this.d.now(),
    });
    if (!fresh) return false;
    const now = this.d.now();
    if (n.subscriptionNotification?.purchaseToken) {
      const token = n.subscriptionNotification.purchaseToken;
      await this.applyStoreUpdate(purchaseFromPlaySubscription(token, await this.d.play.subscription(token), now));
    } else if (n.oneTimeProductNotification?.purchaseToken) {
      const token = n.oneTimeProductNotification.purchaseToken;
      const sku = n.oneTimeProductNotification.sku ?? playLifetimeProductId;
      await this.applyStoreUpdate(purchaseFromPlayProduct(token, sku, await this.d.play.product(sku, token), now));
    } else if (n.voidedPurchaseNotification?.purchaseToken) {
      const existing = await this.d.repo.getPurchase(`google:${n.voidedPurchaseNotification.purchaseToken}`);
      if (existing) {
        await this.d.repo.putPurchase({ ...existing, state: 'revoked', updatedAt: now });
        if (existing.uid) await this.refreshEntitlement(existing.uid);
      }
    }
    return true;
  }

  /**
   * A store update for a purchase we may or may not know. Known: keep its
   * uid, refresh that account. Unknown with an account reference: held
   * until the app verifies it (the app always does, right after buying).
   */
  private async applyStoreUpdate(p: Omit<Purchase, 'uid'>) {
    const existing = await this.d.repo.getPurchase(p.id);
    const uid = existing?.uid ?? null;
    await this.d.repo.putPurchase({ ...p, uid });
    if (uid) await this.refreshEntitlement(uid);
  }

  /** Daily job: re-fetch subscriptions that should have changed by now. */
  async recheck(limit = 500): Promise<number> {
    const due = await this.d.repo.purchasesToRecheck(limit);
    const now = this.d.now();
    let n = 0;
    for (const p of due) {
      if (p.store === 'google') {
        const token = p.id.slice('google:'.length);
        await this.applyStoreUpdate(purchaseFromPlaySubscription(token, await this.d.play.subscription(token), now));
      } else if (p.expiresAt !== null && p.expiresAt + 24 * 3600_000 < now && p.state === 'active') {
        // Apple: no renewal notice a day after expiry; treat as expired until one arrives.
        await this.d.repo.putPurchase({ ...p, state: 'expired', updatedAt: now });
        if (p.uid) await this.refreshEntitlement(p.uid);
      }
      n++;
    }
    return n;
  }
}
