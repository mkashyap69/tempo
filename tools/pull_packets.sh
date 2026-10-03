#!/usr/bin/env bash
# Copies BLE packet logs from a connected Android debug build into docs/packets/.
# iOS: Xcode → Window → Devices → Tempo → Download Container, then copy
# AppData/Documents/packets/*.jsonl into docs/packets/.
set -euo pipefail
cd "$(dirname "$0")/.."
adb exec-out run-as dev.tempo.tempo tar c -C app_flutter packets \
  | tar x --strip-components=1 -C docs/packets
ls -l docs/packets/*.jsonl
