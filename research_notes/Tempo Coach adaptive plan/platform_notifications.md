# On-device scheduling and local notifications for a Flutter app (Android + iOS, no push server)

Research date: 2026-10-05. Scope: scheduling coaching notifications at set times, re-evaluating in the background (e.g. after a BLE sync with a Mi Band 6) and rescheduling them, and actionable notifications (Done / Snooze / Move to evening).

Note on sources: support.google.com (Play policy) was blocked by the egress proxy, and several developer.apple.com pages render client-side and returned no content. Where that happened, the claim is taken from a secondary source and flagged, or it is listed under Gaps.

## Android: exact vs inexact alarms, permissions and Play policy

### Takeaway
A coaching app doesn't qualify for `USE_EXACT_ALARM`, which is limited to alarm-clock, timer and calendar apps. `SCHEDULE_EXACT_ALARM` is denied by default on Android 14+ and the user has to grant it in Settings. For coaching nudges, plan on inexact `setAndAllowWhileIdle` or `setWindow` (minimum 10-minute window) and treat exact timing as an opt-in upgrade.

### Cited Findings
- `USE_EXACT_ALARM` is a normal permission, pre-granted at install, and meant "for calendar and alarm clock apps only". It "must qualify based on Google Play policy". All other apps use `SCHEDULE_EXACT_ALARM`, which is "denied by default on Android 14+ for newly installed apps", and must call `canScheduleExactAlarms()` before using it — [Android 14 behaviour change: schedule exact alarms](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
- `SCHEDULE_EXACT_ALARM` is pre-granted only to platform-signed or privileged apps, apps on the power allowlist (via `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) and `SYSTEM_WELLBEING` role holders — [Android 14 exact alarms](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms). Inference: if the user exempts the app from battery optimisation (Tempo already asks for this for its BLE foreground service), the app may also get exact alarms. Verify this on a real device.
- Google's recommended alternatives for non-alarm apps: `WorkManager` (15-minute minimum), `setAndAllowWhileIdle()` for "alarm at approximate time in idle state", `set()` for "user action after specific time", and `setWindow()` (10-minute minimum window) for "user action within time window" — [Android 14 exact alarms](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
- Play policy, from a secondary summary because the primary page was blocked: apps should request `USE_EXACT_ALARM` "only if their core functionality is of alarm or calendar". Apps that request it are reviewed, and apps that don't qualify "will be disallowed from publishing on Google Play" — [Play Console Help: Permissions and APIs that access sensitive information](https://support.google.com/googleplay/android-developer/answer/16558241) (via search snippet); [Orange OMA summary](https://orangeoma.zendesk.com/hc/en-us/articles/9110068699548-Google-Play-policy-on-use-of-Exact-Alarm-API)
- Inexact semantics on Android 12+: `set()` is delivered "within one hour of trigger time" unless battery-saving restrictions apply. `setWindow()` never fires early, and windows shorter than 600,000 ms (10 minutes) are clipped to 10 minutes — [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
- Exact APIs: `setExact()` respects battery saving. `setExactAndAllowWhileIdle()` fires during Doze. `setAlarmClock()` is "never delayed" and wakes the device. `OnAlarmListener`-based exact alarms don't need `SCHEDULE_EXACT_ALARM`, but they only work while the process is alive. Exact alarms "aren't affected by foreground service launch restrictions" — [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
- Apps should listen for `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` and reschedule as they would on boot. On Android 14, a backup/restore to a new device leaves the permission denied — [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
- "Alarms are cleared on device shutdown/reboot." Apps need `RECEIVE_BOOT_COMPLETED` and a boot receiver to reschedule — [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)

### Inferences
- For "Move to evening" or "Snooze 30 min", inexact `setAndAllowWhileIdle` is accurate enough: it usually lands within minutes, and the one-hour bound for `set()` is the worst case. For a time-anchored nudge such as "wind down at 22:30", use exact timing when `canScheduleExactAlarms()` is true and fall back to inexact otherwise. Don't declare `USE_EXACT_ALARM`.

### Gaps
- I couldn't read the primary Play policy text, and I couldn't confirm whether the 2025–2026 versions add "health/fitness reminders" as an allowed case. The secondary sources say no.
- I found no primary source on Android 16-specific exact-alarm changes. The power page mentions only JobScheduler quota changes in Android 16 (see the next section).

## Android: Doze, App Standby buckets, WorkManager

### Takeaway
While-idle alarms are capped at 7 per hour in Doze, and alarm counts are capped per standby bucket: 10/h in Working set, 2/h in Frequent, 1/h in Rare and 1/day in Restricted. A few coaching notifications a day fit inside every bucket except Restricted, which an app reaches after 8 days without use on Android 13+. WorkManager periodic work has a 15-minute minimum and the system defers it heavily, so don't rely on it for timing.

### Cited Findings
- Bucket limits for regular jobs / expedited jobs / alarms: Active: 20 min per 60 min / 30 min per 24 h / no limit. Working set: 10 min per 4 h / 15 min per 24 h / 10 alarms per hour. Frequent: 10 min per 12 h / 10 min per 24 h / 2 per hour. Rare: 10 min per 24 h / 10 min per 24 h / 1 per hour, network disabled. Restricted: once a day for up to 10 min / 5 min per 24 h / "One alarm per day, either an exact alarm or an inexact alarm", network disabled — [Power management resource limits](https://developer.android.com/topic/performance/power/power-details)
- In Doze, regular alarms are deferred to the maintenance window, and while-idle alarms are "Limited to 7 per hour" — [Power management resource limits](https://developer.android.com/topic/performance/power/power-details)
- Android 16 changed JobScheduler quota behaviour based on standby bucket, top state and foreground-service status. The values "are not a guarantee" — [Power management resource limits](https://developer.android.com/topic/performance/power/power-details)
- The Restricted bucket applies when the user hasn't interacted with the app for 8 days (Android 13) or 45 days (Android 12/12L), or when the app sends excessive broadcasts or bindings — [App Standby Buckets](https://developer.android.com/topic/performance/appstandby)
- WorkManager periodic work has a 15-minute minimum interval — [Android 14 exact alarms](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms); [workmanager on pub.dev](https://pub.dev/packages/workmanager)

### Inferences
- An app with an active BLE foreground service, as Tempo has, is probably treated as Active or close to it while that service runs. That makes a daily schedule of 3–8 notifications plus a few snoozes safe.
- Use WorkManager only as a safety net, for example "every few hours, if no sync happened, rebuild today's schedule". It shouldn't be the delivery mechanism.

### Gaps
- I didn't verify how an active `connectedDevice` foreground service affects bucket placement.

## Android: foreground service types, POST_NOTIFICATIONS, channels, boot, OEMs

### Takeaway
A BLE sync service should use the `connectedDevice` FGS type (`FOREGROUND_SERVICE_CONNECTED_DEVICE` plus a granted `BLUETOOTH_CONNECT`). The `health` type requires body-sensor or Health Connect permissions, which a BLE band app doesn't naturally hold. `POST_NOTIFICATIONS` is a runtime permission from Android 13, and notifications are off by default on new installs. Xiaomi MIUI/HyperOS needs the user to enable Autostart and "No restrictions" battery mode.

### Cited Findings
- `connectedDevice`: needs `FOREGROUND_SERVICE_CONNECTED_DEVICE`, plus at least one of: a granted runtime `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_SCAN` or `UWB_RANGING` permission; a declared `CHANGE_NETWORK_STATE`, `CHANGE_WIFI_STATE`, NFC or similar manifest permission; or a USB permission — [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- `health`: needs `FOREGROUND_SERVICE_HEALTH`, plus `HIGH_SAMPLING_RATE_SENSORS` in the manifest or a granted `BODY_SENSORS` (API ≤35), `READ_HEART_RATE`, `READ_SKIN_TEMPERATURE`, `READ_OXYGEN_SATURATION` or `ACTIVITY_RECOGNITION`. Body-sensor permissions are while-in-use, so starting this service from the background needs `BODY_SENSORS_BACKGROUND` (API 33–35) or `READ_HEALTH_DATA_IN_BACKGROUND` (API 36+). It's meant for "long-running use cases to support apps in the fitness category such as exercise trackers" — [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- `dataSync` is limited to 6 hours in every 24 on Android 15+, and apps targeting 15+ "are not allowed to launch a data sync foreground service from a BOOT_COMPLETED broadcast receiver". `shortService` has a limit of about 3 minutes and calls `onTimeout()` — [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- `POST_NOTIFICATIONS`: a runtime permission since Android 13, with notifications "off by default" on new installs. If it's denied, FGS notifications appear only in the Task Manager. Google recommends asking in context. Use `areNotificationsEnabled()` to check — [Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- Xiaomi MIUI/HyperOS are "among the most aggressive" at killing background apps. Users need to turn on Autostart (Settings > Apps > app > Background autostart) and set battery saver to "No restrictions" — [dontkillmyapp: Xiaomi](https://dontkillmyapp.com/xiaomi); [DEV: Surviving Android battery killers](https://dev.to/szymonwalczak/surviving-android-battery-killers-in-capacitor-apps-4im7). Autostart is off by default, and apps need it to run after boot — same DEV source.
- The flutter_local_notifications README warns that OEMs such as Xiaomi and Huawei can block scheduled notifications, and that Samsung caps AlarmManager at 500 alarms — [flutter_local_notifications README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)

### Inferences
- Channels: create separate channels, for example "Coaching nudges" (default importance), "Bedtime / wind-down" (high) and "Sync status" (low, for the FGS), so the user can mute each one. Importance is fixed once a channel is created, so changing it means creating a new channel ID. This comes from Android API knowledge; I didn't fetch a source for it this session.
- Boot: let the plugin's `ScheduledNotificationBootReceiver` reschedule. Don't start a `dataSync` FGS from boot. Starting `connectedDevice` from boot isn't covered by the Android 15 list I saw, but I haven't verified that (see Gaps).

### Gaps
- I didn't verify the full list of FGS types that Android 15 blocks from `BOOT_COMPLETED`. The page I fetched only spelled out `dataSync` and `shortService`. I also didn't fetch the general background-start exemptions for Android 14.
- I didn't fetch a primary source on notification-channel importance.

## iOS: UNUserNotificationCenter limits, triggers, interruption levels, provisional auth

### Takeaway
iOS keeps only the 64 soonest-firing pending local notifications per app, and a repeating request counts as one. Use `.active`, which needs no entitlement, for normal nudges and `.passive` for low-value ones. `.timeSensitive` needs the Time Sensitive Notifications entitlement. Provisional authorization lets the app skip the prompt and deliver quietly to Notification Center.

### Cited Findings
- "The system keeps the soonest-firing 64 notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest" — [Apple Developer Forums 811171](https://developer.apple.com/forums/thread/811171), quoting the `UNNotificationRequest` docs; [flutter_local_notifications issue #2312](https://github.com/MaikuB/flutter_local_notifications/issues/2312). The plugin README puts it as "iOS will only keep the 64 notifications that were last set" — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md). Note the conflict: Apple says "soonest-firing", the plugin README says "last set". Trust Apple's wording.
- Interruption levels: `passive` is silent and doesn't break through Focus. `active` is the default. `timeSensitive` breaks through Focus and requires the `com.apple.developer.usernotifications.time-sensitive` entitlement, and the user can turn it off per app. `critical` requires an Apple-approved entitlement for emergency or safety use — [UNNotificationInterruptionLevel](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel). This is a summary of the page; the time-sensitive entitlement is self-assigned in Xcode capabilities, while critical needs an application to Apple.
- Provisional authorization (iOS 12+): no prompt. Notifications are "delivered quietly and only show up in Notification Center", where the user chooses "Keep" or "Turn Off" — [WWDC18 Session 710](https://developer.apple.com/videos/play/wwdc2018/710/); [Use Your Loaf](https://useyourloaf.com/blog/provisional-authorization-of-user-notificatons/)

### Inferences
- Budget: about 8 nudges a day × 3 days ≈ 24 pending requests, well under 64. Keep a 2–3 day horizon and top it up whenever the app or a background task runs.
- Coaching nudges shouldn't use timeSensitive. App Review and users may treat that as abuse, and Focus is meant to filter this kind of content. A possible exception is a user-set "bedtime" reminder, offered as an opt-in.

### Gaps
- I couldn't fetch the Apple pages on `UNCalendarNotificationTrigger` and the notification summary, because they render client-side. From platform knowledge, not cited this session: the calendar trigger takes `DateComponents` in the device's current calendar and time zone and supports `repeats`. In the scheduled summary, active and passive notifications are batched unless the user exempts the app; timeSensitive bypasses the summary.

## iOS: background execution (BGTaskScheduler, Core Bluetooth, action handlers)

### Takeaway
BGAppRefreshTask gives about 30 seconds at a time the system picks. `earliestBeginDate` is a floor, not a schedule, so it can't drive time-of-day logic. The most reliable background wake for Tempo is Core Bluetooth: with `bluetooth-central` and state restoration, iOS relaunches the app for BLE events (connection, characteristic notify), giving about 10 seconds each time. This doesn't work after the user force-quits the app or toggles Bluetooth. A notification action without `.foreground` runs in the background for a short time, which is enough to update the DB and reschedule.

### Cited Findings
- BGAppRefreshTask gets about 30 seconds of runtime. `earliestBeginDate` means "it won't start any sooner than that", and iOS may delay further based on power and usage patterns — [Uy Nguyen: BG App Refresh best practice](https://uynguyen.github.io/2020/09/26/Best-practice-iOS-background-processing-Background-App-Refresh-Task/); [Andy Ibanez: Modern background tasks](https://www.andyibanez.com/posts/modern-background-tasks-ios13/). These are secondary sources; the Apple doc page didn't render.
- iOS 26 added `BGContinuedProcessingTask`. It's for work the user starts in the foreground (export, upload), which keeps running after the app is backgrounded and shows system progress UI the user can cancel — [WWDC25 Session 227 "Finish tasks in the background"](https://developer.apple.com/videos/play/wwdc2025/227/). Inference: it doesn't fit periodic re-evaluation, but it could cover a long history sync the user starts.
- `bluetooth-central` wakes the app for connections and disconnections, characteristic notifications and state changes. The app has "~10 seconds" to handle each event, and over-use leads to throttling or termination. Background scans coalesce duplicates and need service UUIDs — [Core Bluetooth Background Processing (archive)](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- With `CBCentralManagerOptionRestoreIdentifierKey`, the system preserves scans, pending connections and subscriptions, and relaunches the app with `willRestoreState`. Connection requests "don't timeout" — [same archive doc](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- Relaunch conditions (iOS 11+): the app is relaunched if it was removed from memory, crashed, or the device restarted (only after the first unlock). It is not relaunched if the user force-quit it or Bluetooth power was toggled. It is relaunched only for a pending BLE request whose event actually occurred — [Apple QA1962](https://developer.apple.com/library/archive/qa/qa1962/_index.html)
- In flutter_local_notifications, `onDidReceiveBackgroundNotificationResponse` runs in a separate isolate on iOS. Using plugins there requires `setPluginRegistrantCallback` in AppDelegate. Actions marked `DarwinNotificationActionOption.foreground` open the app. Other options are `destructive` and `authenticationRequired` — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md); [pub.dev](https://pub.dev/packages/flutter_local_notifications)

### Inferences
- Pattern for Tempo on iOS: keep a pending connect to the band, so state restoration relaunches the app when the band comes back in range. On wake, pull a small amount of data, recompute, and rewrite the pending notifications within about 10 seconds. The Flutter engine's cold start may use a large share of that 10 seconds. Measure it, and do the scheduling in native Swift if needed.
- Use background actions for Done, Snooze and Move to evening. Each one writes a row and calls cancel plus zonedSchedule, which is cheap.

### Gaps
- I found no quantitative data on how often BGAppRefreshTask actually runs in 2025–2026. The anecdotal pattern is a few times a day for frequently used apps and rarely for unused ones.
- I couldn't confirm the exact background time allowed for a non-foreground notification action from a primary Apple source. Platform knowledge says it's a few seconds.

## Flutter packages: versions, APIs, pitfalls

### Takeaway
Use flutter_local_notifications 22.x (needs Flutter ≥3.38.1 and compileSdk 35) with `timezone` + `flutter_timezone` for `zonedSchedule`. Use `AndroidScheduleMode.inexactAllowWhileIdle` by default and `exactAllowWhileIdle` only when `canScheduleExactNotifications()` is true. Use workmanager 0.10.x only as an opportunistic safety net. You don't need android_alarm_manager_plus or flutter_background_service for notification delivery.

### Cited Findings
- flutter_local_notifications 22.3.1 (Sept 2026), with minimum Flutter 3.38.1, Android compileSdk 35 and AGP 8.11.1+. The README text mentions AGP 9.1.1, which conflicts with the pub.dev page; check it on upgrade. Schedule modes: `exact`, `exactAllowWhileIdle`, `inexact`, `inexactAllowWhileIdle` — [pub.dev](https://pub.dev/packages/flutter_local_notifications); [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)
- The manifest needs `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, plus `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` (boot intent filter) and `ActionBroadcastReceiver` (for actions). For exact timing, add `SCHEDULE_EXACT_ALARM` (user-granted) or `USE_EXACT_ALARM` (Play-restricted). Use `requestNotificationsPermission()` and `requestExactAlarmsPermission()` on `AndroidFlutterLocalNotificationsPlugin` — [pub.dev](https://pub.dev/packages/flutter_local_notifications)
- Using `exactAllowWhileIdle` without the exact-alarm permission makes the plugin log an error, and the notification isn't scheduled. Fall back to inexact — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md). Older plugin versions threw a `PlatformException` instead (from issue history, not re-verified).
- Background action handler: it must be top-level or static and annotated with `@pragma('vm:entry-point')`. On Android, actions without `showsUserInterface: true` run in a new Flutter engine with no Activity context — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)
- Release builds: configure keep rules so notification icon resources survive shrinking. Core library desugaring (`coreLibraryDesugaringEnabled true` with `desugar_jdk_libs`) is required — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)
- `timezone` doesn't detect the device zone. Use `flutter_timezone` and then `tz.setLocalLocation(tz.getLocation(name))` — [README](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/README.md)
- workmanager 0.10.10 (Sept 2026, fluttercommunity) wraps Android WorkManager (15-minute periodic minimum) and iOS BGTaskScheduler. It needs a `callbackDispatcher` annotated with `@pragma('vm:entry-point')` — [pub.dev workmanager](https://pub.dev/packages/workmanager)

### Inferences
- Background isolates (the action handler, the workmanager callback, an FGS isolate) and the UI isolate all open the Drift DB. Use a shared-isolate or WAL setup so they don't run into locking errors.
- Re-initialise the `tz` location in every isolate, and reschedule when the time zone changes (listen to the app lifecycle and compare `flutter_timezone` values).

### Gaps
- I didn't review open GitHub issues for 22.x regressions, or android_alarm_manager_plus and flutter_background_service versions. They're not needed for the recommended design.

## Recommended strategy: pre-schedule, then cancel and replace

### Takeaway
Schedule notifications in advance and use background execution only to refine them. Each time the coach plan is computed (app open, BLE sync in the FGS on Android, BLE restoration wake on iOS, notification action, WorkManager or BGAppRefresh safety net), cancel the app's coaching notification IDs and re-issue `zonedSchedule` for the next 24–72 hours. Use deterministic IDs and keep the total under 64 on iOS. Content should stay correct even if no re-evaluation ever runs before it fires.

### Cited Findings
- iOS keeps only the 64 soonest pending requests — [Apple Forums 811171](https://developer.apple.com/forums/thread/811171)
- Background wakes on both platforms are opportunistic: Doze and bucket quotas on Android ([Power limits](https://developer.android.com/topic/performance/power/power-details)), and the BGTask floor-only start plus no relaunch after force-quit on iOS ([QA1962](https://developer.apple.com/library/archive/qa/qa1962/_index.html))
- Scheduled alarms survive the process being killed but not a reboot, so they need the boot receiver — [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)

### Inferences
- Use deterministic IDs, for example `dayOfYear*100 + slot`, so a reschedule replaces rather than duplicates. Keep a small `scheduled_notifications` table recording each ID, its fire time, plan version and `algo_version`, so the app can audit what fired and reconcile after reboot or restore.
- Write content that stays true even if the data goes stale, for example "Check today's recovery before your workout" rather than a hard-coded number. Alternatively, set the payload to a template and fill in the number at delivery time. That's possible on Android only if you build the notification yourself in an alarm receiver; iOS shows pre-baked content unless you add a Notification Service Extension, which only applies to remote push. So bake the best current estimate in at scheduling time and refresh it on every wake.
- Actions: Done means cancel and mark the item done. Snooze means cancel and `zonedSchedule` for now + N minutes (inexact on Android). Move to evening means `zonedSchedule` at the user's evening slot. All of these can run in the background handler. Use `showsUserInterface` or `.foreground` only for "Open".
- Permissions UX: ask for `POST_NOTIFICATIONS` in context. On iOS, consider provisional authorization first. Offer exact alarms on Android as an optional "precise reminders" toggle that sends the user to `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Show an OEM-specific guide (Xiaomi Autostart) on MIUI/HyperOS devices.

### Gaps
- I haven't measured end-to-end reliability, such as the percentage of notifications delivered within 5 minutes on a Xiaomi device with or without exact alarms. That needs on-device testing.
