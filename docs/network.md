# Network calls

Every place the app talks to a server is listed here (CLAUDE.md → Non-negotiables). A new call needs a line in `docs/decisions.md` first, then a row here. Health data leaves the phone only end-to-end encrypted; the one exception is a feedback report the user reads and chooses to send.

## Today

Only in builds given the backend settings (`app/lib/src/account/backend_config.dart`, `tools/build_store.sh` with `.env.store`); without them the app makes no network calls. Apple Health, Health Connect and the Mi Band are on the phone either way.

| Call | Code | Carries | When |
| --- | --- | --- | --- |
| Firebase Auth (anonymous; Apple, Google, email link) | `app/lib/src/account/account_service.dart` | Account identity, email if the user signs in with one | First purchase, or when the user signs in |
| App Check token | same | Device attestation | With each api call |
| `POST /account/init`, `GET /billing/entitlement` | `app/lib/src/account/api_client.dart` | uid only | After sign-in; on open at most once a day (`app.dart` → `_refreshPro`) |
| `POST /billing/apple/verify`, `/billing/google/verify` | `app/lib/src/billing/billing_service.dart` | Signed StoreKit 2 transaction or Play purchase token | After a purchase or restore |
| `POST /account/consent`, `/account/delete` | `api_client.dart`, `screens/account.dart` | uid, two booleans | User's choice |
| Store links (manage subscription, terms, privacy) | `screens/account.dart`, `screens/paywall.dart` | Opens the browser or store | User taps |

## Planned (launch plan and Backend plan)

Region for all of them: `asia-south1` (Mumbai), decision G-O1.

| Call | From | To | Carries | Phase | Opt-in |
| --- | --- | --- | --- | --- | --- |
| Sign in (anonymous, Apple, Google, email link) | `app/lib/src/account` | Firebase Authentication | Account identity, email if given | G1 | Anonymous uid is automatic; an account is the user's choice (L-O1) |
| App Check token | Firebase SDK | App Attest / Play Integrity, Firebase | Device attestation | G0 | No (abuse protection) |
| Entitlement read | Firestore SDK | Firestore `entitlements/{uid}` | Nothing sent; reads own Pro state | G2 | No |
| Purchase verify, restore | `app/lib/src/billing` | `api` `/billing/*` | Signed store transaction or purchase token, uid | G2 | Only when buying or restoring |
| Encrypted sync upload, restore | `packages/sync` via Storage SDK | Cloud Storage `u/{uid}/…`, Firestore `sync_manifests/{uid}` | XChaCha20-Poly1305 ciphertext, segment counts | S1 | Only with an account and backup on |
| Usage events | `app/lib/src/diagnostics` | `api` `/events` → BigQuery | Allow-listed event names and small properties, random install id; never health values | G3 | Opt-in, off by default |
| Crash reports | Crashlytics SDK | Firebase Crashlytics | Stack traces, device model, app version | G3 | Opt-in, off by default |
| Feedback | You → Send feedback | `api` `/feedback` | Text, optional screenshot, optional Health data check report the user previews | G3 | Each send is the user's choice |
| Remote config | app start | `api` `/config` | Nothing but the app version | G3 | No |
| Account delete | You → Account | `api` `/account/delete` | uid | G1 | User's choice |
