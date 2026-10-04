# Tempo app

The Flutter app. See the repository [README](../README.md) for setup, and
[`docs/design.md`](../docs/design.md) for where each design board lives in
`lib/src`.

```
lib/src/core      sync, scoring, coach plan, band link, notifications, widgets, battery,
                  pause, smart alarm, Health export, foreground service, restore
lib/src/state     Riverpod providers, live workout session
lib/src/design    tokens, type, icons, components, charts
lib/src/screens   screens
```

## Platform setup notes

- **iOS HealthKit.** `Runner.entitlements` carries the HealthKit entitlement for the opt-in Health export. The signing team's App ID needs the HealthKit capability (Xcode → Signing & Capabilities).
- **Android Health Connect** needs minSdk 26 and a `FlutterFragmentActivity`; both are set. Only the write permissions for exercise and sleep are declared.
- **Android foreground service.** `flutter_foreground_task`'s service is declared with type `connectedDevice` and only runs during a live workout.
- **Widget taps** use the `tempo://` scheme (`CFBundleURLTypes` on iOS, the home_widget launch intent filter on Android).
