# TempoWidget (WidgetKit)

Sources for the iOS home-screen widgets (design board 12). Flutter writes the
values into the `group.dev.tempo.tempo` app group via `home_widget`; this
extension only reads them.

The extension target is not in `Runner.xcodeproj` yet, because a target can't
be added reliably without Xcode. One-time setup on a Mac:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. File › New › Target › **Widget Extension**. Product name `TempoWidget`,
   untick "Include Live Activity" and "Include Configuration App Intent".
   When asked, don't activate the new scheme.
3. Delete the Swift files Xcode generated in the new group, then add the files
   in this folder to the `TempoWidget` target (`TempoWidget.swift`,
   `Info.plist`, `TempoWidget.entitlements`). Set the target's
   *Code Signing Entitlements* to `TempoWidget/TempoWidget.entitlements` and
   *Info.plist File* to `TempoWidget/Info.plist`.
4. Signing & Capabilities: add **App Groups** with `group.dev.tempo.tempo` on
   both `Runner` (already in `Runner/Runner.entitlements`) and `TempoWidget`.
5. Set the extension's deployment target to iOS 17 (it uses
   `containerBackground`).

Android needs no extra step: `TempoSmallWidget` / `TempoMediumWidget` are
registered in `AndroidManifest.xml`.
