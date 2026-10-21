# Beta release plan: Tempo as a product

As of Oct 21, 2026 · Status: direction decided by the owner (see "Decided"), open decisions listed with a recommendation each. Nothing in "Open decisions" is built until it lands in `docs/decisions.md`.

## Summary

Tempo becomes a product, released first as a public beta on TestFlight and Google Play closed testing. Four things change:

1. **Health apps first.** Apple Health (iOS) and Health Connect (Android) are the only data sources offered in onboarding. The Mi Band 6 BLE path stays in the code, works as today, and is reachable only from You → Developer.
2. **Accounts.** Sign up and sign in (Apple, Google, email). Health data still stays on the phone: the account carries identity, the Pro entitlement and beta membership, not health records.
3. **Freemium.** A free tier, plus Pro as a subscription (monthly, yearly) or a one-time lifetime purchase, bought through the App Store and Google Play.
4. **Beta operations.** Store listings, privacy and health-data compliance, opt-in crash reports and usage events, in-app feedback, and exit criteria for a public launch.

The scoring engine, Coach, Trends, Longevity and the Health connectors already exist (H0–H4, E1, C0–C4, C7, P1/P2, T1). Most of the beta work is around them: onboarding, accounts, billing, compliance, and proving the Health connectors on real phones with the watches and apps beta users actually wear.

## Decided (owner, 2026-10-21)

| # | Decision |
| --- | --- |
| B-D1 | Tempo is a product, not a personal tool. Supersedes PLAN.md "Audience: personal tool … sideloaded builds, no multi-user accounts in v1". |
| B-D2 | Users sign up and sign in to an account. |
| B-D3 | Health apps (Apple Health / Health Connect) are the first and default source. Mi Band 6 BLE is secondary and hidden in You → Developer. |
| B-D4 | Freemium: free tier, Pro by subscription or a one-time purchase. |
| B-D5 | Focus is the beta release. |

## What this changes in the project's rules

| Rule today (CLAUDE.md / PLAN.md) | Change |
| --- | --- |
| "Fully on-device. No backend or network calls" | **Health data stays on the phone** (unchanged). Network is allowed only for: account sign-in, entitlements and store billing, and opt-in crash reports and usage events that never carry health values. Each call site is listed in `docs/network.md` (new) and reviewed. |
| "Data comes from the Mi Band 6 over direct BLE, or read-only from Apple Health / Health Connect" | Order flips: Health first, band behind Developer. "Never write back what was read from Health" stays. |
| "The auth key lives only in flutter_secure_storage" | Unchanged. Account tokens live there too, never in the database or logs. |
| Privacy copy "No account, no cloud" (onboarding, You) | Becomes "Your health data never leaves this phone. Your account holds your email and your plan, nothing else." |

## Product shape for the beta

### Free vs Pro

Starting split, to tune from beta data:

| Free | Pro |
| --- | --- |
| Today: Recovery, Strain, Sleep with their detail screens | Tempo Coach: adaptive plan, goals and progression, today's picks, rescue |
| Day timeline, workouts, 30 days of Trends | Full Trends history, cardio load |
| Journal: logging and the daily check-in | Journal impact estimates and experiments |
| Body-signals alert | Tempo Age (Longevity) with blood work |
| Weekly report | Strength log progression and muscle freshness |
| Apple Health / Health Connect, export of all data | Notifications v2 nudges beyond the morning call |

Prices are starting values, set per country in the stores (India gets regional pricing): Pro monthly $5.99, yearly $39.99, lifetime $99.99. Yearly with a 7-day free trial. The benchmark app charges $99.99 a year; undercutting it is the point.

During the beta every tester has Pro free. The paywall still runs, in the stores' test modes, so the purchase, restore and cancel flows are proven before launch.

### Accounts

- **Sign-in methods:** Sign in with Apple (iOS; required by App Store guideline 4.8 once Google is offered), Google, and email with a one-time code. No passwords to store.
- **What the account does,** so it isn't a sign-in wall with nothing behind it (App Store guideline 5.1.1(v) rejects that):
  - Pro bought on one platform works on the other (a lifetime purchase on iPhone unlocks the Android app).
  - Restores Pro on a new phone without hunting for receipts.
  - Beta membership: which build cohort, feedback replies.
  - Later, optional: end-to-end encrypted backup, so a new phone gets history back (see Open decisions, B-O4).
- **What the account never holds:** health records, scores, journal entries, the band's auth key. The server can't see them even with a breach.
- **Delete account** inside the app (required by both stores): deletes the account, cancels nothing by itself (the store owns subscriptions; the screen links to it), and offers to also wipe local data.
- **Sign out:** keeps local data on the phone and locks it to that account. Signing in as another account on the same phone starts a fresh local database; switching back reopens the first. One database file per account id.
- **Offline:** a signed-in user keeps full use with no network. Entitlements are cached on the phone and refreshed when online; a lapsed subscription locks Pro after a grace period, never the free tier or the data.

### Onboarding (health-first)

1. Welcome → value statement.
2. Sign up / sign in.
3. Source: Apple Health on iPhone, Health Connect on Android. The Mi Band choice is removed from onboarding.
4. Permissions with a plain rationale per data type; on Health Connect also history and background.
5. Profile (age, height, weight, max HR) prefilled from Health where available.
6. First read with progress, then a **source check**: what was found (heart rate, sleep with or without stages, HRV, steps, workouts) and from which apps, using the Health data check engine. Warns when a writer gives poor data. Example: Mi Fitness, as seen on 21 Oct, writes sleep as one in-bed block and heart rate stamped by the hour.
7. Goal and preferred workouts (existing editors).
8. Paywall (skippable) → Today.

### Mi Band behind Developer

- You → Developer gets "Mi Band 6 (beta)": pairing, band settings, Band explorer, re-download history.
- You → Data sources lists only the platform's Health source unless Developer is on.
- Band-only rows in You (battery, firmware, band settings) show only when the band is the source.
- The band code, tests and golden packet tests stay and keep passing; nothing is deleted.

## Data quality for real beta users

Health-first means beta users arrive through whatever app writes to Health. Cheap-band users come through vendor apps, which write less than the band holds. The beta must handle each writer honestly.

| Writer | Platform | Known or likely issues | Handling |
| --- | --- | --- | --- |
| Apple Watch | iOS | Sparse HR at rest (4–10 min); SDNN HRV | Interpolation ≤ 15 min (built); HRV feeds Recovery (built) |
| Mi Fitness / Zepp Life | iOS, Android | Sleep as one in-bed block, no stages; HR stamped by the hour (seen 21 Oct on iOS); no HRV | Detect per writer; spread hour-stamped readings across their hour (algo bump); say "no stages from Mi Fitness" on Sleep (built); Recovery stays "Learning" without HRV, so explain what's missing |
| Samsung Health | Android | Writes to Health Connect only for some types; HRV not shared | TODO(verify) on a Galaxy phone |
| Fitbit / Pixel Watch | Android | Writes to Health Connect | TODO(verify) |
| Fitbit, Google apps | iOS | Fitbit's iPhone app doesn't write to Apple Health; Google apps write only some types | Tempo sees only what they write to Apple Health; the source check says so |
| Garmin, Oura, Whoop | Both | Each writes a subset | TODO(verify) with a tester per brand |

Health Connect only exists on Android. On an iPhone, Google or Fitbit data reaches Tempo only through Apple Health.

## Workstreams and milestones

Week counts assume one engineer full-time; part-time doubles them. Each phase has a gate, as in PLAN.md.

| Phase | Weeks | Scope | Gate |
| --- | --- | --- | --- |
| B0 · Decisions and setup | 1 | Close the open decisions below; Apple Developer and Play Console accounts; final app id and name; backend projects; `docs/network.md` | Every open decision in docs/decisions.md; both store consoles reachable |
| B1 · Health-first | 1–2 | Onboarding without the band; band behind Developer; Data sources filtered; privacy copy; source check after the first read | A fresh install on iPhone and Android reaches Today without seeing "band" anywhere |
| B2 · Connector proof | 2–3 (parallel) | Known-answer integration tests (fixed test night and day written to the iOS Simulator and an Android emulator with Health Connect Toolbox, read back through the real plugin); writer quirks (Mi Fitness hour-stamped HR); H2/H3 device gates | Integration tests pass on both; H2 and H3 gates passed; one week each on Apple Watch, Mi Fitness (iOS) and one Android watch with clean Health data checks |
| B3 · Accounts | 2 | Sign-in methods; token storage; per-account database; sign out and switch; delete account; offline behaviour | Sign up, sign out, sign in on a second phone, delete: all work, offline included |
| B4 · Freemium | 2 | Products in both stores; paywall; entitlement cache; Pro gates; restore; cross-platform Pro through the account; beta "Pro for testers" | Sandbox purchase, restore, upgrade, cancel and lapse on both platforms; a lifetime purchase on iOS unlocks Android |
| B5 · Beta operations | 1–2 | Opt-in crash reports and usage events (no health values); in-app "Send feedback" with an attached Health data check report; privacy policy and terms; store listings, privacy labels, Health Connect declaration; beta review | TestFlight external testing approved; Play closed testing live |
| B6 · Beta | 6–8 | Waves of testers; weekly builds; triage; tune Free/Pro and prices from usage | Exit criteria below |

Order: B0 → B1, then B2 alongside B3/B4, then B5 → B6. B2 is the most important: a beta that gets someone's sleep wrong on day one loses them.

## Beta operations

### Store setup

- **App id and name:** `dev.tempo.tempo` needs a reverse domain you own. Changing it also changes `tempoAppId` in `packages/health_source` (the echo guard that skips Tempo's own records in Health). "Tempo" is probably taken in both stores; check name and trademark before listing.
- **Apple:** Developer Program; HealthKit capability and usage strings; TestFlight internal (up to 100 testers, no review) then external (up to 10,000, after Beta App Review); privacy policy URL; App Privacy labels (health data "not collected" by the developer, since it never leaves the phone; account email collected).
- **Google:** Play Console; Health Connect permission declaration and the health apps declaration with a privacy policy; Data safety form; closed testing track. A personal developer account needs a closed test with at least 12 testers for 14 days before production access; an organisation account doesn't. Check current Play rules at setup.
- **Health rules:** no health data for advertising or sold to anyone; HealthKit data never in iCloud.

### Privacy and legal (get a lawyer for these)

- Privacy policy and terms naming exactly what the account holds and what the opt-in diagnostics send.
- India DPDP Act and GDPR for EU testers: consent, deletion, data location of the account backend.
- Wellness, not medical: store copy avoids "detect", "diagnose" and "illness"; the body-signals card stays phrased as signals to notice.
- Mi Band support stays out of store listings during the beta; it's a Developer feature.

### Feedback and support

- "Send feedback" in You: free text, optional screenshot, optional Health data check report (the user sees it before sending).
- A beta channel (email or a community) and a short survey at day 7 and day 30.
- Release notes per build in TestFlight and Play.

### What to measure (opt-in, no health values)

- Activation: finished onboarding, first scores shown, permissions granted per type.
- Data quality: source app names, whether sleep had stages, HR coverage bands (e.g. "under 50 % of minutes") — counts, never values.
- Retention: days with Tempo opened at D1, D7, D30; morning scores ready before first open.
- Monetization: paywall views, trial starts, purchases by product (store test mode in beta).
- Stability: crash-free sessions, sync failures by reason.

### Exit criteria for a public launch

| Metric | Target |
| --- | --- |
| Crash-free sessions | ≥ 99.5 % |
| Onboarding completion (install → first scores) | ≥ 70 % |
| Mornings with scores ready before first open | ≥ 90 % of tester-days on Health Connect; best effort on iOS |
| D30 retention | ≥ 25 % of testers who reached first scores |
| Health data check clean (no Missing, no Odd) | Every tested writer and platform |
| Open P0/P1 bugs | 0 |
| Purchase, restore, cross-platform Pro | Proven on both stores in test mode |

Targets are starting values to revisit after the first wave.

## Open decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| B-O1 | Backend for accounts | **Firebase Authentication** (Apple, Google, email code; mature Flutter support) with no database at first. Alternative: Supabase (open source, region choice). |
| B-O2 | Billing | **RevenueCat** on top of StoreKit and Play Billing: cross-platform entitlements keyed by the account id, receipt checks and webhooks, no billing server of our own. Alternative: the `in_app_purchase` plugin plus our own receipt checks. |
| B-O3 | Is sign-in required? | Required, as decided, with the account features above in place before Beta App Review. Prepare review notes explaining them. If review pushes back: let people browse with "Continue without an account" and require sign-in only for Pro. |
| B-O4 | Cloud backup | Not in the beta. Later, end-to-end encrypted (key derived on the phone, server holds ciphertext only). The local backup folder stays. |
| B-O5 | Crash reports and usage events | Opt-in at onboarding, off by default. **Sentry** (crash) and **PostHog** (events), EU-hosted; never health values. Alternative: Firebase Crashlytics and Analytics, if Firebase is chosen in B-O1. |
| B-O6 | App id, name, company | Register a domain and an organisation developer account (avoids Play's 12-tester rule, looks better in listings); pick a name with trademark search. |
| B-O7 | Band users already on the band | Only the owner today. Keep the band path working behind Developer; no migration needed. |
| B-O8 | Free/Pro split and prices | Start with the table above; revisit after wave 1. |
| B-O9 | Beta size and waves | Wave 1: 20–30 people you know (iPhone + Apple Watch, iPhone + Mi Fitness, Android + Galaxy/Pixel/Mi). Wave 2: 100–200 from fitness and Android communities. Wave 3: open TestFlight link and Play closed testing at scale. |

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Beta App Review rejects forced sign-in | Beta delayed | Account features in place first; fallback B-O3 |
| Writers give poor data (Mi Fitness) | Users see wrong sleep or 0 strain on day one | Source check in onboarding; B2 writer handling; honest "what's missing" copy |
| iOS background limits | Scores not ready on waking | Read on open with progress; Health background delivery for new samples (TODO(verify)); show data age |
| Accounts erode the privacy story | Trust | Health data never on the server; `docs/network.md`; plain copy; diagnostics opt-in |
| Store health-data review (Health Connect declaration) | Android beta delayed | Submit the declaration in B5, early |
| One engineer, many workstreams | Slips | Keep B6 scope frozen; Free/Pro split moves only after wave 1 data |
| Name or trademark clash | Rename after launch | Search in B0 |

## Checklist

- [ ] B0: open decisions B-O1 … B-O9 closed in docs/decisions.md; CLAUDE.md and PLAN.md updated to match
- [ ] B0: Apple Developer, Play Console, domain, app id, name
- [ ] B1: health-first onboarding; band behind Developer; privacy copy; source check
- [ ] B2: known-answer integration tests on both platforms; writer quirks; H2/H3 gates
- [ ] B3: sign-in, per-account database, sign out, delete account, offline
- [ ] B4: products, paywall, gates, restore, cross-platform Pro
- [ ] B5: diagnostics opt-in, feedback, privacy policy, store forms, beta review
- [ ] B6: waves 1–3; exit criteria met
