# CLAUDE.md

Personal Whoop-style app for the Mi Band 6, built in Flutter. It also runs without a band, reading Apple Health or Health Connect (one source per install). Full plan: `PLAN.md`. Read it before starting any work.

## Non-negotiables

- Data comes from the Mi Band 6 over direct BLE, or read-only from Apple Health / Health Connect on the phone. No Gadgetbridge, Mi Fitness or vendor cloud at runtime. Never write back what was read from Health.
- **Never copy Gadgetbridge source.** It is AGPL-3.0. Read it to understand the protocol, then write our own Dart implementation. Don't paste its code or translate it line by line.
- Fully on-device. No backend or network calls, apart from package fetches at build time.
- The auth key lives only in `flutter_secure_storage`. Never log it, commit it or hardcode it. For local dev, read it from an untracked `.env` file.
- Raw sample tables are append-only (`health_records` too: deletions are tombstones). Scores are always derived and carry an `algo_version` and a `source`.
- `packages/scoring` is pure Dart with no Flutter or BLE imports. Every formula has unit tests.

## Layout

```
/app                  Flutter app (UI, Riverpod)
/packages/band_ble    Huami protocol on flutter_blue_plus
/packages/store       Drift schema + DAOs
/packages/scoring     Strain / Sleep / Recovery
/packages/health_source  Health records → minutes (pure Dart)
/tools/backtest       CLI over an Apple Health export
```

## Working style

- Work phase by phase as in PLAN.md → Milestones. Don't start a phase until the previous gate passes.
- Never guess BLE UUIDs, opcodes or byte layouts. Mark each as `// TODO(verify)` until it's confirmed against a packet log from the real band, and keep the logs in `docs/packets/`.
- Protocol parsers get golden tests built from captured packets.
- Health plugin behaviour (types, units, ids, failures) is `TODO(verify)` until seen on a real phone, like BLE details.
- Keep `docs/decisions.md` up to date. Add one line per decision, with the date.

## Current phase

Tempo Coach C0–C4, P1 (goals and progression) and P2 (Goal screen, tune-ups, next goal) and N1 (tabs: Today, Coach, Trends, Longevity, Profile; Coach split into Today / Week / Goal) and H0–H4 (Apple Health / Health Connect as a data source, see `docs/research/Health connectors plan.md`) built (see PLAN.md → Milestones and `docs/research/Tempo Coach adaptive plan.md`). Gates now: C1's 7-day status check, C4's 14-day notification field diary on a real phone, P1/P2's 4-week block check, and H2/H3's 7 days on an iPhone + watch and an Android phone + watch with no band. C5/C6 deferred.
