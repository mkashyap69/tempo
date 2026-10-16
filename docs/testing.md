# End-to-end test plan

Nothing here has run against the band yet. Work top to bottom; each step's
packet log goes into `docs/packets/` (`tools/pull_packets.sh`).

## Before you start
- Mi Fitness / Zepp Life force-stopped on every phone near the band.
- `.env` with `BAND_AUTH_KEY` (or paste the key in the app).
- `flutter pub get` at the repo root.

## Android: `cd app && flutter run --dart-define-from-file=../.env`

| # | Step | Pass when | If it fails, send me |
| --- | --- | --- | --- |
| 1 | Pair: scan, tap band | "Authenticated (modern/legacy)" | status lines + packet log |
| 2 | Pairing writes settings | "Band settings written." | which settings failed + log |
| 3 | First sync | "Synced: activity: N…" with N ≈ minutes in last 7 days | log (fetch replies, byte count, gaps) |
| 4 | Today screen | Strain and Sleep show values; Recovery says Calibrating | screenshot + Profile → Export (CSV) |
| 5 | Sleep detail | Bed/wake times match Mi Fitness within ~15 min | hypnogram screenshot + minute_samples.csv |
| 6 | Workout button | Live BPM within ~5 s, updates ~1/s, keeps going > 1 min | log |
| 7 | Background | Close app 3+ h; Profile → Last sync advanced; Data health → Sync log has a new line | `adb logcat \| grep -i workmanager` |
| 8 | 7-day check (Phase 1 gate) | Daily steps / sleep totals match Mi Fitness | export CSVs |

## iOS (Mac + Xcode): `cd app && flutter run --dart-define-from-file=../.env`
Same steps 1–6. Accept the system pairing prompt if it appears. Step 7:
background runs are at iOS's discretion; check that open/resume syncs.
Logs: Xcode → Devices → Download Container → `AppData/Documents/packets/`.

## Scoring backtest (no band needed)
```
cd tools/backtest
dart run bin/backtest.dart ~/export.xml > scores.csv
```
Check that hard training days land near 18–19 strain; if not, tune `k`
in `packages/scoring/lib/src/strain.dart` and bump `algoVersion`.

## Most likely failure points
1. Auth opcodes (modern vs legacy) — the log shows which got a reply.
2. Fetch type codes and activity record size (4 bytes assumed).
3. Sleep kind codes (`sleepKinds` in band_ble/lib/src/fetch.dart) — if Sleep is empty, this is why.
4. Stress / SpO2 layouts — wrong values here only affect Recovery.

## Health sources (no band needed)

Neither Xcode nor the Android SDK is in the dev container, so everything
below is TODO(verify) on a phone. Send the Sync log (Profile → Sync health)
and Profile → Export (JSON) when something's off.

| # | Step | Pass when |
| --- | --- | --- |
| H1 | Onboarding → "Where does your data come from?" → Apple Health / Health Connect → Connect | The system sheet lists heart rate, HRV, resting HR, sleep, steps, SpO₂, workouts (Android also distance, calories, past data, background) |
| H2 | Today after the first read | Sync pill shows progress, then "Imported N records"; Sync log says "… imported · N heart-rate readings, N sleep records, N workouts" |
| H3 | Sleep, last night | Bed/wake times and stages match the Health app (Apple) / the watch's app (Health Connect) within a few minutes |
| H4 | Recovery | Calibrating if fewer than 14 nights in the last 90 days, else a score with "HRV, overnight" (Apple: SDNN; Android: "HRV (RMSSD)" if the watch writes it) |
| H5 | Steps on Today vs the Health app's total | Within ~5 % (Tempo takes the busier of phone and watch per minute; Health deduplicates its own way) |
| H6 | A workout logged on the watch | Appears in Workouts as a confirmed workout with HR and strain; not duplicated by an auto-detected one |
| H7 | Delete that workout in Health, then pull to refresh | It disappears from Workouts (tombstoned; the raw row stays) |
| H8 | Start a workout in Tempo | Timer only ("HR from Health later"); after the watch syncs and Tempo reads, it shows HR and strain |
| H9 | iPhone locked overnight | No banner in the morning; the open reads fine. Sync log may show "could not be read (phone locked?)" lines from the night |
| H10 | Android background (close Tempo 3+ h) | A new "Health Connect · …" line in the Sync log without opening Tempo; if "background reads not allowed", allow it in Health Connect → Tempo |
| H11 | Profile → Data source → Mi Band 6 → back to Health | No scores lost; Recovery recalibrates only if the new source has under 14 nights |

## Everyday metrics

| # | Check | Pass when |
| --- | --- | --- |
| E1 | Sleep → Rhythm after 7 days | Regularity is high on a steady week and drops after a late weekend; social jetlag matches your weekend mid-sleep shift within ~15 min |
| E2 | Recovery → Body signals | Each row shows last night against "usual"; after a drink or a late meal at most one row is flagged; Today shows a card only when two or more are |
| E3 | Strain → Movement today | Brisk minutes ≈ minutes of purposeful walking; longest still stretch matches a long desk session on the day timeline; "needs heart rate" on a phone-only Health source |
| E4 | Activity after a hard run | Heart-rate recovery appears when you stood or walked easy for 2 min after stopping; none for an easy session |
| E5 | Health: breathing rate | After the update, one permission sheet asks for breathing rate; Recovery shows it after 14 nights (90 days are backfilled) |

## Today's picks

| # | Check | Pass when |
| --- | --- | --- |
| K1 | Profile → Workouts → Games you play: pick two | Coach → Today shows a run, a strength session and one of your games; one says "Tempo's pick" |
| K2 | The day after a hard session | No hard run is offered; strength is upper body if the hard day was a run |
| K3 | Evening, under 4 h to bed | Nothing hard; under 1 h, only easy options |
| K4 | Open a pick → Make it today's plan | Today's card shows it; the workout screen lists "What to do" (intervals, exercises or format) |
| K5 | Start now on an interval run | The live workout follows the pick's segments |
