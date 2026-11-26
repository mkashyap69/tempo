# v3 UI and UX

As of Nov 26, 2026 · Proposal for the owner. Nothing here is decided until it lands in `docs/decisions.md`.

Mock-ups: claude.ai artifact `EJZX9kuSQtciU4a9ta8MTy` ("Tempo v3 — every screen", 35 boards on 7 pages). Builds on `User flow and journey.md` (F1) and keeps the design tokens in `app/lib/src/design/tokens.dart`.

## The brief

Make Tempo clearly different from the strap, the ring, the big-tech tracker and the benchmark Health app, and make it work for two very different people: someone who wants to feel better and understand their health numbers, and someone training for a goal.

## What sets v3 apart

| # | Idea | What it means on screen | Why the field doesn't have it |
| --- | --- | --- | --- |
| 1 | **Two lenses, one engine** | Everyday or Athlete, set in onboarding from "what brings you here", switchable on Today and in You. The rings keep one name per number (decision 2026-10-31); the lens changes only the words under them and the coach's sentences: "well rested, a brisk 40 fits" vs "HRV and sleep helped, 6.8 to go". | Competitors speak athlete to everyone. |
| 2 | **A call, not three dials** | Today opens on one word (Push · Build · Steady · Ease · Rest), one sentence, the two signals that decided it, and a button. "Why?" opens the reasoning, including what would have changed it. | Competitors lead with dials. |
| 3 | **The rings, kept** | Today's three nested rings (`TodayRings`: recovery outside in its state colour, strain /21 with today's target as two ticks, sleep as a share of need) stay as built, with the legend, the hold-to-explain sheet and the mini rings bar. They open every phase of Today and the widgets; v3 removes what repeated them (score tiles, a separate effort bar). | Strain is shown after the fact. |
| 4 | **Your normal, not the internet's** | Every body signal on a strip of your 60-day normal. Each opens one template: what it is, your normal, why it moved, what to do, when it's worth a doctor's view, what moves yours, and the data source. | Raw numbers and population charts. |
| 5 | **A plan that shows its working** | Plan changes: every coach edit as before → after, the signal behind it, Undo. | AI coaches change plans silently. |
| 6 | **Proof, not tips** | Experiments (14 days) with before/during and how sure Tempo is; impacts ranked by size. | Journals stop at correlations. |
| 7 | **The day has a shape** | Morning reveal (feel first) → day story timeline → evening: lights-out time, tomorrow's forecast as a range for two bedtimes, wind-down. | Same screen at 07:00 and 22:00. |
| 8 | **Private by design** | Works without an account; a ledger of every network call in You → Privacy. | Cloud account first. |

## Navigation

```
 Today      Train      ( + )      Health      You
```

| Tab | Question | v2 source |
| --- | --- | --- |
| Today | How am I, what do I do? | Today |
| Train | Am I getting fitter? | Plan + Progress → Trends (fitness, cardio load), History, strength |
| (+) | I want to start or note something | Start / Log sheet, plus Experiment |
| Health | Am I healthy, and what moves it? | Progress → Tempo Age, Trends (body, sleep), Discoveries, Labs; Week in review |
| You | Me, my data, my settings | You, plus lens and the network ledger |

Week in review opens from Today on Mondays and lives under Health.

## Screens on the canvas

| Page | Boards | Closest code today |
| --- | --- | --- |
| Vision | v3 overview, signature components and lens vocabulary | `design/` |
| Today | Everyday lens, Athlete lens, Evening, Morning reveal, Why this call | `today.dart`, `today_parts.dart`, `today_more.dart`, `highlight.dart` |
| Train | Train tab, Session (how and why), Live run, Live strength, After the session, Goal, Plan changes | `coach.dart`, `plan_parts.dart`, `workout_detail.dart`, `live_workout.dart`, `strength_log.dart`, `goal.dart`, `move_skip.dart` |
| Health | Body check, Metric explained (HRV), Sleep, Recovery in points, Effort and fitness, Tempo Age, Blood markers, Discoveries, Week in review | `trends.dart`, `baselines.dart`, `sleep.dart`, `recovery.dart`, `strain.dart`, `cardio_load.dart`, `longevity.dart`, `labs.dart`, `journal.dart`, `weekly_review.dart` |
| Log and You | (+) sheet, Check-in, Add an activity, Not today, You, Privacy, Coach and notifications | `nav.dart`, `journal.dart`, `add_activity.dart`, `settings.dart`, `data_sources.dart`, `data_health.dart`, `coach_settings.dart` |
| First run | Welcome, What brings you here (sets the lens), Connect Health, First read and learning | `onboarding.dart`, `source_check_view.dart` |
| Outside | Widgets, lock screen, Live Activity, notifications, share card | `core/home_widgets.dart`, iOS `TempoWidget/`, Android `TempoWidgets.kt` |

## What it needs underneath

Most of v3 is presentation over data Tempo already computes (daily call, strain target, baselines, sleep need and plan, tomorrow's recovery, recovery points, Tempo Age with confidence, journal impacts and experiments, insight log). New pieces:

- **Lens** on `Profile` and a word map from score bands to plain words (pure Dart, unit-tested).
- **Plan change log**: an append-only table of coach edits (before, after, reason, signals, undone). Schema change in `packages/store`.
- **Metric explainer content** per body signal: what it is, typical range by age and sex, doctor threshold wording. Needs a source per range before it ships.
- **Network ledger**: count each allowed call by kind on the phone (no new network call).

## Suggested order

1. **V1 Today**: rings unchanged on top, then the call card (no numbers the rings already show), lens and vocabulary. Gate: 5-second test, 9 of 10 right, with both lenses.
2. **V2 Health**: Body check strips, one metric template for all signals, Tempo Age as a range. Gate: half of testers open a "what this means" page in week 1.
3. **V3 Train**: merge Plan and fitness into Train, plan change log with Undo. Gate: 4 weeks with the log on, athletes keep the plan after a change.
4. **V4 Evening and moments**: evening Today, forecast, wind-down, notifications in one voice. Gate: 14 evenings of forecast against the morning.
5. **V5 First run**: "what brings you here" sets the lens; first read shows what's ready.

## Open questions

0. The rings' centre word is the recovery state (Primed · Steady · Low) and the call is the decision (Push · Build · Steady · Ease · Rest). Keep both, or show the call word in the centre? "Steady" appears in both lists.

1. Lens: a hard setting, or derived from the goal with a switch? (Mock-ups: set from the goal, switchable.)
2. Is "Train" the right name for Everyday users whose goal is "feel better"? Alternative: "Move".
3. Which typical ranges (HRV, VO₂ max, blood markers) do we cite, and who reviews the "when to see a doctor" wording?
4. Does the weather call stay (it's on the ledger), or move behind a setting?
