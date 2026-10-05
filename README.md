# Tempo

A personal recovery and strain tracker for the **Xiaomi Mi Band 6**, built in Flutter for Android and iOS.

Tempo talks to the band directly over Bluetooth LE and turns its data into three daily scores:

| Score | Range | Answers |
| --- | --- | --- |
| **Recovery** | 0–100 % | How ready is my body today, compared with my own last 30 days? |
| **Strain** | 0–21 | How much cardiovascular load did I take on today? |
| **Sleep** | 0–100 % | Did I get the sleep I needed last night? |

Everything stays on your phone. There is no account, no cloud and no vendor app running in the background.

> **Status: pre-release, untested on hardware.** Phases 0–4 of the plan are implemented, but the app has not yet been run against a real band. Bluetooth details are marked `TODO(verify)` until a packet capture confirms them. Expect the first run to need fixes. See [`docs/testing.md`](docs/testing.md).

> Tempo is a personal wellness tool, not a medical device. Its scores are estimates and must not be used for diagnosis or treatment.

---

## Contents

- [For users](#for-users)
  - [What you need](#what-you-need)
  - [Get your band's auth key](#get-your-bands-auth-key)
  - [Install](#install)
  - [Pair the band](#pair-the-band)
  - [Using the app](#using-the-app)
  - [How the scores work](#how-the-scores-work)
  - [Privacy](#privacy)
  - [Known limitations](#known-limitations)
  - [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)
  - [Architecture](#architecture)
  - [Repository layout](#repository-layout)
  - [Setup](#setup)
  - [Running](#running)
  - [Tests](#tests)
  - [Working on the Bluetooth protocol](#working-on-the-bluetooth-protocol)
  - [Changing a score](#changing-a-score)
  - [Background sync](#background-sync)
  - [Rules of the codebase](#rules-of-the-codebase)
  - [Project docs](#project-docs)

---

## For users

### What you need

- A **Mi Band 6**.
- An **Android phone** (Android 7.0 or later) or an **iPhone** (iOS 15 or later).
- The band's **auth key**: a 32-character code that proves the app is allowed to talk to the band. You get it once (next section).
- For now, a computer with Flutter to build and install the app. There is no app-store release; Tempo is sideloaded.

Only one app can hold the band at a time. Once Tempo is set up, **don't run Mi Fitness or Zepp Life** alongside it.

### Get your band's auth key

1. Pair the band with **Mi Fitness** or **Zepp Life** as normal.
2. Extract the key using one of the community methods, such as the `huami-token` script ([background](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/1876)), or from Mi Fitness logs on Android.
3. **Don't remove the band inside Mi Fitness** afterwards, because that resets the band and the key stops working. Force-stop or uninstall the app instead.

Keep the key private. Anyone with it can connect to your band.

### Install

Tempo isn't on the Play Store or App Store. Build it from source:

```bash
git clone https://github.com/mkashyap69/tempo.git
cd tempo
flutter pub get
cd app
flutter run --release          # phone connected by USB
```

On iOS you need a Mac with Xcode and an Apple developer account (a free account works, but the install expires after 7 days). Open `app/ios/Runner.xcworkspace`, set your signing team and a bundle ID you own, then run.

### Pair the band

1. Force-stop Mi Fitness / Zepp Life.
2. Open Tempo. A short onboarding asks for your age, height, weight and max heart rate (estimated from age if you don't know it), your goal, the workouts you like, and the days and minutes you can train.
3. Allow Bluetooth (and, optionally, notifications for the morning call and bedtime nudge).
4. Tempo scans for 30 seconds and lists bands by signal strength. Pick yours (check the last characters under Settings › About on the band).
5. Paste your auth key. Tempo checks it is 32 hex characters before it lets you connect. It's stored in the phone's secure storage (Android Keystore / iOS Keychain) and nowhere else.
6. Tempo connects, authenticates, turns on the sensors it needs and pulls the **last 7 days** of history. This can take a minute.

During pairing Tempo changes the band settings that matter for score quality: **heart rate every 1 minute**, **HR-assisted sleep detection** and **stress monitoring**, and it sets the time. Pairing errors (band not found, wrong key, band busy with another app) each have their own screen with what to try.

### Using the app

Five tabs and a start button:

| Tab | What it shows |
| --- | --- |
| **Today** | One coaching line ("Recovery 78% — you're primed… aim for 13–16 strain"), three nested rings for Recovery, Strain (with today's target marked) and Sleep, today's suggested workout, a 7-day recovery and strain chart, a time-in-zones donut, a cardio-load gauge, last night's sleep stages with tonight's bedtime, and today's workouts. Pull down to sync. Tap any ring, chart or card for its detail. |
| **Coach** (Tempo Coach) | Today's readiness (recovery, plus resting HR against your baseline and last night's length), the suggested workout with its status (Planned 18:00, Done ✓, Not seen yet, Missed) and buttons to move it to the evening, mark it done or skip it. If your morning session didn't happen, a card offers what still fits before bed: the full session if it ends 4 h before bedtime (hard) or 1 h (easy), else a shorter easy version, else a 20′ walk. Missed key sessions carry to a later day; missed easy ones drop; three missed days offer to rebuild the week. *Also today* turns your Longevity focus into today's actions (steps, Zone 2 minutes, strength, bedtime). Then this week's plan with done/missed marks, load trend, your focus and Learn cards. |
| **Longevity** | **Tempo Age**: your age adjusted by 30 days of cardio fitness (estimated VO₂max), resting HR, steps, Zone 2+ minutes, strength sessions, sleep length and regularity, night breathing and stress, plus optional smoking, alcohol, blood pressure and waist. Shows years younger or older, pace of aging once there are two months of snapshots, every contributor as ± years, and your biggest levers. *Make this my focus* starts a 4–12 week plan: Coach rebuilds the week around it (Zone 2 sessions, two strength days) and the card tracks this week against the target. **Trends** lives here too: 7 / 30 / 90-day cards for recovery, strain, sleep, resting HR, stress, SpO₂ and steps, plus the day timeline, baselines, a recovery calendar and data health. Tempo Age is a wellness estimate, not a medical result. |
| **Journal** | A five-tap morning check-in (alcohol, late meal, late caffeine, stressful day, travel). After 30 check-ins it shows what each one does to your next-morning recovery, with sample size and confidence. |
| **Profile** | Band status and battery estimate, your details, training preferences, pause (ill or travelling), band settings (HR interval, sleep detection, stress monitoring and wrist are written to the band), background sync, notifications, export (CSV or JSON), restore from a JSON export, Apple Health / Health Connect export, weekly report share card, re-pair, delete all data, theme. |

**Coach notifications.** Tempo schedules the next 48 hours on the phone and replaces them after every sync, app open and button press: a quiet morning brief (*Open · Easier · Rest today*), a session reminder 15 minutes before your slot (*Start · Later 1h · Skip*), a check two hours after a missed morning slot (*Done already · Plan 18:00 · Skip*), a mid-afternoon nudge when your focus lever is behind, a wind-down before bedtime, a rating prompt after a detected workout (*Easy · Moderate · Hard*) and a once-only alert when your night heart rate runs well above usual (*Pause 3 days · I'm fine*). By default at most one unrequested coach nudge a day, 4 notifications a day and 14 a week, nothing between bedtime and waking, 90 minutes apart; a kind you ignore 3 times in a row slows to every other day and pauses for a week after 5. Profile → Notifications → Tempo Coach sets your training slots, the daily cap (0–2), each kind, and on Android optional precise reminders. Every decision and answer is logged on the phone (`nudge_log`).

The **play button** starts a workout: today's suggested session (guided intervals, with a buzz on the band 5 s before each change) or an open session for any sport. You can minimise it and come back; on Android a foreground service keeps the band connection while the screen is locked. At the end you rate how hard it felt (RPE). Coach uses the ratings: sessions that keep feeling harder than planned ease the next hard day, sessions that feel easy step one up. For strength sessions, where wrist HR undercounts, the rating also sets the session's load.

Every detail screen explains itself: Recovery breaks down what moved it against your 30-day baseline, Strain shows the day's heart rate, time in zones and how it built up, Sleep shows the hypnogram, need, debt and tonight's bedtime, and so on.

**Workouts.** Longevity → Trends → *Workouts* (or *All ›* on Today and Strain) lists every workout: ones you record with the band's own Workout app (fetched on sync, marked *From band*), live sessions started in Tempo, and walks, runs and rides Tempo spots from heart rate and steps. The band's workout format is still being confirmed on real hardware: if a band workout doesn't appear, send a packet log from a sync right after one.

**Home-screen widgets.** Small (Recovery) and medium (Recovery, Strain, Sleep). Tapping a score opens its detail screen. On Android add them from the launcher's widget list. On iOS the widget extension needs a one-time Xcode step, see [`app/ios/TempoWidget/README.md`](app/ios/TempoWidget/README.md).

**Syncing.** Tempo syncs when you open the app and in the background: every 3 hours on Android, and whenever iOS allows it on iPhone. The band holds several days of data, so a missed sync catches up next time. If the band's memory filled before a sync, Data health logs a gap with the minutes lost. On Android, Tempo asks once to be left out of battery optimisation so overnight syncs keep running.

**Pause.** Ill or travelling? Profile → *Pause*. Scores still show, but those days don't move your baselines, calibration or learned sleep need, and Coach stops adapting the plan until you resume.

**Smart alarm.** Sleep → Tonight → *Smart alarm* writes an alarm to the band that buzzes in light sleep up to 30 minutes before the time you pick.

**Your first two weeks.** Recovery shows **Calibrating** for the first 14 nights while Tempo learns your baseline. Strain and Sleep work from day one.

**A "day"** runs from when you wake up to when you next fall asleep, not midnight to midnight. Last night's sleep sets this morning's recovery, and today's strain feeds tonight's sleep need.

### How the scores work

All three scores are calculated on your phone from the band's per-minute data. Every constant is a starting point that will be tuned over time.

**Strain (0–21).** For every minute, your heart rate is placed between your resting HR and your HR max (Banister TRIMP). Minutes below 30 % of that range (sitting, pottering about) count for nothing; above it, harder minutes count much more than easy ones. A desk day lands near 0, an easy run day around 5–8, a threshold session around 13 and two hard hours past 18. Strength sessions you rate count as at least their session-RPE load. The day's total is squeezed onto a 0–21 scale, so going from 18 to 19 takes far more work than going from 5 to 6. HR max starts at 190 and rises automatically if the band ever records higher; you can also set it in Profile.

**Sleep performance (%).** Hours slept ÷ hours needed, capped at 100 %.
Need = your base need + half of your recent sleep debt (capped at 2 h) + a little extra for yesterday's strain. The base starts at 7.5 h; after 14 scored nights it becomes the median sleep on the third of nights you recovered best after (kept between 6.5 and 9.5 h). Naps of 20 minutes or more count against the debt.

**Recovery (%).** Last night compared with your own 30-day baseline:

| Input | Better when | Weight |
| --- | --- | --- |
| Stress during sleep (the band's HRV-based stress index) | Lower | 40 % |
| Resting heart rate (lowest 5-minute average while asleep) | Lower | 30 % |
| Sleep performance | Higher | 30 % |

▲ Primed 67–100 · ■ Steady 34–66 · ▼ Low 0–33. Recovery sets today's strain target (13–16 at 67–79%, higher on greener mornings, 8–12 below 50%); a low morning or an overreaching week turns it into a cap of 8 and makes today a rest day. While calibrating the target is a general 10–14.

**Cardio load.** Your last 7 days of strain-weighted heart rate (TRIMP) against your last 28: below 0.8× is detraining, 0.8–1.0× maintaining, 1.0–1.3× building, above 1.3× overreaching.

**The plan.** Coach builds each week from your goal, the workouts you like and the days and minutes you have, with at most two hard sessions and never two in a row. After the first sync each morning it adapts today and the next two days to your recovery, load and recent RPE, and says what changed and why: a rest morning also makes tomorrow's hard session easy, and two hard days never sit back to back. A displaced hard session moves at least 48 h later.

The Mi Band 6 doesn't expose raw beat-to-beat (HRV) data, so Recovery uses the band's stress index as a stand-in. It's a reasonable proxy, not a true HRV measurement.

### Privacy

- **No network.** Tempo makes no network calls at runtime. There are no servers, analytics or accounts.
- **On-device database.** All data lives in a local SQLite database on your phone.
- **The auth key** is kept only in secure storage. It's never written to logs, the database or exports.
- **Export.** Profile → *Export* writes CSV (one file per table) or one JSON file and opens the share sheet. *Restore from export* reads that JSON file back (on a new phone, say); samples already on the phone are kept.
- **Apple Health / Health Connect.** Off by default. When you turn it on, Tempo writes confirmed workouts and nights with sleep stages after each sync. It never reads Health data.
- **Delete.** Profile → *Delete all data* removes the database and the key. *Re-pair or change band* removes the pairing and starts over.
- **Packet logs.** The app writes a log of Bluetooth traffic to its documents folder for debugging. It contains your band's data but never the key.

### Known limitations

- **Untested on hardware.** See the status note at the top.
- **One band, one person.** No multi-user support.
- **Live workouts on iPhone** need Tempo open or recently used; iOS has no foreground service. On Android a foreground service holds the connection.
- **Background sync on iPhone isn't guaranteed.** iOS decides when it runs. Opening the app always syncs.
- **Wrist heart rate lags** during intervals and weightlifting. Rate strength sessions so their load counts; intervals may still be undercounted.
- **Firmware updates** can change the band's protocol. Avoid updating the band through Mi Fitness.

### Troubleshooting

| Problem | Try |
| --- | --- |
| Band doesn't appear in Scan | Force-stop Mi Fitness / Zepp Life, toggle Bluetooth, keep the band close. On Android allow the "Nearby devices" permission. |
| "Band rejected key" | The key is wrong or stale (the band was reset). Extract it again. |
| "No auth variant got a challenge" | Probably a protocol difference on your firmware. Send the packet log (see below). |
| Sleep times look shifted or doubled | Builds from before 5 Oct stored some minutes 5 h 30 m late. Data health → *Re-download band history* replaces them with a fresh copy from the band. |
| No sleep stages | Stages are estimated from heart rate, which needs HR every minute. Tempo sets that on the next sync; the night after will have stages. |
| Sleep dial stays empty | Send the packet log and an export. |
| Recovery stuck on Calibrating | Normal for the first 14 nights with sleep data. |
| Scores look wrong after an update | Profile → Advanced → *Recompute all scores*. |

**Sending a packet log:** on Android with USB debugging on, run `tools/pull_packets.sh` from the repo. On iOS, use Xcode → Devices → Download Container and take `AppData/Documents/packets/`. Open an issue with the log attached.

---

## For developers

### Architecture

Each layer talks only to the one below it. The scoring engine never touches Bluetooth, and the UI never waits on the band. Screens read only from the database.

```
Mi Band 6            per-minute HR, steps, sleep, stress, SpO2
   │
BLE transport        flutter_blue_plus: scan, connect, notify, write
   │
Huami protocol       packages/band_ble: AES auth, fetch, record parsers
   │
Sync service         app/lib/src/core: per-type cursors, WorkManager / BGTask
   │
Local database  ◄──► Scoring engine     packages/store  ◄──►  packages/scoring
   │
State + UI           app/lib/src: Riverpod, CustomPainter charts
```

### Repository layout

```
app/                    Flutter app
  lib/src/core/           sync, scoring service, coach plan, band link, key store,
                          background, notifications, home-screen widgets, export
  lib/src/state/          Riverpod providers, live workout session
  lib/src/design/         design system: tokens, type, icons, components, charts
  lib/src/screens/        every screen from the design canvas
  ios/TempoWidget/        WidgetKit extension sources
  assets/fonts/           Geist and Geist Mono (OFL)
packages/
  band_ble/             Huami protocol on flutter_blue_plus (our own implementation)
  store/                Drift schema + DAOs (raw tables append-only)
  scoring/              Strain / Sleep / Recovery, pure Dart
tools/
  backtest/             CLI: run scoring over an Apple Health export
  pull_packets.sh       copy packet logs off an Android device
  brand/make_icons.py   renders the mark into app icons and launch images
docs/
  decisions.md          dated decision log
  testing.md            end-to-end hardware test plan
  packets/              captured BLE logs (source of truth for the protocol)
PLAN.md                 product and technical plan
CLAUDE.md               working rules for this repo
```

It's a [Dart pub workspace](https://dart.dev/tools/pub/workspaces): one `flutter pub get` at the root resolves every package, with a single lockfile.

### Setup

Requirements: Flutter 3.30+ (Dart 3.13+); Android Studio / Android SDK for Android; a Mac with Xcode and CocoaPods for iOS.

```bash
git clone https://github.com/mkashyap69/tempo.git
cd tempo
flutter pub get
cp .env.example .env    # then set BAND_AUTH_KEY=<32 hex digits>
```

`.env` is git-ignored. Never commit it.

### Running

```bash
cd app
flutter run --dart-define-from-file=../.env
```

In **debug builds**, `BAND_AUTH_KEY` from `.env` is copied into secure storage on first launch, so you don't have to paste the key each time. This builds the key into the debug binary, so never share a debug build made this way. Release builds ignore it and ask for the key on screen.

### Tests

```bash
flutter analyze
(cd packages/scoring && dart test)
(cd packages/store   && dart test)
(cd tools/backtest   && dart test)
(cd packages/band_ble && flutter test)
(cd app              && flutter test)
```

The store tests need a system `libsqlite3`.

After changing the database schema, regenerate the Drift code and commit the output:

```bash
cd packages/store && dart run build_runner build
```

Backtest the scoring engine over an Apple Health export (no band needed):

```bash
cd tools/backtest
dart run bin/backtest.dart ~/export.xml > scores.csv
# options: --source "Mi Fit|Zepp"  --fill 10  --from 2024-01-01  --to 2024-12-31
```

### Working on the Bluetooth protocol

The protocol layer is the riskiest part of the project. The rules:

1. **Never guess.** Every UUID, opcode and byte layout not yet confirmed against a capture from a real band is marked `// TODO(verify)`.
2. **Capture first.** Every packet the app sends or receives is written as JSON Lines to `<app documents>/packets/`. Pull them with `tools/pull_packets.sh` and commit them to `docs/packets/` (format: [`docs/packets/README.md`](docs/packets/README.md)). The encrypted auth reply is redacted, and the key is never logged.
3. **Confirm, then remove the marker.** When a capture confirms a detail, delete its `TODO(verify)` and add a **golden test** built from the captured bytes.
4. **Our own implementation only.** Gadgetbridge is useful for understanding the protocol, but it's AGPL-3.0. Don't copy its code or translate it line by line.

**Band explorer** (Data health → *Band explorer*, or Profile → Advanced) is the fastest way to get a capture of everything at once. It is read-only: it reads every readable characteristic, asks the band about every history type code `0x00`–`0x3f` without transferring or acknowledging (so the band deletes nothing), and records two minutes of raw live heart rate to see whether beat-to-beat (RR) intervals arrive. It saves `explorer-<time>.json` next to the packet log and can share both. Note Mi Fitness's numbers for the same day (VO₂ max, resting HR, stress, sleep stages) when you run it, so unknown values can be matched to known ones.

Most unverified details are in `packages/band_ble/lib/src/`: `uuids.dart`, `protocol.dart` (auth, live HR), `fetch.dart` (history fetch, record layouts, sleep codes) and `settings.dart` (band configuration).

### Changing a score

- **Purity.** `packages/scoring` is pure Dart with no Flutter or BLE imports, and every formula has unit tests.
- **Bump `algoVersion`.** It's in `packages/scoring/lib/src/types.dart`. Every stored score carries the version that produced it, and the app recomputes all scores from raw data when the version changes.
- **Raw data is never edited.** The raw tables (`minute_samples`, `hr_live`, `stress_samples`, `spo2_samples`) are append-only, enforced by SQL triggers. Scores are always derived and can always be recomputed.
- **Check the backtest** before and after the change.

### Background sync

| Platform | Mechanism | Where |
| --- | --- | --- |
| Android | WorkManager periodic task, every 3 h | `app/lib/src/core/background.dart` |
| iOS | BGAppRefresh task `tempo.sync`, `bluetooth-central` background mode, CoreBluetooth state restoration, plus sync on open/resume | `background.dart`, `ios/Runner/AppDelegate.swift`, `Info.plist` |

The sync connects, authenticates, fetches each data type from its cursor in `sync_state`, appends the raw rows, advances the cursor and rescores the affected days.

### Rules of the codebase

- Direct BLE to the band. No Gadgetbridge, Mi Fitness or vendor cloud at runtime.
- Fully on-device. No network calls apart from package fetches at build time.
- The auth key lives only in `flutter_secure_storage`. Never log, commit or hardcode it.
- Record every decision as one dated line in [`docs/decisions.md`](docs/decisions.md).
- Work follows the milestones in [`PLAN.md`](PLAN.md).

### Project docs

- [`PLAN.md`](PLAN.md): goals, data model, scoring formulas, milestones, risks.
- [`docs/testing.md`](docs/testing.md): step-by-step hardware test plan for Android and iOS.
- [`docs/decisions.md`](docs/decisions.md): why things are the way they are.
- [`docs/packets/`](docs/packets/): BLE captures.
- [`docs/design.md`](docs/design.md): where each board of the design canvas lives in the code.

---

*Tempo is an independent personal project. It isn't affiliated with or endorsed by Xiaomi, Huami/Zepp or WHOOP. Product names are used only to describe compatibility.*
