# Backend plan: accounts, billing and encrypted sync on GCP

As of Oct 21, 2026 · Status: direction decided by the owner (see "Decided"); open decisions listed with a recommendation each. Companion to `docs/research/Beta release plan.md`, which this updates for B-O1, B-O2, B-O4 and B-O5.

## Summary

Tempo gets a backend on Google Cloud for four jobs:

1. **Accounts:** sign up and sign in with Apple, Google or email (Firebase Authentication on Identity Platform).
2. **Billing:** Pro by subscription or one-time purchase, verified on our own Cloud Run service against the App Store and Google Play. No third-party billing service.
3. **Encrypted sync:** health data, the journal, workouts, strength sets and settings are encrypted on the phone and stored in Cloud Storage. A new phone gets its history back after sign-in. The server stores bytes it can't read.
4. **Beta operations:** opt-in crash reports (Crashlytics), opt-in usage events (our own endpoint into BigQuery), and feedback the user chooses to send.

Scores stay derived: they're never synced, only recomputed on the phone from the synced raw data, as every score already is today.

## Decided (owner, 2026-10-21)

| # | Decision |
| --- | --- |
| G-D1 | All backend work runs on GCP. |
| G-D2 | Health data is synced to GCP **end-to-end encrypted**: encrypted on the phone with a key the server never holds. Accounts, purchases, feedback and diagnostics are stored readable. |
| G-D3 | Billing runs on GCP: our own receipt verification and store notifications, no RevenueCat. |
| G-D4 | The beta plan's other recommendations stand: Firebase Authentication, opt-in diagnostics with no health values, a domain and an organisation developer account, the Free/Pro split and starting prices. |

## What this changes in the project's rules

| Rule (CLAUDE.md, set earlier today) | Becomes |
| --- | --- |
| "Health data never leaves the phone" | **Health data leaves the phone only end-to-end encrypted.** The server never sees plaintext health data, keys or the band's auth key. The one exception is a feedback report the user reads and chooses to send. |
| "The only network calls are account sign-in and store billing" | Allowed calls: sign-in, billing, encrypted sync, opt-in crash reports and usage events, user-sent feedback. Each call site is listed in `docs/network.md`; anything new needs a line in `docs/decisions.md` first. |

## Architecture

```
Phone (Flutter)
  ├─ Firebase Auth SDK ──────────────► Identity Platform (Apple, Google, email link)
  ├─ App Check (App Attest / Play Integrity) on every call below
  ├─ StoreKit 2 / Play Billing ──────► api (Cloud Run) ──► App Store Server API / Play Developer API
  │                                         │
  │      App Store Server Notifications ───►│ /webhooks/apple
  │      Play real-time notifications ──► Pub/Sub ──► billing worker (Cloud Run)
  │                                         ▼
  ├─ Firestore SDK (read own docs) ◄── Firestore: users, entitlements, devices, sync manifests, feedback
  ├─ Cloud Storage for Firebase ─────► gs://…-sync  (encrypted segments, per-user prefix)
  ├─ Crashlytics (opt-in)
  └─ events (opt-in) ─► api /events ─► Pub/Sub ─► BigQuery (events, billing ledger mirror)

Ops: Secret Manager · Cloud Logging/Monitoring/Error Reporting · Cloud Scheduler · Artifact Registry · Terraform
```

### Services

| Need | GCP service | Why |
| --- | --- | --- |
| Identity | Firebase Authentication upgraded to **Identity Platform** | Apple, Google, email link; blocking functions; SLA; free to 50k monthly users |
| API and webhooks | **Cloud Run** service `api` (TypeScript on Node) | Scales to zero; Apple's official App Store Server Library and Google's API clients exist for Node, not Dart |
| Store notifications (Android) | **Pub/Sub** | Play's real-time developer notifications are delivered to Pub/Sub natively |
| Background jobs | **Cloud Run jobs + Cloud Scheduler** | Account deletion, entitlement re-checks, Firestore exports |
| Operational database | **Firestore** (Native mode) | Serverless, per-user documents, security rules let the app read its own entitlement directly, offline cache in the SDK |
| Encrypted blobs | **Cloud Storage** (through Cloud Storage for Firebase) | Per-user prefix with security rules; object versioning; lifecycle rules |
| Analytics | **BigQuery** | Usage events and a billing-ledger mirror; SQL for the beta's exit metrics |
| Crashes | **Firebase Crashlytics** | Free; collection off until the user opts in |
| Abuse protection | **Firebase App Check** | App Attest (iOS) and Play Integrity (Android) on API, Firestore and Storage |
| Secrets | **Secret Manager** | Apple's signing keys, Play service-account key, webhook secrets |
| Ops | Cloud Logging, Monitoring, Error Reporting | Alerts on webhook failures, billing errors, job failures |
| Infra as code | **Terraform** in `/infra` | Projects, IAM, buckets, Pub/Sub, Cloud Run, Firestore rules deploy |

No Cloud SQL for the beta. Billing is a small append-only ledger, which Firestore holds and BigQuery mirrors for reporting. Revisit if billing queries outgrow Firestore.

### Projects and environments

- `tempo-dev`: development and CI, store sandbox purchases, test accounts.
- `tempo-prod`: the beta and launch. Production store notifications point here.
- Separate Firebase apps per project and per platform; the app picks one by build flavour (`dev`, `prod`).
- Region: see G-O1. Firestore's location can't change after creation, so B0 must pick it.

## Data model

### Firestore (readable; no health data)

| Collection | Key | Fields | Written by | App can read |
| --- | --- | --- | --- | --- |
| `users` | uid | email, created_at, country, consent flags (diagnostics, events), beta cohort, deleted_at | api | own doc |
| `entitlements` | uid | pro (bool), source (`ios_sub`, `android_sub`, `lifetime_ios`, `lifetime_android`, `beta_grant`), expires_at, in_grace, updated_at | billing worker | own doc |
| `purchases` | store + transaction id | uid, product, store, original_transaction_id / purchase_token, state, dates, environment (sandbox/production) | api, billing worker | no |
| `billing_events` | auto | raw notification type and subtype, signed-payload hash, processed_at (append-only ledger) | billing worker | no |
| `devices` | uid/device_id | platform, app version, data source (`apple_health`, `health_connect`, `band`), last_seen, sync cursor | app (own) | own |
| `sync_manifests` | uid | key version, wrapped-key metadata (not keys), segment counts per device and table, last upload | app (own, rules-checked) | own |
| `feedback` | auto | uid, text, app version, attachment path, created_at | api | no |
| `deletions` | uid | requested_at, completed_at, steps done | api, deletion job | no |

Security rules: the app can read its own `users`, `entitlements`, `devices`, `sync_manifests`; it writes only `devices` and `sync_manifests` under its own uid, with field checks. Everything else goes through `api`.

### Cloud Storage (encrypted)

`gs://tempo-prod-sync/u/{uid}/d/{device_id}/{table}/{seq}.seg`: one encrypted segment per upload per table. Rules: only the signed-in owner of `{uid}` can read or write, App Check required, size limit per object. Versioning on; a lifecycle rule removes non-current versions after 30 days.

`gs://tempo-prod-feedback/{feedback_id}/…`: attachments the user chose to send. Readable by the team only, deleted after 90 days.

### BigQuery

- `events.app_events`: pseudonymous id (a random id per install, not the uid), event name, small allow-listed properties, app version, platform, timestamp. No health values ever: an allow-list in `api` drops anything else. 13-month expiry.
- `billing.ledger`: mirror of `purchases` and `billing_events` for revenue and churn reports.

## Encrypted sync

### What syncs

Raw and user-entered data syncs; derived data is recomputed on the phone. Starting from the tables the local backup already restores:

| Kind | Tables | How |
| --- | --- | --- |
| Raw, append-only | `health_records`, `health_deletions`, `minute_samples`, `stress_samples`, `spo2_samples`, `od_events`, `hr_live`, `band_workouts`, `nudge_log` | Append-only segments; merge with insert-or-ignore on each table's key |
| User-entered | `journal`, `morning_feel`, `workouts` (manual and confirmed), `strength_sets`, `plan_days`, `longevity` inputs, settings that describe the user (profile, goal, availability, journal setup, sources chosen) | Segments of changed rows; last writer wins per row, by an `updated_at` stamp added in S1 |
| Derived | `daily_scores`, `baselines`, `sleep_sessions`, `health_minutes` | Not synced. Rebuilt after restore (`rebuildHealthMinutes`, `ScoreService.recomputeFrom`) |
| Device-local | `sync_state` cursors, `sync_log`, band auth key, notification state, theme | Never synced |

S1 audits every table and setting key against this list. A test fails if a new table or settings key isn't classified.

### Crypto

- A random 256-bit **data key** per account, created on the first phone.
- Each segment: rows serialised (CBOR), compressed (zstd or gzip), then encrypted with **XChaCha20-Poly1305** under the data key. Associated data binds uid, device, table, seq and key version, so a segment can't be moved or replayed elsewhere.
- The data key is stored **wrapped**, never in plain form, in two places:
  1. **The platform's synced keychain:** an iCloud Keychain synchronizable item on iOS; Android Block Store with end-to-end encrypted cloud backup. A new phone on the same platform unlocks with no typing.
  2. **A recovery key** shown once at setup: 24 words or a 32-character code. The user saves it to a password manager or prints it. Needed when moving between iPhone and Android, or if the keychain is lost.
- Lose both and the cloud copy can't be decrypted, by us or anyone. The phone's own data is unaffected. The app says this plainly at setup.
- Library: `cryptography` / `cryptography_flutter` (native-accelerated, pure-Dart fallback). All format and crypto code lives in `packages/sync`, pure Dart, with known-answer tests.
- Key rotation: a new key version re-wraps the data key; segment re-encryption can wait for the next full compaction.

### Flows

- **Upload:** after each Health read or band sync, and after user edits (debounced), the app makes segments of rows past each table's upload cursor, encrypts them, uploads them, then advances the cursor. It works offline and catches up later. Compaction merges small segments weekly.
- **Restore on a new phone:** sign in → "Restore your history?" → unlock the key (keychain automatically, or the recovery key) → download and decrypt segments → insert or ignore → rebuild minutes and recompute scores → connect Health (its 90-day re-read dedupes by record key).
- **Beta scope:** one active phone per account, with continuous backup and restore. Live two-way sync between two phones in use at the same time (for example an iPhone and an iPad, or a band phone and a Health phone) comes after the beta. The segment format already allows it: segments are per device, and merges are idempotent.
- The local backup folder stays as an offline fallback.

## Accounts

- **Methods:** Sign in with Apple, Google, and email link (passwordless, built into Identity Platform). An email one-time code would need a custom flow; the link is the native choice (G-O3).
- **Account linking:** the same email from Apple and Google is merged into one account. Apple's private-relay emails are kept as given.
- **Sign up:** Identity Platform creates the user; a blocking function creates `users/{uid}` and a `beta_grant` entitlement for invited testers.
- **On the phone:** one database file per uid (`tempo-{uid}.sqlite`). Signing out keeps the file and locks it; signing in as someone else opens another file. The Firebase SDK keeps the session tokens in the Keychain / Keystore.
- **Offline:** the last entitlement is cached with its expiry; Pro stays on for up to 7 days without a check (grace), then falls back to Free. Data is never locked.
- **Delete account** (You → Account): `api` marks `deletions/{uid}`; a Cloud Run job deletes the Storage prefix, the Firestore docs, the BigQuery link to the install id, and the Identity Platform user. Billing records are kept with the uid removed, as tax law requires. Done within 30 days, usually minutes. The app explains that subscriptions are cancelled in the store, and links there.

## Billing on GCP

### Products

| Product | iOS | Android |
| --- | --- | --- |
| Pro monthly | auto-renewable subscription, group "Pro" | subscription `pro`, base plan `monthly` |
| Pro yearly (7-day trial) | same group | base plan `yearly` with a free-trial offer |
| Pro lifetime | non-consumable | one-time product |

Starting prices: $5.99, $39.99, $99.99, with regional pricing (India first).

### Purchase flow

- **App:** the `in_app_purchase` plugin (StoreKit 2 on iOS, Play Billing on Android). Every purchase carries the account: `appAccountToken` = a UUID derived from the uid (iOS), `obfuscatedAccountId` = a hash of the uid (Android).
- **iOS:** the app sends the signed transaction (JWS) to `POST /billing/apple/verify`; `api` verifies it with Apple's App Store Server Library, writes `purchases`, recomputes `entitlements`.
- **Android:** the app sends the purchase token to `POST /billing/google/verify`; `api` checks it with the Play Developer API (`subscriptionsv2.get` / `products.get`) and **acknowledges it**. Purchases not acknowledged within 3 days are refunded automatically.
- **Notifications:** App Store Server Notifications V2 go to `POST /webhooks/apple` (signature verified). Play real-time developer notifications arrive on a Pub/Sub topic consumed by the billing worker. Both are idempotent: keyed by notification id, stored in `billing_events` before processing.
- **Entitlement:** Pro if there is an active subscription (including grace period and billing retry), an unrevoked lifetime purchase, or a beta grant. Recomputed on every event and by a daily job.
- **Cross-platform:** Pro bought on one store unlocks the other through the account (App Store guideline 3.1.3(b) allows it when Pro is also sold in-app on both).
- **Edge cases with tests:** refund and revocation, upgrade and downgrade between monthly and yearly, lifetime bought while subscribed (prompt to cancel the subscription), a purchase made under a different account (restore offers to move it), Family Sharing off, sandbox vs production, a purchase whose verification failed while offline (retried from a queue on the phone).
- **Restore purchases:** re-sends current transactions (iOS) or queries purchases (Android) to `verify`.

## Diagnostics and feedback

- **Crashlytics:** collection disabled until the user opts in at onboarding or in You → Privacy.
- **Usage events:** our own `POST /events`, batched, opt-in, allow-listed names and properties (see the beta plan's metrics). No Google Analytics and no advertising id, keeping ad SDKs out of a health app.
- **Feedback:** `POST /feedback` with text, an optional screenshot and an optional Health data check report. The user sees the report before sending. It's the one place readable health data reaches the server, so access is limited to the team and it's deleted after 90 days.

## API surface (`api`, Cloud Run)

Every route requires a Firebase ID token and an App Check token, except the store webhooks, which verify their own signatures.

| Route | Purpose |
| --- | --- |
| `POST /billing/apple/verify` | Verify a StoreKit 2 transaction; update the entitlement |
| `POST /billing/google/verify` | Verify and acknowledge a Play purchase; update the entitlement |
| `POST /billing/restore` | Re-verify a batch of transactions or tokens |
| `POST /webhooks/apple` | App Store Server Notifications V2 |
| (Pub/Sub push) `/workers/play-rtdn` | Play real-time developer notifications |
| `POST /events` | Opt-in usage events → Pub/Sub → BigQuery |
| `POST /feedback` | Feedback with optional attachments |
| `POST /account/delete` | Start account deletion |
| `GET /config` | Remote flags (minimum app version, kill switches) |

Sync doesn't go through `api`: the app reads and writes its own Storage prefix and manifest directly, under security rules.

## Security and privacy

- App Check enforced on `api`, Firestore and Storage.
- IAM: one service account per service, least privilege; no human access to prod data except break-glass roles with audit logs.
- Secrets only in Secret Manager. The band auth key and the sync data key never leave the device unwrapped.
- Firestore point-in-time recovery on; scheduled weekly exports to a locked bucket.
- Logs never contain tokens, email bodies or payloads; structured logging with field redaction.
- Store rules: HealthKit data isn't stored in iCloud by us (the keychain item holds a wrapped key, not health data) and is never used for advertising. Health Connect permission declaration and Data safety form say "encrypted in transit, end-to-end encrypted at rest, deletable".
- Privacy policy and DPDP/GDPR: the data inventory in this plan is the policy's source. Legal review before the external beta.

## Repository layout

```
/backend              Cloud Run api + workers (TypeScript), tests with emulators
/infra                Terraform: projects, IAM, Firestore rules, buckets, Pub/Sub, Cloud Run
/packages/sync        Segment format, crypto, merge (pure Dart, no Flutter)
/app/lib/src/account  Sign-in, session, per-account database
/app/lib/src/billing  Products, paywall, verify, entitlement cache
```

`packages/sync` follows the scoring package's rule: pure Dart, every function unit-tested, known-answer tests for the crypto.

## Cost for the beta

Up to about 500 testers, on the published free tiers and list prices (check at setup):

| Item | Monthly |
| --- | --- |
| Identity Platform (email, Apple, Google) | $0 (free to 50k monthly users) |
| Cloud Run, Pub/Sub, Scheduler | $0–10 (scales to zero) |
| Firestore | $0–5 |
| Cloud Storage: about 30 MB a year per user, compressed and encrypted | under $1 |
| BigQuery | $0 (free tier) |
| Crashlytics, App Check | $0 |
| **Total** | **under about $20**, plus the domain and the two developer accounts ($99 a year Apple, $25 once Google) |

## Phases

These replace B3 and B4 in the beta plan and add S1. Weeks assume one engineer full-time.

| Phase | Weeks | Scope | Gate |
| --- | --- | --- | --- |
| G0 · GCP foundation | 1 | Terraform for `tempo-dev` and `tempo-prod`; Identity Platform, Firestore, buckets, Pub/Sub, Cloud Run skeleton with health check; App Check; CI deploys with Workload Identity Federation; `docs/network.md` | `terraform apply` from clean on both projects; `api` deployed; app flavours talk to their project |
| G1 · Accounts | 2 | Sign-in methods, account linking, per-account database, sign out and switch, delete account, offline grace | Sign up, sign out, sign in on a second phone, delete account: all work, offline included |
| G2 · Billing | 3–4 | Store products; paywall; both verify routes; Apple webhooks; Play RTDN worker; entitlement engine with tests for every edge case listed; restore; cross-platform Pro; daily re-check | Sandbox purchase, renew, upgrade, refund, lapse and restore on both stores; iOS lifetime unlocks Android; webhook replay is idempotent |
| S1 · Encrypted sync | 3 | `packages/sync` (format, crypto, merge) with known-answer tests; table and settings classification with its test; upload cursors; keychain and Block Store key storage; recovery key; restore flow; compaction | Restore a phone with 90 days of Health data and a journal onto a fresh install: same scores to the decimal; server copy shown unreadable; lost-key path tested |
| G3 · Diagnostics and feedback | 1 | Crashlytics opt-in, `/events` to BigQuery with the allow-list, feedback with attachments, beta dashboards | Exit metrics answerable from BigQuery; a forced crash appears in Crashlytics only after opt-in |
| G4 · Hardening | 1 | Security rules tests, load test of webhooks, alerting, runbooks (billing incident, key loss, deletion), privacy policy data inventory | Rules tests pass; alerts fire in a drill; runbooks reviewed |

Beta order with these: B0 (+G0) → B1 → B2 alongside G1 → G2 alongside S1 → G3 → G4 → B5 → B6. About 14–18 weeks to the external beta for one full-time engineer. Wave 1 (people you know) can start after G1 + B1 + B2, with Pro granted, before billing and sync are done.

## Open decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| G-O1 | GCP region (Firestore's can't change later) | **asia-south1 (Mumbai)** if most testers are in India, with Cloud Run and buckets in the same region. If the beta is mostly EU or US, `eur3` or `nam5` multi-region. |
| G-O2 | Server language | **TypeScript on Node**, for Apple's and Google's official billing libraries and the Firebase Admin SDK. Dart on the server would share code but lacks those libraries. |
| G-O3 | Email sign-in | **Email link** (native to Identity Platform). A 6-digit code needs a custom flow plus an email provider; add it only if testers struggle with links. |
| G-O4 | Recovery key format | **24 words** (easier to write down) over a 32-character code. |
| G-O5 | Live multi-phone sync | After the beta; the format allows it. |
| G-O6 | Feedback report retention | 90 days, team-only access. |

## Checklist

- [ ] G-O1 … G-O6 closed in docs/decisions.md
- [ ] G0: Terraform, both projects, api skeleton, App Check, CI, `docs/network.md`
- [ ] G1: accounts end to end
- [ ] G2: billing end to end, every edge case tested
- [ ] S1: encrypted sync and restore, known-answer crypto tests, classification test
- [ ] G3: diagnostics opt-in, events to BigQuery, feedback
- [ ] G4: rules tests, alerts, runbooks, privacy inventory
