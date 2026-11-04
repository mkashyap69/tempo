# backend

Tempo's Cloud Run `api` and jobs, in TypeScript on Node 22 (decision G-O2). Plan: `docs/research/Backend plan.md`; calls: `docs/network.md`.

| Path | What |
| --- | --- |
| `src/app.ts` | Routes: `/account/*`, `/billing/*`, `/webhooks/apple`, `/workers/play-rtdn`, `/events`, `/feedback`, `/config` |
| `src/entitlement.ts` | Who has Pro: lifetime, then subscription (active or grace), then beta grant |
| `src/billing/` | Apple and Play purchases to one model; verify, notifications, daily re-check |
| `src/events.ts` | The opt-in event allow-list; anything else is dropped |
| `src/adapters.ts` | Firestore, Firebase Auth / App Check, Apple's verifier, Play Developer API, BigQuery, Storage |
| `src/workers/jobs.ts` | Jobs: account deletions, entitlement re-check |
| `rules/` | Firestore and Storage security rules |

    npm ci
    npm test        # vitest, no cloud needed
    npm run build

Accounts are plain Firebase Authentication (L-O2): `POST /account/init` creates `users/{uid}` and the beta grant on first call instead of a blocking function. Purchases are bound to the account: `appAccountToken` (UUIDv5 of the uid) on iOS, `obfuscatedAccountId` (SHA-256 of the uid) on Android; a receipt from another account gets 409 `other_account`, and moves only when the app sends `move: true` after the user confirms.

TODO(verify) on the first sandbox purchases: the exact fields Apple and Play return (`purchaseFromApple`, `purchaseFromPlaySubscription`), and that the Play service account is linked in Play Console → API access.
