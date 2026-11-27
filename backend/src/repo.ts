import type { Entitlement, Grant, Purchase, UserDoc } from './model.js';

/** Storage the api needs. Firestore in production (firestore_repo.ts), memory in tests. */
export interface Repo {
  getUser(uid: string): Promise<UserDoc | null>;
  createUserIfMissing(user: UserDoc): Promise<boolean>;
  updateConsent(uid: string, consent: UserDoc['consent']): Promise<void>;

  getPurchase(id: string): Promise<Purchase | null>;
  putPurchase(p: Purchase): Promise<void>;
  purchasesFor(uid: string): Promise<Purchase[]>;
  /** Subscriptions to re-check (active, grace or retry), oldest check first. */
  purchasesToRecheck(limit: number): Promise<Purchase[]>;

  grantsFor(uid: string): Promise<Grant[]>;
  putGrant(uid: string, g: Grant): Promise<void>;

  getEntitlement(uid: string): Promise<Entitlement | null>;
  putEntitlement(uid: string, e: Entitlement): Promise<void>;

  /**
   * Stores a store notification before it's processed. False when the id was
   * seen before (the notification is a replay).
   */
  recordBillingEvent(id: string, ev: { store: string; type: string; subtype: string | null; payloadHash: string; at: number }): Promise<boolean>;

  putFeedback(id: string, doc: Record<string, unknown>): Promise<void>;

  requestDeletion(uid: string, at: number): Promise<void>;
  pendingDeletions(limit: number): Promise<string[]>;
  /** Removes the user's readable data; anonymises purchases (kept for tax law). */
  deleteUserData(uid: string, at: number): Promise<void>;
}

/** In-memory Repo for tests and the local emulator-free run. */
export class MemoryRepo implements Repo {
  users = new Map<string, UserDoc>();
  purchases = new Map<string, Purchase>();
  grants = new Map<string, Grant[]>();
  entitlements = new Map<string, Entitlement>();
  billingEvents = new Map<string, unknown>();
  feedback = new Map<string, Record<string, unknown>>();
  deletions = new Map<string, { requestedAt: number; completedAt: number | null }>();

  async getUser(uid: string) {
    return this.users.get(uid) ?? null;
  }
  async createUserIfMissing(user: UserDoc) {
    if (this.users.has(user.uid)) return false;
    this.users.set(user.uid, user);
    return true;
  }
  async updateConsent(uid: string, consent: UserDoc['consent']) {
    const u = this.users.get(uid);
    if (u) u.consent = consent;
  }
  async getPurchase(id: string) {
    return this.purchases.get(id) ?? null;
  }
  async putPurchase(p: Purchase) {
    this.purchases.set(p.id, { ...p });
  }
  async purchasesFor(uid: string) {
    return [...this.purchases.values()].filter((p) => p.uid === uid);
  }
  async purchasesToRecheck(limit: number) {
    return [...this.purchases.values()]
      .filter((p) => p.plan !== 'lifetime' && ['active', 'grace', 'billing_retry'].includes(p.state))
      .sort((a, b) => a.updatedAt - b.updatedAt)
      .slice(0, limit);
  }
  async grantsFor(uid: string) {
    return this.grants.get(uid) ?? [];
  }
  async putGrant(uid: string, g: Grant) {
    this.grants.set(uid, [...(this.grants.get(uid) ?? []), g]);
  }
  async getEntitlement(uid: string) {
    return this.entitlements.get(uid) ?? null;
  }
  async putEntitlement(uid: string, e: Entitlement) {
    this.entitlements.set(uid, e);
  }
  async recordBillingEvent(id: string, ev: unknown) {
    if (this.billingEvents.has(id)) return false;
    this.billingEvents.set(id, ev);
    return true;
  }
  async putFeedback(id: string, doc: Record<string, unknown>) {
    this.feedback.set(id, doc);
  }
  async requestDeletion(uid: string, at: number) {
    if (!this.deletions.has(uid)) this.deletions.set(uid, { requestedAt: at, completedAt: null });
  }
  async pendingDeletions(limit: number) {
    return [...this.deletions.entries()].filter(([, d]) => d.completedAt === null).map(([u]) => u).slice(0, limit);
  }
  async deleteUserData(uid: string, at: number) {
    this.users.delete(uid);
    this.grants.delete(uid);
    this.entitlements.delete(uid);
    for (const p of this.purchases.values()) if (p.uid === uid) p.uid = null;
    const d = this.deletions.get(uid);
    if (d) d.completedAt = at;
  }
}
