# Recovery, strain and sleep app on Mi Band 6 — E2E plan

As of Oct 3, 2026 · Owner: Manish

## Summary

We build a Flutter app for Android and iOS that talks to the Mi Band 6 directly over Bluetooth LE and turns its data into three daily scores: Strain (0–21), Sleep performance (%) and Recovery (0–100%). No Mi Fitness, no Gadgetbridge, no vendor cloud at runtime.

Decisions locked:

- **Stack:** Flutter, one codebase for Android and iOS.
- **Data path:** direct BLE. Our app owns the band; Mi Fitness is used once, only to obtain the auth key. Or, without a band, read-only from Apple Health / Health Connect (decided 2026-10-06; one source per install, see `docs/research/Health connectors plan.md`).
- **Storage:** on the phone first. Raw data is immutable; scores are recomputed from it whenever the algorithm changes. Raw and user-entered data is backed up to GCP end-to-end encrypted (decided 2026-10-21; was "fully on-device, no backend"); scores are never synced. Local backups and data export stay.
- **Hardware:** Mi Band 6 over BLE. Any other watch or ring only through what it writes to Apple Health / Health Connect. No chest straps or other direct sensors.
- **Audience:** a product, released first as a beta (decided 2026-10-21; supersedes "personal tool, sideloaded"). Accounts with sign-up and sign-in; freemium with Pro by subscription or one-time purchase; Apple Health / Health Connect first, the Mi Band behind Developer; backend on GCP with health data synced end-to-end encrypted. See `docs/research/Beta release plan.md` and `docs/research/Backend plan.md`.

The honest ceiling: Mi Band 6 gives per-minute heart rate, steps, sleep stages (light, deep, REM) and a stress index, but not raw beat-to-beat (RR) intervals. Strain and Sleep can match the leading strap's logic closely; Recovery uses the band's stress index as an HRV proxy.

v1 is done when the band syncs in the background on both platforms, the three scores are ready on waking, and they have run for 30 straight days on real data.

## What Mi Band 6 gives us

| Data | How we get it | Feeds |
| --- | --- | --- |
| Per-minute samples: heart rate, steps, intensity, activity kind | Historical activity fetch (Huami service) | Strain, resting HR, sleep detection |
| Live heart rate, ~1 reading/second | Standard BLE Heart Rate service | Live workout screen |
| Sleep stages (light, deep, REM) | Activity-kind codes inside the per-minute samples | Sleep performance |
| Stress index (0–100, derived from HRV by the band) | Separate fetch | Recovery (HRV proxy) |
| SpO2 | Separate fetch | Recovery flag, trends |
| PAI | Separate fetch | Trends only |
| RR intervals / raw HRV | Not exposed by the band | Gap: Recovery uses the stress proxy |

The app sets two band settings during pairing because they decide data quality: HR measurement every 1 minute, and HR-assisted sleep monitoring on.

References: [Gadgetbridge: Xiaomi devices](https://gadgetbridge.org/gadgets/wearables/xiaomi/), [Gadgetbridge changelog](https://www.github.com/Freeyourgadget/Gadgetbridge/blob/master/CHANGELOG.md), [Huami/Xiaomi server pairing](https://gadgetbridge.org/basics/pairing/huami-xiaomi-server/), [huami-token script, issue #1876](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/1876).

## Architecture

Each layer talks only to the one below it. The scoring engine never touches Bluetooth, and the UI never waits on the band.

```
Mi Band 6            per-minute HR, steps, sleep, stress, SpO2
   │
BLE transport        flutter_blue_plus: scan, connect, notify, write
   │
Huami protocol       (Dart) AES auth, fetch commands, record parsers
   │
Sync service         per-type cursors, WorkManager, iOS state restoration
   │
   │      Apple Health / Health Connect ─► health plugin ─► health_source (Dart)
   │                                    (read-only; one source per install)
Local database  ◄──► Scoring engine (pure Dart): Strain, Sleep, Recovery
   │                 reads raw samples, writes daily_scores
State + UI           Riverpod; Today, details, trends, live workout
```

Suggested repo layout:

```
/app                  Flutter app (UI, Riverpod, platform config)
/packages/band_ble    Huami protocol over flutter_blue_plus
/packages/store       Drift schema + DAOs
/packages/scoring     Pure Dart scoring engine (no Flutter deps)
/tools/backtest       CLI: run scoring over an Apple Health export
```

## BLE layer

The band only talks to an app that proves it holds a 16-byte auth key.

1. **Auth key (one time).** Pair the band with Mi Fitness or Zepp Life, then pull the 32-hex-digit key (huami-token script, or grep Mi Fitness logs on Android). Do not remove the band inside Mi Fitness afterwards, because a reset generates a new key. Force-stop or uninstall the app instead.
2. **Authenticate on connect.** On the Huami auth characteristic: request a random challenge, encrypt it with the key using AES-128, send it back, wait for success. Newer firmware needs the "new auth protocol" variant, so implement both and pick by firmware version.
3. **Live heart rate.** Subscribe to the standard Heart Rate Measurement characteristic, start continuous measurement via the HR control point, send a keep-alive at an interval while the workout screen is open.
4. **Historical fetch.** Send "fetch since <last synced minute>" on the fetch-control characteristic, receive chunked per-minute records on the activity-data characteristic, parse, write to the DB, advance the sync cursor. Repeat per data type: activity, stress, SpO2, PAI.
5. **Configure the band** during pairing: time and timezone, user profile (age, weight, height), HR interval 1 minute, sleep assist on, stress monitoring on.

Byte layouts for each record type come from reading Gadgetbridge's Huami parsers as a reference, then are confirmed against a packet log from the real band. **Do not copy Gadgetbridge code** (AGPL-3.0); write our own implementation.

## Data model and storage

SQLite via Drift. Raw data is never edited; every score is derived and recomputable. A year of per-minute samples is ~525,000 rows.

| Table | Key | Columns | Notes |
| --- | --- | --- | --- |
| `minute_samples` | `ts` (minute) | steps, intensity, kind, hr | Raw, never edited |
| `hr_live` | `ts` (second) | bpm, source | Workouts only |
| `stress_samples` | `ts` | value | Raw |
| `spo2_samples` | `ts` | value | Raw |
| `sleep_sessions` | id | start, end, stages (JSON) | Derived from `kind` codes |
| `daily_scores` | date | strain, sleep_perf, recovery, rhr, hrv_proxy, algo_version | Recomputed on algo change |
| `baselines` | metric, window | mean, sd, updated_at | Rolling 30 days |
| `journal` | date, tag | value | Optional behaviours (alcohol, late meal) |
| `sync_state` | device, data_type | last_ts | Fetch cursor |

A "day" runs wake to wake, not midnight to midnight: the sleep that ends a day's strain opens the next day's recovery.

## Scoring engine

A pure Dart package, unit-tested and backtested before band integration exists. The backtest set is an Apple Health export with Mi Fit heart rate, 2020–2026. Every constant is a starting value to calibrate.

### Strain (0–21)

Per-minute Banister TRIMP from heart-rate reserve, summed over the day, compressed to 0–21.

```
HR_r       = (HR - HR_rest) / (HR_max - HR_rest)
TRIMP_day  = Σ_minutes HR_r · 0.64 · e^(1.92 · HR_r)
Strain     = 21 · (1 - e^(-TRIMP_day / k))
```

HR_max starts at 190 bpm and is raised whenever the band records higher. HR_rest is the rolling resting HR from Recovery. Calibrate k so the hardest known training days land around 18–19.

### Sleep performance (%)

Hours slept ÷ hours needed, capped at 100%.

```
Need = 7.5 h + 0.5 · Debt_7d + a · Strain_yesterday
```

Debt = shortfall against need over the last 7 nights, capped at 2 h of carry-over. Start with a = 0.03 h per strain point. Efficiency (asleep ÷ in bed) and deep-sleep share are shown on the detail screen but don't change the score in v1.

### Recovery (0–100%)

Last night vs. the 30-day personal baseline. Each input becomes a signed z-score (higher = better); a weighted sum maps through a logistic curve.

```
z_i      = s_i · (x_i - μ_i,30d) / σ_i,30d
Recovery = 100 / (1 + e^(-1.5 · Σ w_i · z_i))
```

| Input | From | Sign | Weight |
| --- | --- | --- | --- |
| HRV proxy | Band stress index during sleep | Lower is better | 0.4 |
| Resting HR | Lowest 5-minute average during sleep | Lower is better | 0.3 |
| Sleep performance | Score above | Higher is better | 0.3 |

Show "Calibrating" for the first 14 nights. Green 67–100, yellow 34–66, red 0–33.

## App experience

Opens on one screen with three dials (Recovery, Strain, Sleep); every number drills down to the data behind it. Screens read only from the DB, never from BLE.

| Screen | Shows | Reads |
| --- | --- | --- |
| Pairing | Scan, enter auth key, authenticate, write band settings | BLE layer |
| Today | Three dials; one-line coaching ("Recovery 41%, aim for strain under 12") | `daily_scores` |
| Strain detail | Day HR curve, time in zones, strain build-up | `minute_samples` |
| Sleep detail | Hypnogram, need vs actual, debt, efficiency | `sleep_sessions` |
| Recovery detail | Each input against its 30-day baseline | `baselines`, `daily_scores` |
| Live workout | Real-time HR, zone, strain gained this session | `hr_live` |
| Trends | 7 / 30 / 90-day lines for scores, resting HR, stress | `daily_scores` |
| Journal | Yes/no tags each morning | `journal` |
| Settings | HR max, sync status, band settings, data export | `sync_state` |

v1 coaching rule: target strain range is set by today's recovery colour.

## Android vs iOS

| Concern | Android | iOS |
| --- | --- | --- |
| Permissions | `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (12+), notifications | Bluetooth usage description in Info.plist |
| Background sync | WorkManager every few hours; foreground service during workouts | `bluetooth-central` background mode + state restoration; full sync on app open |
| Device identity | MAC address | Peripheral UUID (iOS hides the MAC); store after first pairing |
| Bonding | Handled in-app | System pairing prompt on first encrypted read |
| Main pitfall | OEM battery savers killing the job | Background wakes not guaranteed |

Only one app can hold the band, so Mi Fitness must not be running.

## Milestones

| Phase | Weeks | Scope | Gate to move on |
| --- | --- | --- | --- |
| 0 · Spike | 1–2 | Auth key, AES handshake, live HR on both OSes | Authenticates on Android and iOS |
| 1 · Data sync | 3–5 | History fetch, parsers, Drift storage, band settings | 7 days synced, matches Mi Fitness |
| 2 · Scoring engine | 3–6 (parallel) | Dart package, backtest on Apple Health export | Scores sane over 2020–2026 data |
| 3 · App UI | 6–9 | Today dials, detail screens, trends, live workout | Full day usable without Mi Fitness |
| 4 · Background sync + beta | 10–12 | Background jobs, polish, 30 days of daily use | v1: 30 straight days of scores |
| C0 · Coach groundwork | — | Notification sink seam, decisions logged | Tests pass against a fake sink; device behaviour unchanged |
| C1 · Completion model | — | Schema v8 (plan intent, `nudge_log`), session matching, status chips | 7 real days of statuses match what was actually done |
| C2 · Intra-day replanning | — | RHR / short-night overrides, same-day rescue, carry key sessions, realign, WHO floor | Rule tests pass; 60-day replay override rate accepted |
| C3 · One Coach screen | — | Tempo Coach: session + status, rescue, Also today (focus lever), week glyphs | A week where Coach alone answers "what do I do today?" |
| C4 · Notifications v2 | — | 8 nudge kinds with buttons, 5 channels, caps, quiet hours, backoff | 14-day field diary: buttons work app-closed, ≥ 90 % within 15 min, no day over cap |
| C5 / C6 (deferred) | — | Learned nudge timing; band vibration cues | After 4 weeks of C4 in the field |
| P1 · Goals and progression | — | Training goal (event or open-ended), phases, earned weekly volume steps, lighter every 4th week, taper and race day | A block run for 4+ weeks where each week's step up / hold / step back matches how the week actually went |
| P2 · Goal screen and more goals | — | Goal screen (block timeline, this-week scorecard and forecast, phase explainer, history, how-it-works), rearrange or let go a missed key session, easy rest of week on low recovery/feel, guided setup with race-day calendar and preview, tune-up races, a queued next goal, habits alongside | Same 4-week block check as P1, plus every scorecard verdict matching the week's actual call |
| N1 · Navigation | — | Tabs Today / Coach / Trends / Longevity / Profile; Coach as goal strip + Today / Week / Goal; Journal on Today; Trends with shortcuts and cardio load | A week of use where the goal and Trends are each reached in one tap |
| H0 · Health seam | — | Decisions logged; `packages/health_source`; backtest reads export.xml through it | Backtest runs; package tests pass |
| H1 · Store + scoring | — | Schema 10 (`health_records`, tombstones, `health_minutes`, score source/HRV); algo 8 (per-source baselines, real HRV, source RHR fallback) | Store and scoring tests pass |
| H2 · Apple Health | — | Read access, Health sync, echo guard, onboarding choice, band-only screens hidden | 7 days on an iPhone + watch with no band: scores ready on opening each morning, nights match the Health app |
| H3 · Health Connect | — | Same on Android, history and background permissions, reconcile against silent empty reads | 7 days on an Android phone + watch: background job keeps scores current without opening Tempo |
| E1 · Everyday metrics | — | Sleep regularity and social jetlag (Sleep), body signals (Recovery; Today only when several are off), brisk minutes and longest still stretch (Strain, Trends), heart-rate recovery (Activity); breathing rate from Health | A week of real data where each card's numbers can be checked by hand against the day timeline |
| C7 · Today's picks | — | Three workouts a day (run with type and intervals, strength with focus and exercises, a game you play), sized to readiness, the week and time to bed; one recommended; choosing one makes it today's plan | Two weeks where each day's picks match what a coach would allow (no hard within 48 h of hard, legs fresh before key runs) |
| H4 · Switch and polish | — | Profile → Data source, timer-only live workouts, restore rebuilds Health minutes | Band → Health → band on one install with no lost scores |
| T1 · Teardown next steps | — | Body-signals alert and journal reminder; Journal v2 (catalogue, amounts, automatic entries) and impact engine with experiments; Tempo Age v2 (groups, overlap, confidence, PhenoAge); strength log, progression and freshness; algo 9 (vitals penalty, sleep score v2, load-aware target, source per metric). See `docs/research/Competitor teardown and next steps.md` | Backtest 2020–2026 on the real export with no week of Tempo Age jumping over a year; 4 weeks of logged lifting where each suggested weight is one a coach would set; 14 days of journal with no wrong automatic entry |
| F1 · User flow | — | One voice (`dailyCall`, target follows state); Today as the day's story (phases, one check-in, one insight, Tonight); tabs Today · Plan · (+) · Progress · You; Week in review; first-14-days learning card, welcome back; words by priority. See `docs/research/User flow and journey.md` | 5 people per persona find the goal, last week's review, Tempo Age, logging a lift and pausing in ≤ 2 taps unaided; 14 days with no repeated insight inside its cool-down and none on a rest day; Today and Plan never disagree |

| B0 · Beta decisions and setup | 1 | Open decisions B-O1…B-O9, store accounts, app id and name, backend projects, `docs/network.md` | Every open decision in docs/decisions.md; both store consoles reachable |
| B1 · Health-first | 1–2 | Onboarding without the band, band behind Developer, privacy copy, source check after the first read | A fresh install reaches Today without seeing "band" anywhere |
| B2 · Connector proof | 2–3 | Known-answer integration tests on iOS Simulator and Android emulator, writer quirks (Mi Fitness hour-stamped HR), H2/H3 gates | Tests pass on both; a clean week each on Apple Watch, Mi Fitness (iOS) and one Android watch |
| G0 · GCP foundation | 1 | Terraform for dev and prod, Identity Platform, Firestore, buckets, Pub/Sub, Cloud Run skeleton, App Check, CI | `terraform apply` from clean; app flavours reach their project |
| B3 / G1 · Accounts | 2 | Apple, Google and email-link sign-in, per-account database, sign out, delete account, offline grace | Sign up, sign out, sign in on a second phone, delete, offline: all work |
| B4 / G2 · Billing on GCP | 3–4 | Products, paywall, verify routes, Apple webhooks, Play notifications on Pub/Sub, entitlement engine, restore, cross-platform Pro | Sandbox purchase, renew, upgrade, refund, lapse, restore on both stores; webhook replay idempotent |
| B4 / S1 · Encrypted sync | 3 | `packages/sync`, table classification, keychain / Block Store key, recovery key, restore, compaction | A fresh install restores 90 days to identical scores; server copy unreadable |
| B5 · Beta operations (+ G3, G4) | 2–3 | Crashlytics opt-in, events to BigQuery, feedback, rules tests, alerts, runbooks, privacy policy, store forms, beta review | TestFlight external and Play closed testing live |
| B6 · Beta | 6–8 | Tester waves, weekly builds, tune Free/Pro | Exit criteria in the beta plan |

Phase 0 is the go/no-go. Week counts assume one engineer part-time.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Firmware update changes auth or record format | Sync breaks | Keep the band off Mi Fitness; log firmware version on every connect |
| Band reset invalidates the auth key | Can't connect | Re-extract; store key in secure storage only |
| No raw HRV | Recovery is a proxy | Stress-during-sleep proxy; tune weights against how you feel |
| Porting Gadgetbridge code | AGPL-3.0 contamination | Protocol reference only; own implementation |
| iOS background limits | Scores late some mornings | Sync on open; show last sync time |
| Wrist optical HR lags in intervals/lifting | Strain under-counts | Label workout strain as an estimate |
| Naming and claims | Trademark issues | No competitor or vendor names in the app name; wellness wording only |
| Sparse or late Health data | Strain low, scores change after the morning | Interpolate HR gaps ≤ 15 min; re-read 3 days (10 once a day) and rescore |
| Health read fails silently (empty list) | Records wrongly removed | Tombstone only when the re-read found at least half as many records |
