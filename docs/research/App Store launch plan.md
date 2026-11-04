# App Store launch plan: store readiness, freemium and running costs

As of Nov 3, 2026 · Status: L-O1…L-O7 accepted by the owner on Nov 4 (see `docs/decisions.md`); the name stays Tempo. Builds on `docs/research/Beta release plan.md` (B0–B6) and `docs/research/Backend plan.md` (G0–G4, S1); where this differs, the owner's choice goes into `docs/decisions.md`. Store rules and cloud prices change: every number and rule below is a starting point to re-check at setup (marked TODO(verify) where it matters most).

## Summary

- **Where we are.** The product is mostly built. B1 (health-first onboarding, no band in onboarding) is done. Nothing for accounts, billing, sync or store compliance exists in the app yet: no `in_app_purchase` or Firebase dependency, no privacy manifest, the app id is still `dev.tempo.tempo`, version `0.0.1+1`.
- **What blocks a store listing** is mostly compliance and setup, not features: a legal entity and developer accounts, the app id and name, a privacy manifest, Health declarations, a few Android permissions Play is likely to reject, and a paywall that meets Apple's subscription rules.
- **Freemium:** free tier keeps the daily truth (scores, sleep, live workouts, widgets, backup); Pro sells the coach (adaptive plan, goals, insights, long history, Tempo Age). Prices stay $5.99 / $39.99 / $99.99 with India regional pricing.
- **Infra cost is small:** about **$0–20 a month** for the beta, **~$150–250 a month at 50k monthly users**, and **~$0.003–0.006 per monthly user** after that. The store's 15 % cut is about 100× the infra cost per paying user. The one line item that grows fast is Identity Platform past 50k monthly users (see "Cost levers").

## 1. Store readiness checklist

### Business and accounts (B0)

| Item | Notes | Cost |
| --- | --- | --- |
| Legal entity | Needed for an organisation developer account (B-O6). In India an LLP or Pvt Ltd; a D-U-N-S number (free) for both stores | ₹10–25k setup, then yearly compliance |
| Apple Developer Program (organisation) | Also unlocks Xcode Cloud (25 compute hours a month included) | $99 a year |
| Google Play Console (organisation) | Organisation accounts skip the 12-testers-for-14-days rule | $25 once |
| Store name | The name stays Tempo (L-O7). App Store names must be unique, so list with a subtitle-style name such as "Tempo: Recovery & Sleep", checked for availability in App Store Connect when the app record is created; the same on Play. No trademark filing for now | India ₹4.5–9k per class; US ~$350 per class |
| Domain, website, support email | Marketing page, privacy policy and terms on Firebase Hosting (GCP, free tier); a support inbox | ~$12 a year domain; email $0–7 a month |
| Privacy policy and terms | Lawyer review, as the beta plan says; source is the backend plan's data inventory | One-time, roughly ₹30–80k / $500–2,000 |
| Store Small Business Program | Apple: 15 % instead of 30 % under $1M a year (enrol, it isn't automatic). Google: 15 % on the first $1M a year, and 15 % on all subscriptions | $0 |

### App identity (both platforms)

- [ ] Final app id on a domain we own (replaces `dev.tempo.tempo` in iOS Runner, the widget extension `…TempoWidget`, RunnerTests and Android `applicationId`). Also change `tempoAppId` in `packages/health_source`, the echo guard that skips Tempo's own records in Health.
- [ ] Version `1.0.0` and a build-number scheme driven by CI.
- [ ] Release signing: iOS distribution certificate and profiles (app + widget); Android upload key in CI secrets, Play App Signing on.
- [ ] Build flavours `dev` and `prod` (the backend plan needs them for the two Firebase projects).

### iOS (App Store)

| Item | State today | Action |
| --- | --- | --- |
| Privacy manifest `PrivacyInfo.xcprivacy` | Missing | Add one for Runner and the widget: required-reason APIs (UserDefaults via `shared_preferences`, file timestamps, disk space, boot time as used); check each plugin ships its own. Apple rejects uploads without it |
| Export compliance | `ITSAppUsesNonExemptEncryption` not set | Encrypted sync (XChaCha20-Poly1305) is more than HTTPS. It very likely qualifies for the mass-market exemption, but answer Apple's questionnaire once, then set the key so each build isn't held. France may need a declaration. TODO(verify) |
| iPad | `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone and iPad) | Set iPhone-only for 1.0. Otherwise review tests it on iPad and the listing needs 13" iPad screenshots |
| HealthKit | Share and update strings exist; copy says "Everything stays on this phone" | Rewrite once sync ships: "encrypted on this phone before it's backed up". Never store Health data in iCloud (the wrapped key in the keychain is fine) |
| Bluetooth | `NSBluetoothAlwaysUsageDescription` + background mode for a band that's hidden in Developer | Review flags background modes it can't exercise (guideline 2.5.4). Strip BLE, its usage string and `bluetooth-central` from the App Store flavour, or explain the Developer path in review notes. Recommend stripping for 1.0 |
| Live Activities | `NSSupportsLiveActivitiesFrequentUpdates` on | Fine for live workouts; mention in review notes |
| Sign-in | None yet | See "Accounts and review" below |
| Paywall (guideline 3.1.2) | None yet | Price per period, trial length and what happens after it, Restore, links to terms and privacy, all on the paywall itself |
| Health claims (1.4.1) | Copy avoids diagnose/detect | Keep it. Tempo Age is "an estimate", body signals are "signals to notice", not alerts about illness |
| Account deletion (5.1.1(v)) | n/a until accounts | In-app delete once accounts exist |
| Listing | — | 6.9" screenshots (Apple scales down), a 30 s preview video optional, App Privacy labels, age rating questionnaire, review notes with a demo path that works with no wearable (seed the Simulator with Health data) |

### Android (Google Play)

| Item | State today | Action |
| --- | --- | --- |
| Target SDK | `flutter.targetSdkVersion` | Must meet Play's current requirement for new apps (API 35 since Aug 2025; likely 36 from Aug 2026). TODO(verify) at upload. Native libraries must support 16 KB pages |
| Health Connect | 17 read types + `READ_HEALTH_DATA_HISTORY` and `…_IN_BACKGROUND`, plus `WRITE_EXERCISE`, `WRITE_SLEEP` | Health apps declaration with a reason per permission; drop any type the app doesn't use (each unused one is a rejection risk); the privacy-policy rationale activity Health Connect requires. Submit early: review takes days to weeks |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Declared | Play allows this only when the core feature breaks without it. Remove the permission; open the battery settings screen instead (no permission needed) |
| `SCHEDULE_EXACT_ALARM` | Declared | Restricted to alarm and calendar apps. Use inexact alarms or WorkManager for the morning call |
| Foreground service types `connectedDevice` and `location` | Declared | Play Console FGS declaration with a short video per type. If the band is stripped from the store flavour, `connectedDevice` and the BLE permissions go too |
| Location | Fine and coarse, foreground only | A prominent in-app disclosure before the GPS prompt for walks and runs |
| Play Billing | Not added | `in_app_purchase` with the Play Billing Library version Play requires at upload. TODO(verify) |
| Listing | — | Data safety form, content rating, feature graphic, phone screenshots, closed testing track |

### Quality bar before submitting

- Crash-free sessions ≥ 99.5 % over the last beta week (beta plan exit criteria).
- A fresh install with **no** wearable still makes sense (review devices have none): Today explains what's missing and how to connect a source.
- Dark mode, Dynamic Type / font scale up to 200 %, VoiceOver and TalkBack labels on the score rings and charts.
- Offline: the app opens and scores without network.

## 2. Accounts and review

App Review rejects a sign-in wall when the app has no real account features (5.1.1(v)), and pushes back when a purchase needs registration first. B1 already shipped onboarding without accounts. Recommendation, replacing B-O3's "sign-in required":

- **Free works with no account.** Everything on the phone, as today.
- **Buying Pro needs no account.** The app signs in anonymously (Firebase anonymous auth gives a uid with no sign-in screen) so the purchase is still tied to a uid on our billing service.
- **An account is offered for what it adds:** encrypted backup and restore, Pro on the other platform, beta feedback replies. Signing in links the anonymous uid, so nothing is lost.

This removes the biggest review risk in the beta plan and keeps onboarding as it is. It needs a decision line (it changes B-O3 and B-D2).

## 3. Freemium

### The rule

Free gives the **truth about your day**; Pro gives the **coach that tells you what to do about it, and the long view**. A free user should still open Tempo every morning, because that's who converts.

### Updated split

The Oct 21 split predates U1–U6, W1–W8, N2, D1, the sleep plan and widgets. Proposed:

| Free | Pro |
| --- | --- |
| Recovery, Strain, Sleep with detail screens; the morning reveal | Tempo Coach: adaptive plan, Move or skip with reasons, rescue, week template, injury mode |
| Today's story, number tiles, day timeline, today's insight | Goals and progression (incl. Get stronger), Goal screen, tune-ups, next goal |
| Live walks, runs and strength logging (GPS, pace, Live Activity, notification) | Today's picks (run, strength, game), running paces from a race time |
| Home and lock-screen widgets (basic) | All widget styles; coach widgets |
| Journal logging and daily check-in | Journal impact estimates and experiments |
| 30 days of Trends | Full history, long trends, cardio load |
| Sleep type | The 21-day sleep plan |
| Weekly report (Week in review, short) | Week story in full, earlier days, coach moments beyond the morning call |
| Body-signals card | Tempo Age with blood work |
| Activities added by hand | Strength progression and muscle freshness |
| Health source, export of all data, **encrypted backup** | — |

Backup stays free: it costs about $0.0005 a user a month (below), it's what makes an account worth having, and locking someone's history behind a subscription breaks the privacy story.

### Prices and trial

| Product | US | India (regional) | Notes |
| --- | --- | --- | --- |
| Pro monthly | $5.99 | ₹249 | No trial |
| Pro yearly | $39.99 | ₹1,499 | 7-day free trial; the default on the paywall, shown as "$3.33 a month" |
| Pro lifetime | $99.99 | ₹3,999 | Non-consumable; infra cost per lifetime user is ~$0.06 a year, so it's safe |

Let the stores generate the other countries from the US tier, then adjust India, Brazil, Indonesia and Turkey by hand.

### Where the paywall shows

1. End of onboarding, skippable (exists in the plan as step 8).
2. At the moment of intent: tapping a locked coach card, a goal, Trends past 30 days, Tempo Age. Show what they'd get with their own data ("Your plan for tomorrow is ready") rather than a feature list.
3. After the first full week: a Week-in-review moment that previews the Pro week story.
4. Never on Today's scores, never as a full-screen interruption on open.

### Beta and launch mechanics

- Beta: every tester gets a `beta_grant`; the paywall runs in store sandbox mode (as planned). At launch, convert beta testers to a one-time offer (e.g. first year at 50 % via an Apple offer code / Play promo code) as a thank-you.
- Track paywall views, trial starts, trial-to-paid, by entry point (allow-listed events, no health values).
- Healthy targets to tune toward: 3–6 % of monthly users paying, trial-to-paid ≥ 40 %.

## 4. Infra cost

### Assumptions per active user (from the Backend plan design)

- Firestore: ~10 reads and ~5 writes a day (entitlement, user, manifest on open; device and manifest on upload).
- Cloud Storage: ~30 MB a year of encrypted segments; **one segment per upload bundling all tables**, ~6 uploads a day. (One object per table per upload would make storage operations the biggest line; bundle them.)
- Events: ~20 allow-listed events a day, sent as one batch.
- Cloud Run scales to zero; webhooks tolerate a cold start, so no minimum instance.

GCP list prices, single region (asia-south1 is within a few % of us-central1). TODO(verify) at setup with the pricing calculator.

### Monthly cost by size

| Monthly active users | 500 (beta) | 5,000 | 50,000 | 200,000 |
| --- | --- | --- | --- | --- |
| Identity Platform | $0 | $0 | $0 | ~$735 (see levers) |
| Firestore | $0 | ~$1 | ~$25 | ~$100 |
| Cloud Storage (data + ops, year one) | <$1 | ~$8 | ~$80 | ~$320 |
| Cloud Run + Pub/Sub + Scheduler | $0 | ~$2 | ~$20 | ~$80 |
| BigQuery (events, billing ledger) | $0 | $0 | ~$5 | ~$25 |
| Logging, Monitoring, Secret Manager | $0 | ~$1 | ~$10 | ~$40 |
| Crashlytics, App Check, Hosting | $0 | $0 | $0 | $0 (ask for a Play Integrity quota raise past 10k calls a day; free) |
| **Total infra** | **~$0–5** | **~$10–20** | **~$150–200** | **~$600 without Identity Platform's fee, ~$1,300 with** |
| Per monthly user | — | ~$0.003 | ~$0.004 | $0.003–0.0065 |

Storage grows with history (30 MB per user per year), so year two costs roughly double the storage line; weekly compaction and gzip/zstd keep it near that.

### Fixed and one-time costs

| Item | Cost |
| --- | --- |
| Apple Developer | $99 a year |
| Google Play | $25 once |
| Domain + email | ~$12 a year + $0–7 a month |
| Legal entity (India) | ₹10–25k setup + yearly filings |
| Privacy policy / terms review | ~$500–2,000 once |
| Trademark | ~₹9–18k (two classes, India); +$700 US |
| CI builds | Xcode Cloud's 25 h a month (included) for iOS; GitHub Actions Linux for Android and tests (free tier on a private repo is 2,000 min). macOS minutes on GitHub cost ~$0.08 a minute if used instead |
| Test devices | One mid-range Android phone + a Wear OS / Galaxy watch if not owned (~$300–500) |

### What revenue looks like next to it

At 50k monthly users, 4 % paying, a blended ~$2.50 a month net of the 15 % store fee (India-heavy mix lowers this): ~2,000 payers ≈ **$5,000 a month** against ~$200 of infra. The real costs are the store fee, taxes and your time, not GCP.

### Cost levers

1. **Identity Platform's per-user fee.** The plan upgrades Firebase Auth to Identity Platform for blocking functions, which charges per monthly user past 50k (~$0.0055 then ~$0.0046). Plain Firebase Authentication without the upgrade has no per-user charge for email, Apple and Google sign-in. Create `users/{uid}` and the beta grant from `api` on first call instead of a blocking function, and stay on plain Firebase Auth. Saves ~$735 a month at 200k. TODO(verify) the current terms when creating the project. Anonymous users (section 2) count as users on Identity Platform, which makes this lever matter more.
2. **Bundle segments** (one object per upload, not per table) and back off uploads to every few hours when nothing changed.
3. **Budgets and alerts:** a GCP budget at $50 with alerts at 50/90/100 % from day one; a hard cap via a budget-triggered function for the dev project.
4. **Log hygiene:** structured logs at info level, no per-request payloads; stay within the free 50 GiB.

## 5. Phases and timeline

On top of the beta plan, with B1 done. One engineer full-time; part-time doubles it.

| Phase | Weeks | Scope | Gate |
| --- | --- | --- | --- |
| L0 · Business setup | 1–3 (calendar; paperwork waits) | Entity, D-U-N-S, both developer accounts, store name with a subtitle, domain, Small Business Program | Both consoles open under the organisation |
| L1 · Store hygiene (alongside B2) | 1–2 | App id, flavours, signing, privacy manifest, export compliance answer, iPhone-only, App Store flavour without BLE, Android permission clean-up, target SDK, disclosures | A `prod` build uploads to TestFlight and Play internal testing with no warnings |
| B2 · Connector proof | 2–3 | As planned | As planned |
| G0 + G1 · GCP and accounts | 3 | As planned, with optional accounts and anonymous uid (section 2), plain Firebase Auth (lever 1), budgets | As planned + budget alerts fire in a drill |
| G2 · Billing + paywall | 3–4 | As planned + the updated split and paywall entry points | As planned |
| S1 · Encrypted sync | 3 | As planned, segments bundled per upload | As planned |
| G3/G4 + B5 · Diagnostics, hardening, listings | 2–3 | As planned + screenshots, review notes, Health Connect and FGS declarations submitted early | TestFlight external approved; Play closed testing live |
| B6 · Beta | 6–8 | As planned | Beta exit criteria |
| L2 · Launch | 1–2 | Production review on both stores, launch offer for testers, phased rollout (Apple 7-day phased release; Play staged 10 % → 100 %) | Live in both stores |

About **5–6 months** to a public 1.0 for one full-time engineer, the same 14–18 weeks to the external beta as the beta plan plus beta and launch. A faster path, if wanted: ship the beta with on-device store purchases only (StoreKit 2 checks on the phone, Play acknowledgement from the app) and add the GCP billing service before launch. That departs from G-D3, so it's the owner's call.

## Decisions

L-O1…L-O6 accepted 2026-11-04, along with B-O3, B-O7, B-O9 and G-O1…G-O6 (region: asia-south1, Mumbai). L-O7: keep Tempo.

| # | Decision | Recommendation |
| --- | --- | --- |
| L-O1 | Accounts optional (free and Pro without sign-in; anonymous uid; account for backup and cross-platform) | Yes. Replaces B-O3 |
| L-O2 | Plain Firebase Auth instead of Identity Platform | Yes, unless a needed feature requires the upgrade |
| L-O3 | Updated Free/Pro split (section 3), backup free | Yes; revisit after wave 1 as planned |
| L-O4 | India prices ₹249 / ₹1,499 / ₹3,999 | Yes, tune from beta |
| L-O5 | App Store and Play builds without BLE (band stays in the dev flavour) | Yes for 1.0 |
| L-O6 | iPhone-only for 1.0 | Yes |
| L-O7 | Name and entity | Decided: keep Tempo, listed with a subtitle-style store name |

## Checklist

- [x] L-O1 … L-O6 closed in `docs/decisions.md` (2026-11-04)
- [x] L-O7: keep Tempo (2026-11-04)
- [ ] L0: entity, D-U-N-S, Apple and Play organisation accounts, name, domain, Small Business Program
- [x] L1 (code): store build flag, signing, privacy manifest, export compliance, iPhone-only, store build without BLE, Android permissions (2026-11-04)
- [ ] L1 (needs L0): final app id on our domain; target SDK checked at first upload
- [ ] Beta plan B2–B6 and Backend plan G0–G4, S1 with the changes above
- [ ] GCP budgets and alerts in both projects
- [ ] L2: production review, tester offer, phased rollout
