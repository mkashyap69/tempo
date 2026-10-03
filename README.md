# Tempo

Personal recovery/strain app for the Mi Band 6. See `PLAN.md` and `CLAUDE.md`.

## Phase 0 spike: run it

1. Make sure Mi Fitness / Zepp Life is force-stopped (only one app can hold the band).
2. `cp .env.example .env` and fill in `BAND_AUTH_KEY` (32 hex digits).
3. `cd app && flutter run --dart-define-from-file=../.env` (debug build, phone plugged in).
   Or skip the `.env` and paste the key in the app.
4. Tap **Scan**, pick the band, wait for "Authenticated", then live BPM.
5. `tools/pull_packets.sh` to copy the packet log into `docs/packets/`, review it, commit it.

## Tests

```
flutter pub get
flutter analyze
(cd packages/band_ble && flutter test)
```
