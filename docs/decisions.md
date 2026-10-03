# Decisions

- 2026-10-03 · Monorepo as a Dart pub workspace (root `pubspec.yaml`), one lockfile for app + packages.
- 2026-10-03 · BLE: flutter_blue_plus 2.x with `License.nonprofit` (personal, non-commercial use).
- 2026-10-03 · AES-128 for the auth handshake via `pointycastle` (MIT); tested against the FIPS-197 vector.
- 2026-10-03 · Auth tries the "modern" (0x82/0x83) variant first, falls back to legacy (0x02/0x03). Revisit once firmware → variant is confirmed from captures.
- 2026-10-03 · Dev key path: debug builds run with `--dart-define-from-file=../.env` seed secure storage once. This compiles the key into the *debug* binary only; release builds ignore it and take a pasted key. Never distribute a debug build.
- 2026-10-03 · Packet logs are JSONL written in the app's documents dir and pulled into `docs/packets/` with `tools/pull_packets.sh`. The encrypted auth reply is redacted.
- 2026-10-03 · Owner overrode the phase gates: Phases 0–4 built back to back, tested on hardware at the end. Every protocol detail stays `TODO(verify)` until captures confirm it.
- 2026-10-03 · Strain k = 120 as a starting value. Backtest on synthetic data shows resting-level HR alone accumulates ~12 strain/day; calibrate k (or a TRIMP floor) on the real Apple Health export.
- 2026-10-03 · Recovery renormalises weights over available inputs (e.g. backtest has no stress data).
- 2026-10-03 · Sleep session = sleep runs merged across ≤30 min wake gaps, ≥60 min asleep; main night = longest ending in (D-1 14:00, D 14:00].
- 2026-10-03 · Raw-table append-only enforced with SQL triggers. Because parsers are unverified, Settings has "Delete all data" (drops the DB file) for resetting after a bad parse; it is not an edit path.
- 2026-10-03 · History fetch never sends the post-transfer ack until verified: on some firmware it deletes data from the band.
- 2026-10-03 · First sync reaches back 7 days. PAI is not fetched (trends-only, no table yet).
- 2026-10-03 · Background: WorkManager every 3 h on Android; iOS BGAppRefresh (tempo.sync) + bluetooth-central + CoreBluetooth state restoration, plus sync on open/resume.
- 2026-10-03 · Keychain accessibility = after first unlock (this device only) so background sync can read the key while locked.
- 2026-10-03 · Workout foreground service on Android deferred; live workout requires the screen to stay open.
