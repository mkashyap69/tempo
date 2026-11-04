#!/bin/sh
# Xcode build phase "Store Info.plist" (Runner). In a store build
# (--dart-define=TEMPO_STORE=true, see lib/src/core/build_info.dart) it
# removes the Mi Band's Bluetooth background mode from the built Info.plist:
# App Review questions background modes it can't exercise, and the band is not
# in store builds (launch plan L-O5). NSBluetoothAlwaysUsageDescription stays,
# because flutter_blue_plus still links CoreBluetooth and an upload without
# the string is rejected.
set -e
store=false
old_ifs=$IFS
IFS=','
for d in ${DART_DEFINES:-}; do
  v=$(printf '%s' "$d" | base64 --decode 2>/dev/null || true)
  if [ "$v" = "TEMPO_STORE=true" ]; then store=true; fi
done
IFS=$old_ifs
[ "$store" = true ] || exit 0

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
buddy=/usr/libexec/PlistBuddy
i=0
while v=$("$buddy" -c "Print :UIBackgroundModes:$i" "$plist" 2>/dev/null); do
  if [ "$v" = "bluetooth-central" ]; then
    "$buddy" -c "Delete :UIBackgroundModes:$i" "$plist"
    echo "Store build: removed bluetooth-central from UIBackgroundModes"
    exit 0
  fi
  i=$((i + 1))
done
