# Design → code

The source of truth for the UI is the Tempo design canvas
(claude.ai artifact `CtNEKWWnbaHpY5infsKrWd`, 45 boards on 8 pages). This maps
each board to the code that implements it.

## Brand & system

| Board | Code |
| --- | --- |
| 01 Brand (mark, lockup, app icon, splash count-in) | `design/components.dart` (`TempoMark`, `TempoLockup`), `app.dart` (`Splash`), `tools/brand/make_icons.py`, Android `res/drawable/*`, iOS `LaunchScreen.storyboard` |
| 02 Colour tokens | `design/tokens.dart` (`TempoColors`, `TempoScales`) |
| 03 Type, space, shape, motion, haptics, icons | `design/type.dart`, `design/tokens.dart` (`TempoSpace`, `TempoRadii`, `TempoMotion`), `design/components.dart` (`TempoHaptics`), `design/icons.dart` |
| 04 Components — data | `design/meter.dart` (`ScoreMeter`, `TargetMeter`, `TickRow`, `TargetStrip`, `DeviationBar`, `SegmentBar`, `IntervalBars`), `design/chart.dart`, `screens/recovery.dart` (`RecoveryTrend`), `screens/sleep.dart` (`Hypnogram`), `screens/coach.dart` (`WeekBars`, `MiniLoad`) |
| 05 Components — UI | `design/components.dart` (buttons, badges, banner, segmented, chips, switch, yes/no, field, toast, sheet, empty states), `app.dart` (tab bar + start button) |

## Screens

| Board | Code |
| --- | --- |
| Today (dark, light, motion, all states) | `screens/today.dart`, `screens/shared.dart` |
| 13 Coach home (+ states) | `screens/coach.dart` |
| 14 Cardio load (+ explainer sheet, all four statuses) | `screens/cardio_load.dart` |
| 15 Suggested workout | `screens/workout_detail.dart` |
| 16 Weekly plan | `screens/weekly_plan.dart` |
| 17 Learn, Learn cards | `screens/learn.dart` |
| 1 Onboarding (8 steps) | `screens/onboarding.dart` |
| 2 Pairing (scan → success, wrong key, not found, busy) | `screens/pairing.dart` |
| 4 Recovery detail (primed, low, calibrating) | `screens/recovery.dart` |
| 5 Strain detail | `screens/strain.dart` |
| 6 Sleep detail | `screens/sleep.dart` |
| 7 Live workout (guided, open, paused, summary + RPE) | `screens/live_workout.dart`, `state/live_session.dart` |
| 8 Trends | `screens/trends.dart` |
| 8a Day timeline | `screens/day_timeline.dart` |
| 8b Activity detail | `screens/activity_detail.dart` |
| 8c Night detail | `screens/night_detail.dart` |
| 8d Stress detail | `screens/stress.dart` |
| 8e Baselines | `screens/baselines.dart` |
| 8f Calendar | `screens/calendar.dart` |
| 8g Insight detail | `screens/insight_detail.dart` |
| 8h Data health | `screens/data_health.dart` |
| 9 Journal (check-in, insights, locked) | `screens/journal.dart` |
| 10 Weekly report + share card | `screens/weekly_report.dart` |
| 11 Profile & settings | `screens/settings.dart` |
| 12 Widgets | Android `kotlin/.../TempoWidgets.kt` + `res/layout/tempo_widget_*.xml`; iOS `ios/TempoWidget/`; data from `core/home_widgets.dart` |
| States × screens | rules applied per screen; covered by `app/test/screens_test.dart` |

## Flows

| Flow | Code |
| --- | --- |
| Pairing | `screens/pairing.dart` |
| First-week calibration | `scoring` (`calibrating`, 14 nights), `core/today.dart` (`nights`), Today / Coach / Recovery calibrating states |
| Morning plan adaptation | `scoring/lib/src/coach.dart` (`dayState`, `adaptWeek`), `core/coach_service.dart` (`adaptToday`, run from `afterSync`) |

## Where the design is approximated

- Glyphs ▲ ■ ▼ ⚠ aren't in Geist; the platform's fallback font draws them.
- Charts are drawn in the design's 520-unit view box and scaled, so stroke widths scale with screen width.
- The design's sample numbers are replaced by your data; empty states appear where data is missing.
