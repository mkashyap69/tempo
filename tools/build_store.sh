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
# Backend settings (lib/src/account/backend_config.dart) from an untracked
# file: TEMPO_API_URL=…, TEMPO_FIREBASE_PROJECT=…, one per line. Without it
# the build has no account or purchases. Covered by .gitignore (.env.*).
store_env="${TEMPO_STORE_ENV:-../.env.store}"
if [ -f "$store_env" ]; then
  defines+=("--dart-define-from-file=$store_env")
else
  echo "warning: $store_env missing; building without the account service" >&2
fi
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
