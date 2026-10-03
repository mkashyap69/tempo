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
2. Open Tempo. The pairing screen appears.
3. Paste your auth key. It's stored in the phone's secure storage (Android Keystore / iOS Keychain) and nowhere else.
4. Enter your birth year, height, weight and sex. The band uses these for its own calculations.
5. Tap **Scan** and pick your band (usually "Mi Smart Band 6").
6. Tempo connects, authenticates, sets up the band and pulls the **last 7 days** of history. This can take a minute.

During pairing Tempo changes two band settings that matter for score quality: **heart rate every 1 minute** and **HR-assisted sleep detection on**. It also turns on stress monitoring and sets the time.

### Using the app

| Screen | What it shows |
| --- | --- |
| **Today** | The three dials and a one-line suggestion, e.g. "Recovery 72%, aim for strain 14–18". Tap any dial for details. The sync button pulls new data from the band. |
| **Strain detail** | Today's heart-rate curve, how strain built up during the day, and time in each heart-rate zone. |
| **Sleep detail** | Hypnogram (deep / light / REM / awake), hours slept vs hours needed, sleep debt, efficiency and deep-sleep share. |
| **Recovery detail** | Each input (stress during sleep, resting HR, sleep performance) compared with your 30-day baseline. |
| **Workout** | Live heart rate about once a second, your current zone and the strain you've gained this session. Keep the screen open. |
| **Trends** | 7-, 30- and 90-day charts for every score, resting HR and stress. |
| **Journal** | Each morning, yes/no tags for yesterday: alcohol, late meal, late caffeine, screens in bed, illness, stress. |
| **Settings** | Band info, sync status, HR max, data export, recompute scores, forget band, delete all data. |

**Syncing.** Tempo syncs when you open the app and in the background: every 3 hours on Android, and whenever iOS allows it on iPhone. The band holds several days of data, so a missed sync catches up next time.

**Your first two weeks.** Recovery shows **Calibrating** for the first 14 nights while Tempo learns your baseline. Strain and Sleep work from day one.

**A "day"** runs from when you wake up to when you next fall asleep, not midnight to midnight. Last night's sleep sets this morning's recovery, and today's strain feeds tonight's sleep need.

### How the scores work

All three scores are calculated on your phone from the band's per-minute data. Every constant is a starting point that will be tuned over time.

**Strain (0–21).** For every minute, your heart rate is placed between your resting HR and your HR max (Banister TRIMP). Harder minutes count much more than easy ones. The day's total is squeezed onto a 0–21 scale, so going from 18 to 19 takes far more work than going from 5 to 6. HR max starts at 190 and rises automatically if the band ever records higher; you can also set it in Settings.

**Sleep performance (%).** Hours slept ÷ hours needed, capped at 100 %.
Need = 7.5 h + half of your recent sleep debt (capped at 2 h) + a little extra for yesterday's strain.

**Recovery (%).** Last night compared with your own 30-day baseline:

| Input | Better when | Weight |
| --- | --- | --- |
| Stress during sleep (the band's HRV-based stress index) | Lower | 40 % |
| Resting heart rate (lowest 5-minute average while asleep) | Lower | 30 % |
| Sleep performance | Higher | 30 % |

🟢 67–100 · 🟡 34–66 · 🔴 0–33. The colour sets the strain target on the Today screen.

The Mi Band 6 doesn't expose raw beat-to-beat (HRV) data, so Recovery uses the band's stress index as a stand-in. It's a reasonable proxy, not a true HRV measurement.

### Privacy

- **No network.** Tempo makes no network calls at runtime. There are no servers, analytics or accounts.
- **On-device database.** All data lives in a local SQLite database on your phone.
- **The auth key** is kept only in secure storage. It's never written to logs, the database or exports.
- **Export.** Settings → *Export all data* writes CSV files to the app's documents folder.
- **Delete.** Settings → *Delete all data* removes the database. *Forget band and key* removes the pairing.
- **Packet logs.** The app writes a log of Bluetooth traffic to its documents folder for debugging. It contains your band's data but never the key.

### Known limitations

- **Untested on hardware.** See the status note at the top.
- **One band, one person.** No multi-user support.
- **Workout tracking needs the screen on.** On Android, leaving the Workout screen may drop the live connection.
- **Background sync on iPhone isn't guaranteed.** iOS decides when it runs. Opening the app always syncs.
- **Wrist heart rate lags** during intervals and weightlifting, so workout strain may be undercounted.
- **Firmware updates** can change the band's protocol. Avoid updating the band through Mi Fitness.

### Troubleshooting

| Problem | Try |
| --- | --- |
| Band doesn't appear in Scan | Force-stop Mi Fitness / Zepp Life, toggle Bluetooth, keep the band close. On Android allow the "Nearby devices" permission. |
| "Band rejected key" | The key is wrong or stale (the band was reset). Extract it again. |
| "No auth variant got a challenge" | Probably a protocol difference on your firmware. Send the packet log (see below). |
| Sleep dial stays empty | Sleep stage codes may not match your firmware yet. Send the packet log and an export. |
| Recovery stuck on Calibrating | Normal for the first 14 nights with sleep data. |
| Scores look wrong after an update | Settings → *Recompute all scores*. |

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
State + UI           app/lib/src/ui: Riverpod, fl_chart
```

### Repository layout

```
app/                    Flutter app
  lib/src/core/           sync, scoring service, band link, key store, background, export
  lib/src/ui/             screens and widgets
packages/
  band_ble/             Huami protocol on flutter_blue_plus (our own implementation)
  store/                Drift schema + DAOs (raw tables append-only)
  scoring/              Strain / Sleep / Recovery, pure Dart
tools/
  backtest/             CLI: run scoring over an Apple Health export
  pull_packets.sh       copy packet logs off an Android device
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

---

*Tempo is an independent personal project. It isn't affiliated with or endorsed by Xiaomi, Huami/Zepp or WHOOP. Product names are used only to describe compatibility.*
