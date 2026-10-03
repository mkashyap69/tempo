# Whoop-style app on Mi Band 6 — E2E plan

As of Oct 3, 2026 · Owner: Manish

## Summary

We build a Flutter app for Android and iOS that talks to the Mi Band 6 directly over Bluetooth LE and turns its data into three Whoop-style daily scores: Strain (0–21), Sleep performance (%) and Recovery (0–100%). No Mi Fitness, no Gadgetbridge, no vendor cloud at runtime.

Decisions locked:

- **Stack:** Flutter, one codebase for Android and iOS.
- **Data path:** direct BLE. Our app owns the band; Mi Fitness is used once, only to obtain the auth key.
- **Storage:** fully on-device, no backend. Raw data is immutable; scores are recomputed from it whenever the algorithm changes. Backups via data export in Settings.
- **Hardware:** Mi Band 6 only. No Polar H10 or other sensors.
- **Audience:** personal tool. Pairing takes a pasted auth key (no guided key extraction), sideloaded builds, no multi-user accounts in v1.

The honest ceiling: Mi Band 6 gives per-minute heart rate, steps, sleep stages (light, deep, REM) and a stress index, but not raw beat-to-beat (RR) intervals. Strain and Sleep can match Whoop's logic closely; Recovery uses the band's stress index as an HRV proxy.

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
| Naming and claims | Trademark issues | No "Whoop" or "Mi" in the app name; wellness wording only |
