# Decisions

- 2026-10-03 · Monorepo as a Dart pub workspace (root `pubspec.yaml`), one lockfile for app + packages.
- 2026-10-03 · BLE: flutter_blue_plus 2.x with `License.nonprofit` (personal, non-commercial use).
- 2026-10-03 · AES-128 for the auth handshake via `pointycastle` (MIT); tested against the FIPS-197 vector.
- 2026-10-03 · Auth tries the "modern" (0x82/0x83) variant first, falls back to legacy (0x02/0x03). Revisit once firmware → variant is confirmed from captures.
- 2026-10-03 · Dev key path: debug builds run with `--dart-define-from-file=../.env` seed secure storage once. This compiles the key into the *debug* binary only; release builds ignore it and take a pasted key. Never distribute a debug build.
- 2026-10-03 · Packet logs are JSONL written in the app's documents dir and pulled into `docs/packets/` with `tools/pull_packets.sh`. The encrypted auth reply is redacted.
