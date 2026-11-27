import type { BillingService } from '../billing/service.js';
import type { Repo } from '../repo.js';

/** Cloud Run job "deletions": finishes requested account deletions (usually minutes, within 30 days). */
export async function runDeletions(repo: Repo, now: () => number, limit = 200): Promise<number> {
  const uids = await repo.pendingDeletions(limit);
  for (const uid of uids) await repo.deleteUserData(uid, now());
  return uids.length;
}

/** Cloud Run job "recheck": daily entitlement re-check of subscriptions. */
export async function runRecheck(billing: BillingService, limit = 500): Promise<number> {
  return billing.recheck(limit);
}
