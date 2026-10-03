# Packet captures

Raw BLE logs from the real band. They are the only source of truth for UUIDs,
opcodes and byte layouts: anything in `packages/band_ble` marked
`// TODO(verify)` stays so until a file here confirms it.

## Format

One JSON object per line (`<os>-<utc timestamp>.jsonl`):

| key | meaning |
| --- | --- |
| `ts` | UTC timestamp |
| `dir` | `tx` (app → band), `rx` (band → app), `info` (GATT discovery, status) |
| `char` | characteristic UUID |
| `hex` | payload bytes. Missing on redacted writes (the encrypted auth reply) |
| `note` | free text |

The auth key is never written. Check a file before committing anyway.

## Getting them

Android: `tools/pull_packets.sh` with the phone on adb (debug build).
iOS: see the comment at the top of that script.
