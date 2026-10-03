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
| 4 | Today screen | Strain and Sleep show values; Recovery says Calibrating | screenshot + Settings → Export CSVs |
| 5 | Sleep detail | Bed/wake times match Mi Fitness within ~15 min | hypnogram screenshot + minute_samples.csv |
| 6 | Workout button | Live BPM within ~5 s, updates ~1/s, keeps going > 1 min | log |
| 7 | Background | Close app 3+ h; Settings → Last sync advanced | `adb logcat \| grep -i workmanager` |
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
