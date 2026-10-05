# CLAUDE.md

Personal Whoop-style app for the Mi Band 6, built in Flutter. Full plan: `PLAN.md`. Read it before starting any work.

## Non-negotiables

- Direct BLE to the Mi Band 6. No Gadgetbridge, Mi Fitness or vendor cloud at runtime.
- **Never copy Gadgetbridge source.** It is AGPL-3.0. Read it to understand the protocol, then write our own Dart implementation. Don't paste its code or translate it line by line.
- Fully on-device. No backend or network calls, apart from package fetches at build time.
- The auth key lives only in `flutter_secure_storage`. Never log it, commit it or hardcode it. For local dev, read it from an untracked `.env` file.
- Raw sample tables are append-only. Scores are always derived and carry an `algo_version`.
- `packages/scoring` is pure Dart with no Flutter or BLE imports. Every formula has unit tests.

## Layout

```
/app                  Flutter app (UI, Riverpod)
/packages/band_ble    Huami protocol on flutter_blue_plus
/packages/store       Drift schema + DAOs
/packages/scoring     Strain / Sleep / Recovery
/tools/backtest       CLI over an Apple Health export
```

## Working style

- Work phase by phase as in PLAN.md → Milestones. Don't start a phase until the previous gate passes.
- Never guess BLE UUIDs, opcodes or byte layouts. Mark each as `// TODO(verify)` until it's confirmed against a packet log from the real band, and keep the logs in `docs/packets/`.
- Protocol parsers get golden tests built from captured packets.
- Keep `docs/decisions.md` up to date. Add one line per decision, with the date.

## Current phase

Tempo Coach C0–C4 built (see PLAN.md → Milestones and `reports/Tempo Coach adaptive plan.md`). Gates now: C1's 7-day status check and C4's 14-day notification field diary on a real phone. C5/C6 deferred.
