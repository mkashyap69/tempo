#!/usr/bin/env bash
# Builds what goes to the App Store and Google Play (launch plan L1).
#
#   tools/build_store.sh android     # app/build/app/outputs/bundle/release/app-release.aab
#   tools/build_store.sh ios         # app/build/ios/ipa/*.ipa (needs a Mac, Xcode, signing)
#
# A store build sets TEMPO_STORE=true (lib/src/core/build_info.dart): no Mi
# Band, no battery-optimisation request, no exact alarms; the Android release
# manifest and the iOS Info.plist are trimmed to match. It never reads ../.env,
# so no band key is compiled in. Android signs with android/key.properties when
# present (see android/app/build.gradle.kts).
set -euo pipefail
cd "$(dirname "$0")/../app"
target="${1:-}"
defines=(--dart-define=TEMPO_STORE=true)
case "$target" in
  android)
    [ -f android/key.properties ] || echo "warning: android/key.properties missing; signing with the debug key (not uploadable)" >&2
    flutter build appbundle --release "${defines[@]}"
    ;;
  ios)
    flutter build ipa --release "${defines[@]}"
    ;;
  *)
    echo "usage: $0 android|ios" >&2
    exit 2
    ;;
esac
