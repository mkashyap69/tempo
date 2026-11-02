# TempoWidget (WidgetKit + Live Activity)

The widget extension: home-screen widgets (Tempo small/medium, Session,
Day), lock-screen widgets, and the live workout's Live Activity (lock screen
and Dynamic Island). Flutter writes widget values into the
`group.dev.tempo.tempo` app group via `home_widget`; the Live Activity is
started and updated by the app over `tempo/live_activity`
(`Runner/LiveActivityChannel.swift`).

The `TempoWidget` target is in `Runner.xcodeproj` (added 2026-11-02 with the
`xcodeproj` gem). Files:

- `TempoWidget.swift` — widgets and the `@main` bundle
- `LiveWorkoutActivity.swift` — the Live Activity's views
- `../Shared/TempoWorkoutAttributes.swift` — the activity's attributes and
  state; compiled into both Runner and TempoWidget
- `Info.plist`, `TempoWidget.entitlements` — the extension's plist (merged
  with generated keys) and its App Group

On a Mac, once:

1. Open `ios/Runner.xcworkspace`, select the `TempoWidget` target, Signing &
   Capabilities: pick your team (same as Runner). App Groups should show
   `group.dev.tempo.tempo` on both targets.
2. Build and run Runner. If Xcode reports a build cycle, check that
   "Embed Foundation Extensions" sits above "Thin Binary" in Runner's
   Build Phases.

Widget links must carry `?homeWidget` (e.g. `tempo://strain?homeWidget`):
home_widget ignores any other URL.

Android needs no extra step: the providers are in `AndroidManifest.xml`.
