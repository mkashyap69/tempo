# Store launch: Tempo for other people

As of Oct 20, 2026 · Status: proposal, nothing decided. Owner sign-off needed on L-D1–L-D8 before any work starts.

## Summary

Take Tempo from a sideloaded personal tool to an App Store and Google Play app that strangers can install, sign in to, pay for and trust with their health data.

The app is further along than most at this stage: scoring, Coach, goals, Health sources, backups and the "wellness, not medical" wording already exist. What's missing is everything around the app: a product a stranger can set up in two minutes, accounts and sync, billing, store compliance, and a way to find users.

Three things decide the shape of the plan:

1. **Lead with Apple Health / Health Connect, not the Mi Band.** Band pairing needs an auth key pulled with a script against Xiaomi's servers. Strangers won't do that, review teams may reject an app built on it, and the Mi Band 6 is a 2021 device no longer sold. The store product is "WHOOP-style recovery from the watch you already have". The band stays in the personal build (and maybe a hidden Labs toggle on Android later).
2. **Stay private by default, with optional sign-in.** Today every byte stays on the phone. That's the strongest thing Tempo can say against WHOOP, Oura and the rest. Keep it: the app works fully signed out; signing in turns on **end-to-end encrypted** sync and backup, so the server only ever holds ciphertext. We get accounts, restore on a new phone and multi-device without holding readable health data.
3. **Several non-negotiables in CLAUDE.md change.** "No backend or network calls" can't survive accounts, billing and crash reports. The proposal narrows it rather than drops it (see L-D3).

Launch is done when both store listings are live, a stranger goes from install to their first Recovery score in one session, and the app holds a crash-free rate of 99.5 %+ over the first 30 days.

## What changes and what doesn't

| Area | Today | Store build |
| --- | --- | --- |
| Data sources | Band, Apple Health, Health Connect | Apple Health, Health Connect. Band only in the personal build |
| Storage | Drift on the phone, JSON backups to a folder | Same Drift DB, plus optional E2E-encrypted sync |
| Accounts | None | Optional: Sign in with Apple, Google, email link |
| Network | None at runtime | Auth, encrypted sync, billing, crash reports, opt-in analytics. Never plaintext health data |
| Money | None | Free core, Pro subscription |
| Audience | Owner | Anyone 18+ in launch markets |
| Scoring, Coach, goals | Built | Unchanged; first-run backfill from Health history matters more |

## Hard blockers found in the repo

Things that would fail review or hurt strangers as the app stands. Each needs a fix in L1.

| # | Issue | Where | Why it matters | Fix |
| --- | --- | --- | --- | --- |
| B1 | Backups can go to iCloud Drive | `app/lib/src/core/backup.dart:20`, `screens/backups.dart:136` | App Review guideline 5.1.3(ii) says apps may not store personal health information in iCloud (TODO(verify) current wording) | Store build: Tempo's own folder or encrypted sync only; keep folder picker in personal build |
| B2 | `SCHEDULE_EXACT_ALARM` | `AndroidManifest.xml` | Play restricts exact alarms to alarm / calendar apps; Android 14+ denies it by default | Move nudges to inexact alarms or WorkManager windows; drop the permission |
| B3 | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | `AndroidManifest.xml` | Play allows it only for a short list of use cases; band sync was the reason | Drop in the store build (no band); Health Connect background read covers sync |
| B4 | BLE + foreground-service permissions | `AndroidManifest.xml`, `Info.plist` | Unused permissions draw review questions and scare users | Flavor-specific manifests: store flavor has no BLE or connected-device service unless band ships |
| B5 | Name "Tempo" | everywhere | "Tempo" is an established fitness brand (connected home gym). Likely trademark conflict in fitness classes. TODO(verify) with a search in US / EU / India | Pick a new name before any listing, domain or marketing (L-D1) |
| B6 | Terms borrowed from a competitor | Strain 0–21, Recovery % | Close to WHOOP's product language and scale. Generic words are fine, the exact 0–21 scale and copy should be checked | Legal check; consider a 0–100 Load scale for the store build |
| B7 | Owner assumptions in onboarding | `onboarding.dart`, `pairing.dart` | Built for someone who already knows the app | New first-run flow (L1) |
| B8 | Health Connect `WRITE_EXERCISE`, `WRITE_SLEEP` | `AndroidManifest.xml`, `health_export.dart` | Fine (we write our own workouts, not what we read), but each permission needs a declared purpose | Keep, justify in the Play health declaration; ask only when the user turns export on |

## Decisions for the owner

| # | Decision | Recommendation |
| --- | --- | --- |
| L-D1 | New name | Yes, before L1. Short, ownable, .app domain free, no clash in Nice classes 9, 41, 44 |
| L-D2 | Band in the store build | No for launch. Revisit as an Android "Labs" toggle after launch if users ask |
| L-D3 | Amend "fully on-device" | Replace with: *Health data is stored and processed on the device. It leaves only end-to-end encrypted, when the user signs in to sync. Other network calls: sign-in, billing, crash reports without health data, opt-in anonymous usage events.* |
| L-D4 | Accounts required or optional | Optional. Required sign-in costs installs and adds nothing scoring needs |
| L-D5 | Backend | Supabase (Postgres, auth with Apple / Google / email, storage, EU region). Holds users, device list, encrypted blobs. No health columns anywhere |
| L-D6 | Billing | RevenueCat over StoreKit 2 and Play Billing. Free tier + Pro with 14-day free trial |
| L-D7 | Launch markets | English first: US, UK, Canada, Australia, India. Add EU after a GDPR review (health data is special-category) |
| L-D8 | Seller | A company, not a personal account. Lets you take a Play organisation account (skips the personal-account 12-testers-for-14-days rule, TODO(verify)), keeps your name off the listing and limits liability |

## Accounts and storage design

Keep the device as the source of truth. The server is a dumb, encrypted mailbox.

```
Phone A ── Drift DB ── change log ── encrypt (data key) ──► Supabase storage
                                                             │  ciphertext only
Phone B ◄── decrypt ◄────────────────────────────────────────┘
```

- **What syncs.** Raw tables (`minute_samples`, `health_records` with tombstones, `stress_samples`, `spo2_samples`, workouts, `hr_live`) and user-authored rows (journal, goals, strength log, settings in the backup allow-list). **Not** `daily_scores` or `baselines`: they're derived, so each phone recomputes them. This is why the append-only rule pays off: raw tables merge by union.
- **Mutable rows** (journal, goals, settings) get a hybrid logical clock and last-writer-wins per row.
- **Format.** Reuse the backup JSON: an initial full snapshot, then append-only change batches, each gzipped and encrypted (XChaCha20-Poly1305). Compact into a new snapshot every 30 batches.
- **Keys.** A random 256-bit data key per account. It's wrapped by a key derived from a recovery code shown once at sign-up (Argon2id), and the wrapped copy is also kept in the platform keychain (iCloud Keychain / Google Block Store) for a silent restore. Losing both means losing synced data; the local DB is unaffected. Say so plainly in the UI.
- **Server tables.** `users`, `devices`, `blobs (user_id, seq, size, created_at, object_key)`, `entitlements` (mirrored from RevenueCat webhooks). Row-level security on everything.
- **Account deletion** in the app (App Review 5.1.1(v)): deletes server rows and blobs, keeps local data unless the user also wipes it.
- **Health data from Apple Health / Health Connect.** Re-syncing it is allowed only because it's encrypted and for the user's own use. Never for ads, never sold, never readable by us. TODO(verify) against HealthKit and Health Connect terms before L2.

New package: `/packages/sync` (pure Dart: change log, HLC, merge, crypto envelopes, all unit-tested), with a thin Supabase adapter in `/app`.

## What's free and what's Pro

| Free | Pro |
| --- | --- |
| Recovery, Strain, Sleep score every day | Tempo Coach: plans, rescue, notifications |
| 7-day trends | Goals and progression, tune-ups, next goal |
| Today, day timeline, workouts | 30 / 90 / 365-day trends, cardio load |
| Local backups | Journal impact engine and experiments |
| | Longevity / Tempo Age, labs |
| | Encrypted sync across phones |

Price to start: **$5.99 / month or $39.99 / year** (India: ₹199 / ₹1,499 via store price tiers). That's under Oura's membership and far under WHOOP, near Athlytic and Bevel Pro. Test the annual price in month two. TODO(verify) all competitor prices at launch time.

## Milestones

Same rule as PLAN.md: no phase starts until the previous gate passes. Weeks assume one engineer part-time, as before.

| Phase | Weeks | Scope | Gate to move on |
| --- | --- | --- | --- |
| L0 · Decisions and paperwork | 1–2 | L-D1–L-D8 signed off; company, D-U-N-S, Apple and Play developer accounts; name, domain, trademark search; privacy policy and terms drafted (lawyer review); CLAUDE.md non-negotiables amended | Accounts open, name cleared, docs/decisions.md updated |
| L1 · Store-ready build | 3–6 | `store` and `personal` flavors; B1–B8 fixed; new first-run (pick source → permissions with plain reasons → backfill up to 90 days of Health history → first scores in the same session); empty, sparse and no-watch states; accessibility pass (Dynamic Type, TalkBack / VoiceOver, contrast); in-app privacy screen; delete-all-data | 5 people who've never seen Tempo install from a test build and reach a score unaided; no BLE strings in the store flavor |
| L2 · Accounts and sync | 5–9 | `/packages/sync`; Supabase project (EU or US region), RLS, auth; recovery code and keychain restore; two-phone sync; account deletion | Sync tests pass; two phones converge after 7 days of offline edits; a server dump shows no readable health data |
| L3 · Billing and paywall | 8–10 | RevenueCat, products in both stores, trial, paywall after first Recovery score (not before), restore purchases, entitlement gates on Pro screens | Sandbox purchase, renewal, cancel and restore pass on both OSes |
| L4 · Quality and telemetry | 9–11 | Crash reporting (Sentry, health fields scrubbed); opt-in analytics (TelemetryDeck or PostHog EU, event names only); device matrix: iPhone + Apple Watch, Pixel + Pixel Watch, Galaxy + Galaxy Watch, a Garmin and an Oura via Health (TODO(verify) which write to Health Connect); CI builds for both stores | Crash-free 99.5 % in beta; the H2 / H3 7-day gates passed on testers' phones, not just the owner's |
| L5 · Beta | 11–14 | TestFlight (external, up to 10k) and Play closed testing; 50–100 testers from the waitlist; in-app feedback; weekly builds | D7 retention ≥ 35 % in beta; top 10 issues fixed; store review dry runs passed |
| L6 · Launch | 15–16 | Listings, screenshots, preview video, privacy labels / Data safety, HealthKit and Health Connect declarations, phased rollout | Both live; phased rollout reaches 100 % with no blocker |
| L7 · After launch | 17+ | Weekly releases for a month, reviews answered within 48 h, pricing test, Labs band toggle decision, localisation if data says so | 30-day numbers below |

## Store compliance checklist

**Apple**
- HealthKit entitlement; `NSHealthShareUsageDescription` (and update description if export stays) in plain words.
- Privacy nutrition label: health and fitness data "not linked to you, not used for tracking"; with sync on, linked but encrypted. TODO(verify) how Apple wants E2E data declared.
- Privacy policy URL; in-app account deletion; Sign in with Apple offered alongside Google (guideline 4.8).
- Category: Health & Fitness. No diagnostic claims. Longevity and labs copy reviewed against guideline 1.4.1.
- No health data in iCloud (B1). No HealthKit data to third parties, analytics or ads.

**Google Play**
- Health apps declaration and Health Connect permissions declaration, each permission with a purpose; a video of the permission flow may be asked for.
- Data safety form matching the app exactly, including the encrypted sync.
- Restricted permissions removed (B2, B3); foreground-service types declared if any remain.
- Personal developer accounts must run a closed test with 12+ testers for 14 days before production (TODO(verify) current rule). An organisation account avoids it (L-D8).
- Target the current required API level.

**Both:** "wellness tool, not a medical device" in the listing, onboarding and Learn (already in the app). No disease words (AFib, apnea, diagnose, treat). Age gate 18+ for labs and Tempo Age.

## Legal and privacy

- **Medical-device line.** US FDA general-wellness policy, EU MDR, India CDSCO: stay on the wellness side. Scores describe your own trends; no thresholds that say "see a doctor for X" beyond a generic line. Get one hour of a regulatory lawyer's time on Longevity, labs and body-signal alerts before launch.
- **Data protection.** GDPR (health data is special-category; needs explicit consent and a DPIA), UK GDPR, India DPDP Act 2023, US state health-privacy laws (Washington My Health My Data Act applies to wellness apps). E2E encryption and on-device processing make all of these much lighter, which is the point of L-D3.
- **Open source.** No Gadgetbridge code in the store build at all (band excluded). Run a licence scan over dependencies in CI.
- **Docs to publish:** privacy policy, terms (with subscription terms), a one-page "how your data is handled" in plain words, a security contact.

## Go-to-market

### Who it's for

**Primary:** people 25–45 who train 3+ times a week (runners, gym, hybrid), already wear an Apple Watch, Galaxy Watch, Pixel Watch or similar, and have looked at WHOOP or Oura but don't want another device or a $200+/year membership.

**Secondary:** existing WHOOP users leaving at renewal; data-minded people who care where health data goes.

Validate both in L5: who stays past day 7?

### Positioning

> Recovery, strain and sleep scores and a coach that plans your week, from the watch you already wear. Your data stays on your phone.

Three proof points, in this order:
1. **No new hardware, no $30/month.** Works with what's already in Apple Health / Health Connect, scores from day one using your history.
2. **A coach, not just a dashboard.** Today's picks, goals with real progression, same-day replanning. Most competitors stop at the score.
3. **Private by design.** Processed on the phone; synced only end-to-end encrypted. We can't read it, sell it or lose it in a breach.

### Competitors to watch (TODO(verify) features and prices at launch)

| App | Hardware | Strength vs Tempo | Where Tempo wins |
| --- | --- | --- | --- |
| WHOOP | Own strap, membership | Brand, community, 24/7 HRV | No device, a fraction of the price, coach and goals |
| Oura | Ring + membership | Sleep, form factor | No device, training focus |
| Athlytic | Apple Watch, iOS only | Closest copy of the idea, cheap | Android too, coach and goals, journal impact |
| Bevel | Apple Watch, iOS | Polished, nutrition | Android, training plans, privacy story |
| Garmin / Samsung / Fitbit built-ins | Their own watch | Free, built in | Works across brands, deeper coach |

The honest gap: Android has fewer good options than iOS. Galaxy and Pixel Watch owners are an easier beachhead than Apple Watch owners, where Athlytic and Bevel are established. Launch on both, but aim early community and ad spend at Android, and watch which side converts.

### Channels, in order of cost

1. **App Store Optimisation.** Title + subtitle around "recovery", "HRV", "sleep score", "strain", "readiness". Screenshots that show the coach, not just rings. Localised keywords per market. Ask for a rating after the third green-recovery morning, never on day one.
2. **Communities.** r/AppleWatchFitness, r/GalaxyWatch, r/PixelWatch, r/whoop, r/running, r/Garmin, r/QuantifiedSelf, Strava clubs. Be useful first: posts on how the scores work (the Learn screen content is ready-made). Follow each subreddit's self-promotion rules.
3. **Build in public.** X / Threads / LinkedIn: weekly posts on the algorithm, backtests over 6 years of real data, design decisions. Turns PLAN.md and decisions.md into content.
4. **Reviewers and creators.** 15–30 small-to-mid fitness-tech YouTubers and bloggers who review WHOOP alternatives. Free lifetime Pro, an honest-review ask, a comparison sheet. One good wearables reviewer is worth more than months of posts.
5. **Launch spikes.** Product Hunt, Hacker News "Show HN" (privacy and on-device angle fits that audience), Indie Hackers. Same week as store launch.
6. **Referrals.** Give a month of Pro, get a month. Shareable weekly report card (already built as Weekly report) as the organic loop.
7. **Paid**, only after organic numbers say the funnel works: Apple Search Ads on competitor and "HRV" keywords, then Meta / Reddit ads to Android watch owners. Start at $20–30/day, stop if cost per trial is over a third of first-year revenue.

### Launch timeline

| When | What |
| --- | --- |
| L0 (T−14 weeks) | Name, domain, one-page site with waitlist (static, no tracking beyond a privacy-friendly counter); social handles |
| L1–L4 (T−12 to T−6) | Build-in-public posts weekly; collect waitlist; line up 20 creators |
| L5 (T−5 to T−2) | Beta from the waitlist; collect testimonials and screenshots from real users (with consent); press kit |
| L6 (launch week) | Phased rollout starts Monday; Product Hunt Tuesday; Show HN Wednesday; creator embargo lifts; waitlist email with a launch-week discount on annual |
| L7 (T+1 to T+8 weeks) | Weekly releases; reply to every review; first pricing test; first paid tests if funnel numbers hold |

### Numbers to watch

| Metric | Definition | 30-day target |
| --- | --- | --- |
| Activation | Health connected and first Recovery seen in the first session | 60 % of installs |
| D1 / D7 / D30 | Opened Today on that day | 50 % / 30 % / 15 % |
| Trial start | Started Pro trial | 25 % of activated |
| Trial → paid | Paid after trial | 35 % |
| Crash-free sessions | From crash reports | 99.5 % |
| Store rating | Average | 4.5+ |

Targets are guesses for a health-and-fitness subscription app; reset them after beta. Measure through opt-in events only; on-device funnels can be computed locally and sent as counts.

## Costs to start (per year, rough)

| Item | Cost |
| --- | --- |
| Apple Developer Program | $99 |
| Google Play (one-time) | $25 |
| Company, D-U-N-S, trademark filing (one class, one country) | $300–1,500 depending on country |
| Lawyer: privacy policy, terms, regulatory hour | $1,000–3,000 |
| Supabase, Sentry, RevenueCat, analytics | $0 on free tiers to start; Supabase Pro $25/month once real users arrive; RevenueCat takes ~1 % above its free revenue band |
| Domain, site hosting | ~$50 |
| Store fees | 15 % of revenue under the small-business programs |
| Test devices you don't own (Galaxy Watch, Pixel Watch) | $300–600 used |

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Health review rejection (HealthKit, Health Connect declaration) | Launch slips weeks | Dry-run submissions in L5; plain permission reasons; ask only for what's used |
| Sparse watch data (non-Apple, budget watches) | Poor scores, bad reviews | HR coverage already tracked; show "not enough data" honestly; list tested watches |
| Scores feel wrong to strangers | Churn in week one | Backfill history so baselines exist on day one; explain every number (Learn); beta feedback loop |
| Trademark dispute after launch | Forced rename, lost ASO | Clear the name in L0 (B5) |
| Losing the recovery code | Synced data gone | Keychain copy, clear warning, local data unaffected |
| Breach of the backend | Reputational | Server holds ciphertext only; no health columns; RLS; security contact |
| Medical claim complaints | Store removal, regulator letters | Wellness wording, legal review of Longevity and alerts |
| One engineer part-time | 16 weeks becomes 30 | Cut L2 from the launch if needed: ship signed-out with local backups, add sync as a Pro feature in L7 |

## Fastest path if time is short

If the 16 weeks are too many: ship L0 + L1 + L3 + L4, skip accounts. The app launches private and signed-out, with local backups, Free and Pro. Sync and sign-in (L2) follow as the first big update, which also gives launch number two to market. This keeps the strongest message ("we never see your data") fully true at launch.
