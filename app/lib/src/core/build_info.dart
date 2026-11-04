/// What kind of build this is, fixed at compile time.
///
/// App Store and Play builds pass `--dart-define=TEMPO_STORE=true`
/// (`tools/build_store.sh`). A store build leaves out what the stores' review
/// would question in a health app that doesn't sell a band (launch plan L-O5):
/// the Mi Band (Bluetooth, its background mode and foreground-service type,
/// sleep export of band nights), the battery-optimisation exemption prompt and
/// exact alarms. The Android release manifest and the iOS Info.plist are
/// trimmed to match (`android/app/src/store/AndroidManifest.xml`,
/// `ios/scripts/store_info_plist.sh`).
abstract final class BuildInfo {
  /// True in App Store and Play builds.
  static const store = bool.fromEnvironment('TEMPO_STORE');

  /// The Mi Band path (You → Developer) exists in this build.
  static const bandAllowed = !store;

  /// Android's "Precise reminders" (SCHEDULE_EXACT_ALARM) and the direct
  /// battery-optimisation request (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) are
  /// declared only outside store builds; Play restricts both.
  static const restrictedAndroidPermissions = !store;
}
