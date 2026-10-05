# Tempo Coach: current state of the repo (as of commit d7e3fdf, 2026-10-05)

All sources are files in `/home/user/tempo` (repo-relative links, line numbers at d7e3fdf). The tab bar today is Today / Coach / Longevity / Journal / Settings ([app/lib/src/app.dart:304-311](app/lib/src/app.dart)). CLAUDE.md still says "Current phase: Phase 0", but the code is far beyond that: scoring, store schema v7, background sync, coach, longevity. Build-plan constraints that still apply: `packages/scoring` stays pure Dart with unit tests for every formula; raw tables are append-only; derived rows carry `algo_version`; no network; any new BLE opcode needs `// TODO(verify)` plus a packet log in `docs/packets/` ([CLAUDE.md](CLAUDE.md)).

## Scoring engine: coach, load, targets, adaptation, longevity levers

### Takeaway
`packages/scoring/lib/src/coach.dart` holds a complete pure-Dart weekly planner (`weekPlan`), recovery-based day states (`dayState`, `strainTarget`) and a once-a-morning adaptation (`adaptWeek`). The adaptation looks three days ahead, carries a displaced hard session forward and uses RPE effort feedback. Everything works at day granularity. Sessions have no time of day, and the engine has no notion of "missed", "done" or an intra-day replan. Longevity levers only touch the plan for `activeMinutes` and `strength`, through `_applyFocus`.

### Cited Findings
**Types and session library**
- Enums `Sport {running, cycling, walking, strength, yoga, hiit, sport}`, `Goal {fitness, fatLoss, performance, wellbeing}`, `Intensity {rest, easy, moderate, hard}`, `DayState {go, easeOff, rest, general}` and `Effort {heavy, onTrack, light, unknown}` — [coach.dart:15-24](packages/scoring/lib/src/coach.dart)
- `Segment(minutes, zone 1..5)` serialises as `[min, zone]`. `Session` has `key, title, sport?, segments, strainLo/Hi, intensity, note`, plus getters `isRest`, `isHard`, `minutes`, `zones` and `structure`, e.g. "10′ Z2 · 5 × (3′ Z4 / 2′ Z1) · 8′ Z2". JSON keys are `key,title,sport,segments,lo,hi,intensity,note` — [coach.dart:52-155](packages/scoring/lib/src/coach.dart)
- `sessionTemplate(key)` is the only session library. It has 17 keys: rest, easy_walk, mobility, easy_run, aerobic_run, steady_run, threshold_run, vo2_run, long_run, easy_ride, long_ride, tempo_ride, strength_full, strength_lower, yoga, hiit, sport. Unknown keys throw — [coach.dart:161-336](packages/scoring/lib/src/coach.dart)
- `hardKeyFor(Sport)`, `easierKeyFor(Session)` (the Z2 version), `harderKeyFor(Session)`, `_easyKey`, `_longKey` — [coach.dart:338-382](packages/scoring/lib/src/coach.dart)
- `fitMinutes(s, maxMinutes)` trims the longest block, never below 10′ — [coach.dart:384-409](packages/scoring/lib/src/coach.dart)
- `expectedRpe(Intensity)` maps rest/easy/moderate/hard to 1/3/5/7. `intensityForStrain` gives easy below 8, moderate below 14, else hard — [coach.dart:26-39](packages/scoring/lib/src/coach.dart)
- `effortTrend(recent, n=3)` takes the mean of (RPE − expected) over the newest 3 rated sessions and needs at least 2. A mean of +1.5 or more is heavy, −1.5 or less is light — [coach.dart:41-50](packages/scoring/lib/src/coach.dart)

**Weekly plan**
- `CoachPrefs {goal, likes, days (1=Mon..7), maxMinutes}`. `hardPerWeek` is 2 for fitness and performance, 1 for fatLoss and wellbeing — [coach.dart:411-429](packages/scoring/lib/src/coach.dart)
- `weekPlan(p, {general, focus: Lever?})` builds 7 sessions starting Monday. Unavailable days are rest, and Wednesday becomes rest when all 7 days are available. Hard days are placed from the latest available day backwards, at least 2 days apart. A long session (ride or run) goes on a weekend day unless the goal is wellbeing. Easy keys rotate across the remaining days, capped at 2 strength days. In general mode `easy_run` becomes `aerobic_run`. The function then calls `_applyFocus` and `fitMinutes` — [coach.dart:431-491](packages/scoring/lib/src/coach.dart)
- `_applyFocus`: with `Lever.activeMinutes`, up to 2 free easy_walk, mobility or yoga days become a Z2 session (aerobic_run, easy_ride or easy_walk), or one easy_run/easy_ride is lengthened to long_*. With `Lever.strength`, the planner makes sure there are 2 strength days that are never consecutive. No other lever changes the plan — [coach.dart:493-533](packages/scoring/lib/src/coach.dart)

**Targets and day state**
- `strainTarget({recovery, calibrating, load})`. With no recovery and not calibrating the target is 8–12 (general). Calibrating gives 10–14 (general). Recovery ≤33 or overreaching load gives a 0–8 cap. Below 50: 8–12; below 67: 10–13; below 80: 13–16; below 90: 14–17; otherwise 15–18. `StrainTarget.cap` and `.general` are flags — [coach.dart:535-567](packages/scoring/lib/src/coach.dart)
- `dayState(...)`: general while calibrating or with no recovery. Rest at recovery ≤33 or overreaching load. easeOff below 67 or when `daysSinceHard < 2`. Otherwise go — [coach.dart:569-581](packages/scoring/lib/src/coach.dart)

**Adaptation**
- `PlanChange(dayIndex, from, to, reason, state)` and `Adaptation(week, changes, carried)` — [coach.dart:583-598](packages/scoring/lib/src/coach.dart)
- `adaptWeek(week, today, state, {reason, carried, available, effort})` changes today's slot by state:
  - go: take the carried session if `canTakeHard`. Otherwise, with heavy effort and a hard day planned, swap to the easier session and carry the hard one. With light effort on an easy day, step up through `harderKeyFor`.
  - easeOff: a hard session becomes its easier version and is carried.
  - rest: today becomes `rest`, and a hard session is carried.
  - general: a hard session becomes its easier version and is not carried.
  — [coach.dart:600-714](packages/scoring/lib/src/coach.dart)
- Three-day look-ahead: after a rest morning, tomorrow's hard session eases and is carried. No two hard days in a row within today … today+2. A pending carried session is placed at least 2 days ahead on an available day that passes `canTakeHard`, trying easy days first. If nothing fits it is returned as `carried` — [coach.dart:715-771](packages/scoring/lib/src/coach.dart)
- `canTakeHard(i)` requires that day i is neither hard nor rest, that its neighbours are not hard, and that the week has fewer than 2 hard sessions — [coach.dart:616-621](packages/scoring/lib/src/coach.dart)
- `sessionTrimp` and `sessionStrain(s, hrMax, hrRest, dayTrimp)` estimate the strain a planned session adds, using zone midpoints .55/.65/.75/.85/.93 of max HR — [coach.dart:773-801](packages/scoring/lib/src/coach.dart)
- Recorded decisions: at most 2 hard sessions a week, at least 2 days apart; adaptation runs once a day after the first sync that includes last night; the 3-day look-ahead — [docs/decisions.md:35,47](docs/decisions.md)

**Cardio load (ACWR)**
- `LoadStatus {learning, detraining, maintaining, building, overreaching}`. `cardioLoad(dailyTrimp newest-first)`: acute is the 7-day mean, chronic the 28-day mean. Status is learning with fewer than 7 days of data. Ratio below 0.8 is detraining, below 1.0 maintaining, up to 1.3 building, above that overreaching. `productive` is chronic × 0.8–1.3, and `loadHistory(weeks=12)` gives the weekly series — [load.dart:1-73](packages/scoring/lib/src/load.dart)

**Other scoring modules**
- Insights cover journal tags only: next-morning recovery with vs without a tag. They unlock at 30 check-ins, need at least 5 nights per group, and grade confidence as notEnough, none, low, moderate or high — [insights.dart:1-73](packages/scoring/lib/src/insights.dart)
- Activity detection: `detectActivities(mins, hrMax)` with `ActivityParams(hrPct .6, minSteps 90, minMinutes 10, maxGap 2)`. It returns `DetectedActivity{start,end,sport?,avgHr,maxHr,stepsPerMin}` and guesses the sport from cadence and HR — [activity.dart:1-40](packages/scoring/lib/src/activity.dart)
- Sleep plan: `bedtimeMinute(needHours, wakeMinute, latency=10)`, `medianClock`, `consistency(bedtimes, tolerance 25)`, `wakeUps` and `sleepLatency` — [sleep_plan.dart:1-80](packages/scoring/lib/src/sleep_plan.dart)
- The barrel exports activity, baseline, breathing, coach, daily, hrv, insights, load, longevity, recovery, resting_hr, sleep, sleep_plan, sleep_stages, strain, types and zones — [scoring.dart](packages/scoring/lib/scoring.dart)

**Longevity levers**
- `Lever` enum: fitness, restingHr, steps, activeMinutes, strength, sleepDuration, sleepRegularity, breathing, stress, smoking, alcohol, bloodPressure, waist — [longevity.dart:13-27](packages/scoring/lib/src/longevity.dart)
- `TempoAge.levers` returns the actionable contributors with gain ≥ 0.1 years, sorted by gain. restingHr and stress are not actionable — [longevity.dart:127-146](packages/scoring/lib/src/longevity.dart)
- `leverTarget`: fitness = VO₂ norm + 7, RHR 55, steps 10k (8k at 60+), activeMinutes 300/week, strength 2/week, sleep 7.5 h, regularity 30 min SD, breathing 90, stress 30, alcohol 7 units, BP 115, waist 94/80 — [longevity.dart:246-262](packages/scoring/lib/src/longevity.dart)
- `leverWeeks`: 4 for steps, sleep and alcohol; 6 for breathing; 8 for activeMinutes and strength; 12 otherwise — [longevity.dart:264-271](packages/scoring/lib/src/longevity.dart)
- Tempo Age needs 30 days of data and 4 band contributors before it leaves calibration — [longevity.dart:273-329](packages/scoring/lib/src/longevity.dart)

### Inferences
- `adaptWeek` is the natural seam for a "Tempo Coach" engine. It is pure and well tested, but it only reacts to the morning state and a carried session.
- An intra-day replan ("missed morning → evening") would need new inputs (time of day, whether today's session was done or skipped, strain so far) and new pure functions, such as a "rest of today" or a "missed today → reschedule" variant.
- Of the 11 actionable levers, only 2 change the plan. Steps, sleepDuration, sleepRegularity, alcohol and breathing have "what to do" text in the UI (`leverHow`) but no planner or notification hooks. These are the obvious candidates for daily nudges in a merged coach.
- `sessionStrain` already supports a projected end-of-day strain, which could drive evening suggestions.

### Gaps
- `daily.dart` (239 lines), `recovery.dart`, `strain.dart` and the sleep-need code were not read in detail beyond what `today.dart` uses (`sleepNeedHours`, `sleepDebtHours`, `learnedBaseNeed`).
- The engine has no time-of-day preference (morning vs evening trainer) anywhere.

## Store: tables and DAOs relevant to coaching

### Takeaway
Drift schema v7. `plan_days` stores one JSON `Session` per date with `original`, `reason` and `adaptedAt`, but has no status, completion or time-slot column. Workouts link to a plan only through a JSON copy (`workouts.plan`), and only for guided live sessions. Coach state lives in the generic `settings` key/value table: carried session, last adaptation date, focus lever and notification prefs.

### Cited Findings
- `schemaVersion => 7`. Migrations: v2 adds workouts, plan_days and sync_log; v3 adds napHours and baseNeed; v4 band_workouts; v5 minute_samples.aux; v6 spo2.quality and od_events; v7 longevity — [database.dart:47-80](packages/store/lib/src/database.dart)
- `Workouts`: id, start, end, sport?, title, source ('live'|'auto'|'band'), confirmed, strain (day strain added), trimp, avgHr, maxHr, zones (JSON minutes z1..z5), `rpe?`, `plan?` (JSON Session if guided) — [tables.dart:134-152](packages/store/lib/src/tables.dart)
- `PlanDays`: date PK, session (JSON), original?, reason?, adaptedAt?, general — [tables.dart:154-164](packages/store/lib/src/tables.dart)
- `DailyScores`: date PK, strain, trimp, hrMax, sleepPerf, sleptHours, needHours, napHours, baseNeed, sleepStart, sleepEnd, recovery, rhr, hrvProxy, calibrating, algoVersion — [tables.dart:79-98](packages/store/lib/src/tables.dart)
- `Settings` (key, value; "never secrets"), `SyncLog` (ts, summary, result ok|retried|failed|gap, durationMs), `Longevity` (date, tempoAge, realAge, calibrating, contributors JSON, algoVersion), `Journal` (date, tag, value bool) — [tables.dart:110-187](packages/store/lib/src/tables.dart)
- Plan DAOs: `putPlanDay` (insertOnConflictUpdate), `planDay(day)`, `planBetween(from,to)`, `watchPlanBetween` — [database.dart:452-471](packages/store/lib/src/database.dart)
- Workout DAOs: `addWorkout`, `updateWorkout`, `deleteWorkout`, `workout(id)`, `workoutsBetween`, `upsertBandWorkout`, `replaceAutoWorkouts` (keeps live and confirmed rows) — [database.dart:365-450](packages/store/lib/src/database.dart)
- `logSync`, `watchSyncLog`, `putLongevity`, `longevitySince`, `watchLongevity`. `restorable` lists plan_days, workouts and longevity among others — [database.dart:473-530](packages/store/lib/src/database.dart)
- Setting keys used by the coach: `coach_carried` (JSON Session or empty), `plan_adapted` (date key of the last adaptation), `morning_call` (HH:mm or off, default 07:00), `bedtime_nudge` (minutes before, or off, default 30), `wake_time`, `buzz_cues` (1|0), `range_haptic_day`, `smart_alarm`, `pauses` (JSON), `longevity_focus` (JSON {lever,start,weeks}), `longevity_inputs`, `last_sync`, `last_sync_attempt`, `last_sync_error`, `battery_opt_prompted` — [profile.dart:7-41](app/lib/src/core/profile.dart)
- `Profile` lives in setting `profile_v2`. It holds age, height, weight, maxHr?, metric, male, goal, likes, days (default {1,2,4,5,6,7}) and maxMinutes (default 75). `profile.prefs` returns `CoachPrefs` — [profile.dart:43-147](app/lib/src/core/profile.dart)

### Inferences
- Tracking completion against the plan needs either new columns on `plan_days` (status: planned/done/skipped/moved, slot or time, doneWorkoutId) in a v8 migration, or a new derived table. `plan_days` is not raw, so changing it is allowed. It is restored from exports, so `restoreRows` must handle the new columns; per [database.dart:531-534](packages/store/lib/src/database.dart) it drops unknown columns.
- A notification or event log (what was sent, tapped or acted on) has no table today. `sync_log` is the nearest pattern.

### Gaps
- No table records coach messages, nudges or user responses, and none records per-day "lever actions" such as steps or bedtime adherence.

## App services: coach_service, today, longevity_service, sync hooks

### Takeaway
`CoachService.ensureWeek` builds and persists the week. `adaptToday` runs the morning adaptation at most once per date, from `afterSync()`. `afterSync` is the only post-sync hook; it runs after foreground, background and pairing syncs. It adapts the plan, refreshes widgets, reschedules the two notifications and exports to Health. Focus levers come from `longevity_service.dart`, and `setFocus` triggers a week rebuild.

### Cited Findings
- `dailyTrimp(db, day, days=112)` returns TRIMP newest-first from `daily_scores`. `loadFor(db, day)` passes it to `cardioLoad` — [coach_service.dart:15-38](app/lib/src/core/coach_service.dart)
- `ensureWeek(day, {rebuild})` builds through `sc.weekPlan(profile.prefs, general: latest score calibrating, focus: active focus lever)`. It never rewrites past days and keeps adapted days unless asked to rebuild — [coach_service.dart:46-85](app/lib/src/core/coach_service.dart)
- `daysSinceHard(day)` counts days since the last workout with at least 5 minutes in Z4+Z5 over 14 days. `effort(day)` collects (rpe, planned intensity) from the last 7 days, using the plan JSON if guided, else `intensityForStrain` — [coach_service.dart:87-125](app/lib/src/core/coach_service.dart)
- `adaptToday()` returns early if `plan_adapted == today`, if paused, or if today's score has no `sleepEnd`. It then computes `dayState`, reads `coach_carried` and calls `sc.adaptWeek` with `available: profile.days` and the effort trend. It writes each change to `plan_days` with `original`, a reason prefixed by a glyph (▲ ■ ▼ ·) and `adaptedAt`, then saves `coach_carried` and `plan_adapted` — [coach_service.dart:127-184](app/lib/src/core/coach_service.dart)
- `_reason` builds strings such as "Recovery 41% after 5 h 40 m sleep", "... and load overreaching" and "... and load building" — [coach_service.dart:193-207](app/lib/src/core/coach_service.dart)
- `afterSync(db)` calls `CoachService.adaptToday()`, then `loadToday`, `updateHomeWidgets`, `rescheduleNotifications` and `HealthExport.exportNew()` — [home_widgets.dart:69-85](app/lib/src/core/home_widgets.dart). It is called from the background dispatcher ([background.dart:21](app/lib/src/core/background.dart)), the foreground `syncNow` ([providers.dart:136](app/lib/src/state/providers.dart)) and pairing ([pairing.dart:281](app/lib/src/screens/pairing.dart)).
- `rescheduleNotifications(db, t)` schedules the morning call from `morning_call` (default 07:00) and the bedtime nudge at `(t.bedtimeMinute − nudge) % 1440` (default 30 min) — [home_widgets.dart:87-101](app/lib/src/core/home_widgets.dart). It also runs on app open, before any sync ([app.dart:240-254](app/lib/src/app.dart)).
- The `SyncService.syncWith` tail writes `last_sync`, recomputes scores (`recomputeIfStale`, `recomputeFrom`) and runs `updateLongevity(db)` — [sync_service.dart:376-399](app/lib/src/core/sync_service.dart)
- `TodayData` / `loadToday(db)` gather score, history, nights (0–14), load, target, state, plan, planRow, week, needTonight, debt, baseNeed, wakeMinute (setting or median of the last 14 wakes), bedtimeMinute, lastSync, `stale` (over 12 h), today's workouts, baselines, pause and smartAlarm — [today.dart:12-221](app/lib/src/core/today.dart)
- Focus: `LongevityFocus(lever, start, weeks)` with `activeOn` and `weekOn`, stored in `longevity_focus`. `setFocus(db, lever)` saves it for `leverWeeks(lever)` weeks and calls `ensureWeek(rebuild: true)` — [longevity_service.dart:50-103](app/lib/src/core/longevity_service.dart)
- `focusProgress(db, f, profile)` returns (value, weekly goal) for activeMinutes (minutes ≥ 60% HRmax this week), strength (sessions), steps (daily average) and sleepDuration (average hours). Other levers return null — [longevity_service.dart:105-139](app/lib/src/core/longevity_service.dart)
- `updateLongevity(db)` writes today's snapshot plus monthly backfill for 6 months — [longevity_service.dart:320-355](app/lib/src/core/longevity_service.dart)
- `saveRpe(db, workoutId, rpe)` updates the RPE and rescores the day for strength sessions. The coach reads RPE at the next morning adaptation — [score_service.dart:223-232](app/lib/src/core/score_service.dart)
- Auto-detected activities become `workouts` rows with source 'auto' on every rescore — [score_service.dart:120-199](app/lib/src/core/score_service.dart)
- Pause mode (ill or travelling) skips adaptation and removes paused days from the history windows — [docs/decisions.md:48](docs/decisions.md); [coach_service.dart:134](app/lib/src/core/coach_service.dart)

### Inferences
- `afterSync` is the right hook for "re-evaluate the day" logic, but its timing is unreliable: it only runs when a sync runs (WorkManager about every 3 h on Android, unpredictable on iOS, and on open or resume). The `plan_adapted` guard blocks any second evaluation in a day.
- No code compares today's plan with today's workouts. A completion check could be computed in `loadToday` from `workouts` (live with `plan`, auto or band) against `plan` (sport and strain range).

### Gaps
- `HealthExport` and `score_service` were not read in full.

## Notifications, background execution and alarms

### Takeaway
Only two local notifications exist: a daily "morning call" with static text and a one-shot bedtime nudge. Both use the single channel `tempo_daily` with inexact scheduling, no actions, no payload and no tap handler. Background sync is a WorkManager periodic task every 3 h, plus BGAppRefresh on iOS. A foreground service (`flutter_foreground_task`, connectedDevice) runs only during live workouts. There is no exact-alarm permission and no one-off or time-targeted background task.

### Cited Findings
- `TempoNotifications` singleton, with IDs `_morningId = 1` and `_bedtimeId = 2` — [notifications.dart:9-16](app/lib/src/core/notifications.dart)
- One Android channel: `'tempo_daily'`, "Morning call & bedtime", default importance, icon `ic_stat_tempo`. iOS uses default `DarwinNotificationDetails()` — [notifications.dart:18-28](app/lib/src/core/notifications.dart)
- `init()` loads tz data and sets the local zone from `FlutterTimezone`. `initialize` is called with no `onDidReceiveNotificationResponse` and no Darwin categories or actions. Permissions are not requested at init — [notifications.dart:30-50](app/lib/src/core/notifications.dart)
- `requestPermission()` covers Android 13+ `requestNotificationsPermission` and iOS alert and sound — [notifications.dart:52-70](app/lib/src/core/notifications.dart)
- `scheduleMorningCall(minuteOfDay)` uses `zonedSchedule` with `inexactAllowWhileIdle` and `matchDateTimeComponents: time` (repeats daily). The text is static: "Your call for today" / "Open Tempo near your band — it syncs last night and sets today's plan." — [notifications.dart:86-100](app/lib/src/core/notifications.dart)
- `scheduleBedtime(minute, label)` is a one-shot "Bedtime in a little while" / "Aim to be in bed by $label...", rescheduled on every sync — [notifications.dart:102-115](app/lib/src/core/notifications.dart)
- Decision: "Notifications are local only (flutter_local_notifications): a daily morning call and tonight's bedtime nudge, rescheduled after every sync." — [docs/decisions.md:40](docs/decisions.md)
- Settings → Notifications group: a "Morning call" picker (off, 06:30–09:00 in 30-min steps, among others) and a "Bedtime nudge" picker (off/15/30/45/60). Each asks for permission and calls `rescheduleNotifications` — [settings.dart:747-794](app/lib/src/screens/settings.dart). Onboarding requests permission — [onboarding.dart:94](app/lib/src/screens/onboarding.dart)
- Background: `backgroundDispatcher` runs `SyncService(db).run(wait: 2s)` then `afterSync`. `BandBusyException` returns true; other errors return false, so WorkManager retries — [background.dart:13-32](app/lib/src/core/background.dart)
- `scheduleBackgroundSync()` registers periodic task `tempo.sync` every 3 h on both platforms. Android uses `ExistingPeriodicWorkPolicy.keep` and `NetworkType.notRequired` — [background.dart:34-54](app/lib/src/core/background.dart)
- iOS AppDelegate: `WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "tempo.sync", earliestBeginInSeconds: 3*60*60)` and a plugin registrant callback — [AppDelegate.swift](app/ios/Runner/AppDelegate.swift)
- `main()` runs `scheduleBackgroundSync`, `HomeWidget.setAppGroupId` and `TempoNotifications.init`. On iOS it calls `FlutterBluePlus.setOptions(restoreState: true)` — [main.dart:13-31](app/lib/main.dart)
- The app syncs on open and on every `resumed` lifecycle event, except during a live session — [app.dart:235-261](app/lib/src/app.dart)
- `BackgroundGuard` (flutter_foreground_task): channel `tempo_live` "Live workout", service id 4101, `ForegroundServiceTypes.connectedDevice`, wake lock, `autoRunOnBoot: false`. Android only. It also wraps battery-optimisation exemption checks and requests — [background_guard.dart:9-88](app/lib/src/core/background_guard.dart). A one-time "Keep syncing overnight?" prompt is in [app.dart:217-233](app/lib/src/app.dart)
- In-app haptic `TempoHaptics.success()` fires once a day when strain enters the target range (setting `range_haptic_day`). It is not a notification and only fires while the app is open — [app.dart:273-285](app/lib/src/app.dart)
- Smart alarm: `writeSmartAlarm(db, minute)` writes band alarm slot 0 (every day; the band can vibrate up to 30 min early in light sleep) and saves `smart_alarm` — [alarm.dart:8-34](app/lib/src/core/alarm.dart)
- Locked plugin versions: flutter_local_notifications 22.3.1, workmanager 0.10.10, flutter_foreground_task 11.0.3, timezone 0.11.1, flutter_timezone 5.1.1, home_widget 0.10.0, flutter_blue_plus 2.3.13. Riverpod is ^3.4.3, drift ^2.31.0, health ^13.3.2 — [app/pubspec.yaml](app/pubspec.yaml); [pubspec.lock](pubspec.lock)
- AndroidManifest has BLUETOOTH_SCAN (neverForLocation) and BLUETOOTH_CONNECT; legacy BT and location up to SDK 30; POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, VIBRATE, FOREGROUND_SERVICE, FOREGROUND_SERVICE_CONNECTED_DEVICE, WAKE_LOCK, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS and Health Connect write permissions. It declares the `ForegroundService` with `foregroundServiceType="connectedDevice"` and `stopWithTask="true"`, plus flutter_local_notifications' `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver` (BOOT_COMPLETED, MY_PACKAGE_REPLACED, QUICKBOOT). It has **no SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM** and no `ActionBroadcastReceiver` — [AndroidManifest.xml:3-100](app/android/app/src/main/AndroidManifest.xml)
- iOS Info.plist: `BGTaskSchedulerPermittedIdentifiers` = `tempo.sync` and `com.pravera.flutter_foreground_task.refresh`. `UIBackgroundModes` = `bluetooth-central` and `fetch` (no `processing`, no `remote-notification`) — [Info.plist:5-9,74-78](app/ios/Runner/Info.plist)
- A repo-wide search found no `AndroidNotificationAction`, `actions:`, `onDidReceiveNotificationResponse`, `registerOneOffTask` or `AndroidScheduleMode.exact*` in `app/lib` or the manifest (grep run during this research).

### Inferences
- The morning call only asks the user to open the app. It cannot say "today: Threshold intervals" because it is scheduled ahead with fixed text. Plan-aware content would need rescheduling after `adaptToday` (already in `afterSync`) with dynamic body text, or a separate notification posted when adaptation completes.
- With inexact scheduling and 3-h WorkManager periods, the "fire at time X with fresh state" pattern is approximate. Adding actions ("Done", "Move to evening", "Skip") needs a notification-response handler, including a background `@pragma('vm:entry-point')` callback that opens the Drift DB, the `ActionBroadcastReceiver` in the manifest, and iOS `DarwinNotificationCategory` registration.
- Rescheduling "missed morning → evening" from the background depends on a sync landing; otherwise it only happens when the app opens.

### Gaps
- The Android `minSdk`/`targetSdk` and the Gradle desugaring config (needed by flutter_local_notifications) were not read.
- Whether iOS ever runs `tempo.sync` in practice is not documented in the repo beyond "iOS decides when (if ever)" ([background.dart:34-36](app/lib/src/core/background.dart)).

## UI screens: Coach, Weekly plan, Workout detail, Today, Longevity, Live workout

### Takeaway
The Coach tab shows readiness, today's suggested workout (or a rest card), a week bar chart with the last change, cardio load and learn links. The Longevity tab owns the focus card and the "make this my focus" lever cards. The Coach screen does not show the focus lever: a grep for "focus" in coach.dart, weekly_plan.dart and today.dart found nothing. Today also shows the suggested workout card with a Start button. There is no done or missed state on any plan card.

### Cited Findings
- `WeekView(monday, rows, scores)` with `session(i)`, `original(i)` and `actual(i)`. `weekProvider` calls `ensureWeek` and reads the week's scores. `loadHistoryProvider` covers 12 weeks — [coach.dart:26-65](app/lib/src/screens/coach.dart)
- `CoachScreen`: header badge "General plan" or "Personal plan"; a pause banner; a stale banner with a Sync button; a "Today's readiness" line from `_readiness`; a rest card (strain cap, bedtime, carried note) or a `WorkoutCard` (overline "Suggested workout", opens `WorkoutDetailScreen`); a "This week" card with `WeekBars` (planned vs actual) and the latest change line; a Cardio load card — [coach.dart:67-260](app/lib/src/screens/coach.dart). Helpers: `_carriedNote`, `_changeLine`, `_why`, `_readiness` — [coach.dart:403-470](app/lib/src/screens/coach.dart)
- `WeeklyPlanScreen` lets the user edit availability (`AvailabilityEditor`), which saves the profile and calls `ensureWeek(rebuild: true)`. It shows a "What changed" card, "Adapted HH:MM" and planned vs actual strain per day with that day's workouts — [weekly_plan.dart:19-240](app/lib/src/screens/weekly_plan.dart)
- `WorkoutDetailScreen._replace(ref, to, why)` handles manual swaps of today's plan row: it keeps `original`, sets reason "· Swapped to … by you." and sets `adaptedAt`. It has a Start button — [workout_detail.dart:24-41,131,166,191](app/lib/src/screens/workout_detail.dart)
- Today screen: `RestCard` ("Start easy walk") on rest days, otherwise `WorkoutCard(overline 'Suggested for today', onStart: openLive(plan: t.plan), onWhy: WorkoutDetailScreen)` — [today.dart:241-254](app/lib/src/screens/today.dart). `FirstWeekCard` has a checklist with `done` items for onboarding only — [today.dart:493-515](app/lib/src/screens/today.dart)
- `planAdds(t)` and `strainStatus(t)` give the expected strain from today's plan — [shared.dart:296-350](app/lib/src/screens/shared.dart)
- Longevity tab: `LongevityData` (with focus and progress); `_FocusCard` shows "Your focus", `leverHow`, progress "x / goal" and an "End focus" confirm; `_LeverCard` shows "Make this my focus · N weeks" with a switch-focus confirm that calls `setFocus` — [longevity.dart:19-75,463-611](app/lib/src/screens/longevity.dart)
- `leverHow` gives per-lever "what to do" copy. For example, steps: "Walk more through the day: calls on foot, stairs, a walk after meals."; sleepDuration: "Protect a bedtime ... Tempo nudges you."; sleepRegularity: "Go to bed within the same 30 minutes, weekends too." — [longevity.dart:203-224](app/lib/src/screens/longevity.dart)
- Live session (Riverpod notifier): `start({plan, sport})` reads `buzz_cues`. It buzzes the band 5 s before a segment change (strong buzz on change) and when the connection comes back. Haptic on change. Foreground service on start. On finish it calls `addWorkout(..., source 'live', plan JSON)`, and `rate(rpe)` calls `saveRpe` — [live_session.dart:122-318](app/lib/src/state/live_session.dart). The summary screen has an RPE 1–10 picker — [live_workout.dart:550-735](app/lib/src/screens/live_workout.dart)
- Home widgets show recovery, strain target or cap, and sleep, and deep-link through `tempo://recovery|strain|sleep|today` — [home_widgets.dart:20-125](app/lib/src/core/home_widgets.dart)
- The design doc maps "13 Coach home" to `screens/coach.dart` and the "Morning plan adaptation" flow to `dayState`/`adaptWeek`/`adaptToday` — [docs/design.md:22,54](docs/design.md)

### Inferences
- A unified "Tempo Coach" screen would merge the `CoachScreen` cards with `_FocusCard` and the lever "what to do" items. Today's `WorkoutCard` and `RestCard` would gain status (done, missed, moved). Notification taps would deep-link to it; there is no notification deep-link plumbing today, only the widget URI scheme `tempo://`.
- Manual swap (`_replace`) is the existing pattern for user-driven plan edits, so "Move to evening" or "Skip" actions can reuse it.

### Gaps
- The full `WorkoutCard` API and the `shared.dart` helpers were only partly read. `learn.dart`, `cardio_load.dart` and `journal.dart` were not reviewed.

## Band capabilities usable for coaching

### Takeaway
The band can be buzzed through SIG Immediate Alert 2A06. This is used for interval cues but is still `TODO(verify)`. Live HR works, with continuous measurement and keep-alive. A smart alarm can be written to slot 0. The GATT dump shows the SIG Alert Notification service (0x1811: 2A46 New Alert, 2A44 control point), which could carry text alerts, but no code uses it. Idle or sedentary alerts and realtime steps are not wired up; realtime steps exist only in the band explorer.

### Cited Findings
- `MiBand.buzz({strong})` writes `AlertCommands.mild [0x01]` or `high [0x02]` to `alertLevel` 2A06, and skips silently if the characteristic is missing — [mi_band.dart:564-574](packages/band_ble/lib/src/mi_band.dart); [protocol.dart:273-277](packages/band_ble/lib/src/protocol.dart); [uuids.dart:44-45](packages/band_ble/lib/src/uuids.dart)
- Decision: "band buzz via SIG Immediate Alert 2a06 level 1. Both TODO(verify) until captured." — [docs/decisions.md:38](docs/decisions.md)
- The packet logs show the GATT discovery entry `char 00002a06... [writeNoResp]` and `service 00001811...` with `2a46 [read,write]` and `2a44 [read,write,notify]` — [docs/packets/android-2026-10-03T07-30-26.511121Z.jsonl](docs/packets/android-2026-10-03T07-30-26.511121Z.jsonl)
- Live HR: `startLiveHr()` / `startLiveHrRaw()` send stop-manual, stop-continuous and start-continuous on 2A39, with a keep-alive timer — [mi_band.dart:576-603](packages/band_ble/lib/src/mi_band.dart)
- Band settings: `setAlarm(BandAlarm)`, `setSleepAssist`, `setStressMonitoring` and `setWearLocation`. All config bytes are TODO(verify) — [mi_band.dart:356-370](packages/band_ble/lib/src/mi_band.dart); [settings.dart:1-114](packages/band_ble/lib/src/settings.dart)
- `parseRealtimeSteps` (0x0c, three u32 values) is used only in `core/band_explorer.dart` — [protocol.dart:266-271](packages/band_ble/lib/src/protocol.dart); [band_explorer.dart:115](app/lib/src/core/band_explorer.dart)
- Only one app can hold the band, and a sync holds a lock (`BandBusyException`) — [background.dart:23-24](app/lib/src/core/background.dart); [PLAN.md](PLAN.md) "Only one app can hold the band"

### Inferences
- A band buzz as a coaching nudge needs a BLE connection at nudge time. In the background that means piggy-backing on a WorkManager sync, so it is opportunistic. Text alerts through 2A46 would need protocol work: a new opcode with a packet log and a golden test per CLAUDE.md.
- Steps-lever nudges ("you're at 4k by 3 pm") can use per-minute steps from the last sync (`minute_samples`), with no realtime BLE needed.

### Gaps
- No packet log in the repo confirms that a 2A06 write actually vibrates the band. The 2A46 New Alert payload format and any Huami idle-alert or sedentary-reminder config command were not found in the repo.

## Gaps to build for adaptive, notification-driven coaching (and tests)

### Takeaway
Most building blocks exist: a pure planner and adaptation, load, targets, levers with targets, focus progress, a post-sync hook, local notifications and a band buzz. The missing pieces are intra-day state, a completion model, a richer and actionable notification scheduler, and a unified screen. Tests cover the scoring rules and services well but cover no notification behaviour.

### Cited Findings
**Missing pieces**
- Adaptation runs at most once a day: the guard `if (await db.setting(Keys.planAdapted) == key) return const [];` — [coach_service.dart:133](app/lib/src/core/coach_service.dart)
- `Session` has no time-of-day or slot field — [coach.dart:63-155](packages/scoring/lib/src/coach.dart). `PlanDays` has no status or completion column — [tables.dart:154-164](packages/store/lib/src/tables.dart)
- Only workouts recorded live from a plan store `plan` JSON. Auto-detected and band workouts have `plan == null` — [tables.dart:150-151](packages/store/lib/src/tables.dart); [score_service.dart:180-198](app/lib/src/core/score_service.dart)
- Notifications have 2 fixed IDs, one channel, no actions and no tap handler — [notifications.dart:16-50](app/lib/src/core/notifications.dart)

**Existing tests**
- Scoring coach tests cover zones, cardio load, strain targets, day state, session JSON, session strain, fitMinutes, the week plan (availability, ≤2 hard and never back to back, a rest day, general), adaptation (rest carries, ease off, go takes carried, heavy and light effort, no third hard day, after-rest easing, no consecutive hard within 3 days), effort, activity detection, insights and the sleep plan — [packages/scoring/test/coach_test.dart:21-383](packages/scoring/test/coach_test.dart)
- Longevity tests cover conversion, hazards, Tempo Age, pace, and "coach focus" (active minutes adds Z2 without new hard days; strength gives two non-consecutive days) — [packages/scoring/test/longevity_test.dart:7-224](packages/scoring/test/longevity_test.dart)
- App service tests: `coach` group (effort from RPE vs implied strain; no adaptation while paused; strength RPE rescoring), pause, restore, sync gap, widget links, band workouts, and longevity (inputs, manual details, snapshot algo version, pace, "a focus lever reshapes this week's plan") — [app/test/services_test.dart:30-317](app/test/services_test.dart)
- Widget tests: all screens render in both themes; Longevity hero, focus card and large text; Today states (normal, first day, calibrating, not paired, no permission, sync failed, syncing, stale); Live workout — [app/test/screens_test.dart:111-283](app/test/screens_test.dart)
- Store tests include "plan days upsert by date" and "auto workouts are replaced; live and confirmed ones stay" — [packages/store/test/store_test.dart:97-131](packages/store/test/store_test.dart)
- Test support: `app/test/support/harness.dart` and `seed.dart` for seeded DBs ([app/test/support](app/test/support))

### Inferences
Gaps for "Tempo Coach", grounded in the code above:
1. **Intra-day replanning (pure Dart, `packages/scoring`)**: new functions that take (today's session, now, done or not, strain so far, recovery state, user's preferred slots) and return a move-to-evening, shortened (`fitMinutes`), easier or skip-and-carry decision, reusing `easierKeyFor` and the `adaptWeek` carry rules. They need unit tests in the style of coach_test.
2. **Completion model**: match today's workouts (live with plan, confirmed auto, band) to the plan by sport and strain range or zones. Persist status on `plan_days` (schema v8) or derive it in `loadToday`. Feed missed days back into the weekly carry logic, which today only carries for recovery reasons.
3. **Daily notification schedule**: extend `TempoNotifications` with plan-aware morning text after `adaptToday`, a pre-session reminder at the preferred slot, a "missed → evening?" check, lever nudges (steps progress, bedtime/regularity, which already exists), and an evening wrap-up or RPE prompt. Use separate IDs and channels, and reschedule from `afterSync` and from app open (both already call `rescheduleNotifications`).
4. **Notification actions**: register the response callbacks (foreground and background entry point), add the `ActionBroadcastReceiver` to the manifest, add Darwin categories, and add deep links into the coach screen.
5. **Settings**: new keys next to `morning_call` and `bedtime_nudge` (e.g. preferred workout time, quiet hours, per-nudge toggles); the Settings → Notifications group is the place.
6. **Unified screen**: merge `CoachScreen` with the Longevity `_FocusCard`/`leverHow`/`focusProgress` into one "today's plan + what to do" list. Longevity keeps Tempo Age and trends.
7. **Optional band nudge**: `buzz()` during background syncs, which is opportunistic and still TODO(verify).
8. **Tests**: there are no tests for `notifications.dart`, `rescheduleNotifications` or `afterSync` ordering. These need a fake notifications seam, since `TempoNotifications` is a concrete singleton over the plugin.

### Gaps
- No product spec for "Tempo Coach" exists in the repo: PLAN.md and docs/design.md have no section on it. Task #17 in the session task list ("Tempo Coach: research and plan") is the only reference.
- Exact-alarm policy (whether to add `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`) and iOS 64-pending-notification limits are platform questions outside this repo scan.
