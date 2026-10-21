# CLAUDE.md

Recovery, strain and sleep app built in Flutter, heading for a beta release. It reads Apple Health or Health Connect (one source per install); the Mi Band 6 over BLE is a secondary source behind You → Developer. Full plan: `PLAN.md`. Read it before starting any work.

## Non-negotiables

- Data comes read-only from Apple Health / Health Connect on the phone (the first and default source), or from the Mi Band 6 over direct BLE (hidden in You → Developer). No Gadgetbridge, Mi Fitness or vendor cloud at runtime. Never write back what was read from Health.
- **Never copy Gadgetbridge source.** It is AGPL-3.0. Read it to understand the protocol, then write our own Dart implementation. Don't paste its code or translate it line by line.
- Health data leaves the phone only end-to-end encrypted; the server never sees plaintext health data, the sync key or the band's auth key (the one exception: a feedback report the user reads and chooses to send). Allowed network calls: sign-in, billing, encrypted sync, opt-in diagnostics, user-sent feedback, all on GCP and listed in `docs/network.md`; any other call needs a line in `docs/decisions.md` first. See `docs/research/Backend plan.md`.
- The auth key lives only in `flutter_secure_storage`. Never log it, commit it or hardcode it. For local dev, read it from an untracked `.env` file.
- Raw sample tables are append-only (`health_records` too: deletions are tombstones). Scores are always derived and carry an `algo_version` and a `source`.
- `packages/scoring` is pure Dart with no Flutter or BLE imports. Every formula has unit tests. `packages/sync` follows the same rule, with known-answer tests for its crypto.

## Layout

```
/app                  Flutter app (UI, Riverpod)
/packages/band_ble    Huami protocol on flutter_blue_plus
/packages/store       Drift schema + DAOs
/packages/scoring     Strain / Sleep / Recovery
/packages/health_source  Health records → minutes (pure Dart)
/tools/backtest       CLI over an Apple Health export
/packages/sync        Encrypted sync format, crypto, merge (pure Dart; planned)
/backend              Cloud Run api and workers, TypeScript (planned)
/infra                Terraform for GCP (planned)
```

## Working style

- Work phase by phase as in PLAN.md → Milestones. Don't start a phase until the previous gate passes.
- Never guess BLE UUIDs, opcodes or byte layouts. Mark each as `// TODO(verify)` until it's confirmed against a packet log from the real band, and keep the logs in `docs/packets/`.
- Protocol parsers get golden tests built from captured packets.
- Health plugin behaviour (types, units, ids, failures) is `TODO(verify)` until seen on a real phone, like BLE details.
- Keep `docs/decisions.md` up to date. Add one line per decision, with the date.

## Current phase

Tempo Coach C0–C4, P1 (goals and progression) and P2 (Goal screen, tune-ups, next goal) and N1 (tabs: Today, Coach, Trends, Longevity, Profile; Coach split into Today / Week / Goal) and H0–H4 (Apple Health / Health Connect as a data source, see `docs/research/Health connectors plan.md`) and E1 (everyday metrics: sleep regularity, social jetlag, body signals, brisk minutes, longest still stretch, heart-rate recovery) and C7 (today's picks: a run, a strength session and a game to choose from) and T1 (teardown next steps: Journal v2 and impact engine, Tempo Age v2, strength log and progression, algo 9; see `docs/research/Competitor teardown and next steps.md`) and F1 (user flow: one voice, Today as the day's story, tabs Today · Plan · (+) · Progress · You, Week in review, today's insight; see `docs/research/User flow and journey.md`) built (see PLAN.md → Milestones and `docs/research/Tempo Coach adaptive plan.md`). Gates now: C1's 7-day status check, C4's 14-day notification field diary on a real phone, P1/P2's 4-week block check, H2/H3's 7 days on an iPhone + watch and an Android phone + watch with no band, T1's backtest, 4-week lifting and 14-day journal checks, and F1's task tests and 14-day insight diary. C5/C6 deferred. Next: the beta, phases B0–B6 in `docs/research/Beta release plan.md` with the GCP backend phases G0–G4 and S1 in `docs/research/Backend plan.md`, starting with B0/G0 and the open decisions G-O1…G-O6.
