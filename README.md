# Tempo

Personal recovery/strain app for the Mi Band 6. See `PLAN.md` and `CLAUDE.md`.

## Status

Phases 0–4 are implemented but **not yet run on hardware**. All BLE details
are `TODO(verify)`. Follow `docs/testing.md`.

## Run

1. Force-stop Mi Fitness / Zepp Life (only one app can hold the band).
2. `cp .env.example .env` and fill in `BAND_AUTH_KEY` (32 hex digits), or paste it in the app.
3. `flutter pub get`, then `cd app && flutter run --dart-define-from-file=../.env`.
4. Pair → first sync → Today. Pull packet logs with `tools/pull_packets.sh`.

## Tests

```
flutter pub get
flutter analyze
(cd packages/scoring && dart test)
(cd packages/store && dart test)
(cd packages/band_ble && flutter test)
(cd tools/backtest && dart test)
(cd app && flutter test)
```

Regenerate the Drift code after schema changes: `cd packages/store && dart run build_runner build`.
