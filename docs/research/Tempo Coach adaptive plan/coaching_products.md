# How adaptive fitness-coaching products adapt plans and notify users (Garmin, Whoop, Oura, Apple, Runna, TrainingPeaks, Athlytic/Bevel, Fitbod)

> Method note (2026-10-05): the network proxy blocked full-page fetches for nearly every primary source (support.whoop.com, whoop.com, ouraring.com, support.runna.com, the5krunner.com, dcrainmaker.com, wareable.com, shoulditrain.com). The findings below come from **search-engine result summaries** of the cited pages, not from full reads. Treat exact wording and numbers as "per the page's search snippet". Where something is known only from background knowledge and not confirmed by a source here, it is in **Gaps**, not in Cited Findings.

## Q1. Inputs: what signals does each product use to decide the day?

### Takeaway
Every product starts from an overnight recovery signal (HRV, RHR and sleep, plus skin temperature on Oura, Whoop and Apple-based apps) and weighs it against recent load. Garmin and Fitbod also use performance and fitness models (VO2max, muscle freshness). Explicit user feedback (RPE or "how did it feel") is only used by the plan-based products: Garmin Coach, Runna and Fitbod.

### Cited Findings
- **Garmin Daily Suggested Workouts (DSW)** inputs: Training Status, Training Load and Load Focus, sleep data, recovery hours, VO2max and recent workouts. Low readiness pushes it toward easy runs or rest, and high readiness toward harder sessions. It re-evaluates after each recorded activity — [the5krunner](https://the5krunner.com/garmin-features/training/daily-suggested-workouts/); [Garmin Rumors wiki](https://wiki.garminrumors.com/Daily_Suggested_Workout)
- DSW "prescribes the workout type it believes fills the biggest gap today", using the balance of load across intensities (Load Focus) — [therunninggenie](https://therunninggenie.com/blog/garmin-daily-suggested-workouts-explained)
- **Garmin Training Readiness** is a 0–100 score shown each morning. It combines sleep quality, recovery time, HRV Status, stress and recent (acute) training load. Readiness 1–24 is the "rest day" band. Training Readiness feeds into DSW and shifts suggestions toward recovery when it is low — [shoulditrain: Training Readiness](https://www.shoulditrain.com/blog/garmin-training-readiness-explained); [Garmin Rumors wiki](https://wiki.garminrumors.com/Training_Readiness)
- **Garmin Coach** (race plans) inputs: performance data (VO2max, training load, lactate threshold, FTP), recovery data (sleep, HRV status, training readiness, recovery time) and lifestyle data (missed workouts, schedule changes, stress) — [shoulditrain Garmin Coach review](https://www.shoulditrain.com/blog/garmin-coach-review); [gneta Garmin Coach review](https://www.gneta.app/blog/garmin-coach-review)
- **Whoop Strain Target** is based on "last night's sleep and today's recovery score". It "dynamically updates throughout the day" and refreshes every 10 minutes — [Whoop support: Strain Target](https://support.whoop.com/s/article/Strain-Coach?language=en_US)
- **Whoop Coach** (AI, built on OpenAI) analyses "biometric data, behavioral patterns, and environmental factors" — [Whoop support: AI-Powered Whoop Coach](https://support.whoop.com/s/article/How-to-Use-the-AI-Powered-WHOOP-Coach?language=en_US); [Whoop: Introducing Whoop Coach](https://www.whoop.com/us/en/thelocker/introducing-whoop-coach-powered-by-openai/)
- **Whoop Sleep Coach / Sleep Planner** computes a nightly sleep need dynamically. The 2025-era Sleep Planner also takes circadian rhythm into account — [Whoop: Sleep Planner feature update](https://www.whoop.com/us/en/thelocker/feature-update-whoop-app-sleep-planner/); [Whoop Sleep Coach FAQ](https://support.whoop.com/APP_FEATURES__COACHING/Understanding_Your_WHOOP_Features/Sleep_Coach_with_Haptic_Alerts_Commonly_Asked_Questions)
- **Oura Readiness** contributors include RHR, HRV balance, recovery index, body temperature and the previous night's sleep, plus activity contributors. Rest Mode turns the activity contributors off — [Oura blog: Rest Mode](https://ouraring.com/blog/ouras-new-rest-mode-helps-optimize-your-recovery/); [Oura blog: Readiness](https://ouraring.com/blog/readiness-score/)
- **Oura bedtime guidance** is "calculated relative to the nights you've slept the longest and most efficiently" and can update daily — [Oura blog: ideal bedtime](https://ouraring.com/blog/ideal-bedtime/)
- **Apple Workout Buddy** (watchOS 26, 2025) uses heart rate, pace, distance, Activity rings, personal milestones and fitness history, including the Training Load feature from watchOS 11 — [Apple Newsroom, June 2025](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/); [DC Rainmaker watchOS 26](https://www.dcrainmaker.com/2025/06/apple-watchos-26-announced-workout-buddy-and-more-explained.html)
- **Athlytic** Exertion (0–10) uses your 30-day max HR, 60-day average RHR and time above a personalised HR threshold. The app suggests a Target Exertion Zone from your Recovery score. It monitors HRV, RHR, SpO2, respiratory rate and wrist temperature against your normal range — [Athlytic help: Exertion & Target Exertion](https://athlyticapp.helpscoutdocs.com/article/53-understanding-exertion-and-target-exertion); [Athlytic App Store](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755)
- **Bevel and Athlytic** both read Apple Health and produce a daily recovery/readiness score from HRV and RHR. They are positioned as Whoop-style layers over Apple Watch — [lifestack: Bevel vs Athlytic](https://lifestack.ai/blog/bevel-vs-athlytic); [fitcoin: Bevel vs Athlytic](https://www.fitcoin.co/articles/bevel-vs-athlytic)
- **Fitbod** tracks how "fresh" each muscle group is. Every logged workout (reps, sets, weights, equipment, exertion level and missed days) informs the next one — [Fitbod blog: personalisation](https://fitbod.me/blog/how-fitbod-personalizes-your-workout-plan-using-smart-training-algorithms/); [Fitbod Algorithm Q&A](https://help.fitbod.me/hc/en-us/articles/16254175592215-Fitbod-s-Algorithm-Q-A)
- **Runna** adjusts workouts for heat and humidity, so weather is an input — [Runna support: heat & humidity](https://support.runna.com/en/articles/15647483-how-does-runna-adapt-my-workouts-for-heat-and-humidity)

### Inferences
- A Mi Band 6 can supply HR, a resting-HR proxy, sleep staging, SpO2 and stress (a vendor HRV-derived value). That covers Whoop/Oura-style recovery inputs except validated overnight HRV and skin temperature. A Garmin-style "Load Focus" (gap filling across low aerobic, high aerobic and anaerobic) is achievable from HR zones.
- Explicit feedback (RPE or "how did it feel") is the cheapest high-value input for a band without good performance metrics. Fitbod and Garmin Coach both use exertion feedback.

### Gaps
- Exact Training Readiness weighting and Firstbeat white-paper formulas could not be fetched. Background knowledge says Garmin's Training Readiness levels are Prime/High/Moderate/Low/Poor, but this was not verified here.
- I could not confirm whether Bevel uses user-entered RPE.
- I could not confirm Whoop's exact input list for the AI Coach plan builder (Whoop Advanced Labs and journal inputs).

## Q2. Adaptation: daily re-suggestion vs week re-planning; missed, partial, harder or easier workouts; low readiness; illness and travel

### Takeaway
There are three adaptation models:
1. **Stateless daily re-suggestion**: Garmin DSW, Whoop Strain Target, Athlytic, Fitbod. Missed work is simply dropped and nobody "catches up".
2. **Plan with automatic daily rebuild**: Garmin Coach. It moves hard sessions back and eases targets after illness or misses, and pushes harder after strong benchmark runs.
3. **Plan with user-driven rescheduling**: Runna (drag within ±1 week, skip, a "Plan Realignment" pop-up after more than 3 misses, extend or rebuild for illness) and TrainingPeaks (manual, compliance colours).

Illness is handled by an explicit mode (Oura Rest Mode, Runna extend/rebuild) rather than inferred silently. The one exception is Oura's temperature-triggered prompt.

### Cited Findings
- **Garmin DSW, missed workout**: a skipped workout "is simply lost and you continue with the workout schedule for the next day". It does not reschedule — [Garmin Forums: DSW skipping](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-945/251132/daily-suggested-workout-skipping-missing-a-training); [the5krunner](https://the5krunner.com/garmin-features/training/daily-suggested-workouts/)
- **Garmin Coach, daily rebuild**: "The adaptive programs rebuild the schedule daily. Miss a workout and the analytics engine adjusts… do something that was not on the plan and the next workout accounts for it." One example: after a week of illness, a tempo run was replaced with an easy run and the hard session pushed to the next week — [shoulditrain Garmin Coach review](https://www.shoulditrain.com/blog/garmin-coach-review)
- **Garmin Coach, harder or easier**: "Upward adjustment" applies if benchmark runs show faster paces or lower HR than expected (targets rise, long runs extend). "Downward adjustment" applies after missed workouts, runs slower than target or accumulated fatigue (recovery runs replace hard ones) — [gneta Garmin Coach review](https://www.gneta.app/blog/garmin-coach-review)
- Garmin Coach users reported "new adaptive workouts" causing sudden changes in suggested HR zones (forum thread), which suggests re-targeting happens without explanation — [Garmin Forums](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/402015/garmin-coach-new-adaptive-workouts-sudden-change-of-suggested-hr-zones-in-workouts)
- **Garmin, low readiness**: readiness 1–24 is the "rest day" range, and DSW shifts toward recovery or rest — [shoulditrain](https://www.shoulditrain.com/blog/garmin-training-readiness-explained)
- **Runna**:
  - You can drag-and-drop workouts in the calendar, but "only within the same week, or one week forward or one week backward".
  - "Skip" removes a run and Runna "will adjust around your remaining sessions". One skipped run "won't make too much difference".
  - If you've missed more than three workouts or a whole week, a **Plan Realignment pop-up** offers to skip the missed workouts or rearrange them to later in the week.
  - For extended time away (e.g. illness) it offers to **extend the plan** by the time away, or **rebuild from today to the same end date** (fixed race).
  - [Runna: skip/missed sessions](https://support.runna.com/en/articles/15012850-how-and-when-to-skip-a-run-managing-missed-sessions-in-your-training-plan); [Runna: Plan Realignment](https://support.runna.com/en/articles/10026375-how-to-use-the-plan-realignment-feature); [Runna: Training Calendar](https://support.runna.com/en/articles/10137793-how-to-use-your-training-calendar)
- **Runna** adapts pace targets for heat and humidity — [Runna support](https://support.runna.com/en/articles/15647483-how-does-runna-adapt-my-workouts-for-heat-and-humidity)
- **TrainingPeaks** has no automatic adaptation. The "Compliance" view colours completed workouts against planned duration, distance or TSS: within 20% is green, within 50% yellow, beyond 50% red. Premium lets you reschedule missed sessions. Third-party 2026 reviews say TrainingPeaks offered "no adaptive plans, AI-generated workouts or automatic rescheduling" as of Sept 2026, with adjustments made manually or by a coach — [TrainingPeaks Athlete User Guide](https://help.trainingpeaks.com/hc/en-us/articles/231472468-TrainingPeaks-Athlete-User-Guide); [coachbox TrainingPeaks review 2026](https://coachbox.app/en/compare/trainingpeaks-review/) (third-party claim, not TrainingPeaks' own wording); [TrainingPeaks blog: missed workout](https://www.trainingpeaks.com/blog/how-to-work-around-a-missed-workout/)
- **Fitbod**: "if you miss a session or change your frequency, the app recalibrates future workouts so you don't need to 'catch up'". Muscle-recovery state decides which muscle groups to train — [Fitbod blog](https://fitbod.me/blog/how-fitbod-personalizes-your-workout-plan-using-smart-training-algorithms/); [Fitbod Q&A](https://help.fitbod.me/hc/en-us/articles/16254175592215-Fitbod-s-Algorithm-Q-A)
- **Whoop Strain Target**: recalculated intraday every 10 minutes from recovery and sleep. There is no week plan; the target simply resets daily — [Whoop support](https://support.whoop.com/s/article/Strain-Coach?language=en_US)
- **Oura Rest Mode** (illness, injury, stress):
  - User-toggled. It disables the Activity goal, Activity Score and activity contributors for as long as it is on.
  - Readiness then emphasises RHR, HRV balance, recovery index, temperature and sleep.
  - Sleep and Readiness messages switch to recovery guidance.
  - Oura "automatically alerts you" to consider it when body temperature is elevated.
  - [Oura blog: Rest Mode](https://ouraring.com/blog/ouras-new-rest-mode-helps-optimize-your-recovery/); [Tom's Guide on Rest Mode](https://www.tomsguide.com/wellness/fitness/this-one-oura-ring-setting-was-a-game-changer-for-me-after-i-had-my-baby)
- **Oura activity goal** adapts daily to readiness. A May 2025 update ("All Movement Counts") expanded activity features — [Oura blog: Activity Score](https://ouraring.com/blog/activity-score/); [BusinessWire May 2025](https://www.businesswire.com/news/home/20250521864148/en/All-Movement-Counts-URA-Introduces-Enhanced-Activity-Features-and-Expands-Partner-Ecosystem)
- **Apple Activity rings** can be paused (since watchOS 11, 2024), so a streak survives a rest or sick day. Goals can also be set per weekday — [Cult of Mac: tweak and pause rings](https://www.cultofmac.com/how-to/apple-watch-activity-rings)

### Inferences
- A good pattern for Tempo is to combine them:
  - Garmin DSW-style daily re-suggestion (never "catch up").
  - A light weekly skeleton like Runna's: shift sessions within ±1 week, and after N misses show a "realign?" prompt instead of silently rebuilding.
  - An Oura-style explicit Pause/Rest mode that suspends goals and streaks. Tempo already has a "pause mode" (task #11), which matches this.
- Showing why an automatic rebuild happened matters. Garmin forum complaints about sudden target changes show the cost of silent re-targeting.

### Gaps
- Garmin Coach's post-workout "How did it feel / how hard was it" rating, and how that rating moves the plan, was not confirmed from a source here.
- I found no source on how any product handles travel or time-zone shifts specifically.
- Garmin's newer "Garmin Coach" strength and adaptive-plan updates of 2025–26 were not verified.
- Whoop's 2025 "Strength Trainer" and plan-builder adaptation was not verified.

## Q3. Intra-day behaviour: re-suggesting later, "you still have time" prompts, move reminders, bedtime prompts

### Takeaway
No source showed a product re-scheduling a missed morning workout into the evening. Intra-day coaching is instead done through:
- continuously updating targets (Whoop Strain Target every 10 minutes, with a haptic when you hit it);
- "you're close" goal nudges (Apple Daily Coaching, the end-of-day "close your rings" push);
- inactivity alerts (Apple at :50 past the hour; Oura after 50 minutes inactive, with 10 minutes to reset);
- wind-down prompts (Oura 1 hour before suggested bedtime, Whoop Sleep Planner nightly bedtime push, Whoop "Day in Review").

### Cited Findings
- **Whoop Strain Target** updates every 10 minutes. When you reach the target you get a notification and a haptic so you can decide to push on or wind down. On WHOOP 4.0 the haptic fires only during an active session that uses Strain Target; 5.0/MG fire more generally — [Whoop support: Strain Target](https://support.whoop.com/s/article/Strain-Coach?language=en_US)
- **Whoop Sleep Planner** sends "nightly notifications recommending when you should go to bed". The **Day in Review** summary "delivers timely prompts to help you wind down" — [Whoop: Sleep Planner](https://www.whoop.com/us/en/thelocker/feature-update-whoop-app-sleep-planner/); [Whoop: AI guidance](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/)
- **Whoop haptic smart alarm** has three modes based on your schedule, including waking you when you have "reached optimal sleep or recovery" — [Whoop: Sleep Coach with haptic alerts](https://www.whoop.com/us/en/thelocker/new-whoop-4-0-feature-sleep-coach-with-haptic-alerts/)
- **Whoop Daily Outlook** (launched January 2025) is a morning plan-the-day view with personalised recommendations — [gadgetsandwearables, Jan 2025](https://gadgetsandwearables.com/2025/01/24/whoop-daily-outlook/)
- **Oura inactivity alerts**: a "friendly reminder to stretch your legs after 50 minutes of inactivity". You have 10 minutes to reset it with a brief walk or stretch — [Oura help: inactivity alerts](https://help.ouraring.com/activity/inactivity-alerts)
- **Oura bedtime guidance** sends a notification 1 hour before the suggested bedtime "so you can start unwinding" — [Oura blog: ideal bedtime](https://ouraring.com/blog/ideal-bedtime/)
- **Apple Stand reminders** arrive at 50 minutes past the hour if you haven't met that hour's stand goal. **Daily Coaching** sends encouragement "when you're getting close" to goals or monthly challenges, at any time of day — [iMore: Activity notifications](https://www.imore.com/how-customize-notifications-activity-app-apple-watch); [How-To Geek](https://www.howtogeek.com/275101/how-to-completely-disable-all-the-activity-notifications-on-your-apple-watch/)
- Apple Watch "gives you a nudge to close your rings at the end of each day" — [Apple: Close Your Rings](https://www.apple.com/watch/close-your-rings/)
- An academic piece is titled after Apple's evening coaching line "You Can Still Do It", and analyses those notifications during COVID-19 lockdowns — [Flow Journal, 2020](https://www.flowjournal.org/2020/07/apple-watch-notifications/)
- **Apple Workout Buddy** (in-workout voice) mentions ring proximity, e.g. "10 minutes away from finishing your Exercise ring" — [AppleInsider](https://appleinsider.com/inside/watchos-26/tips/how-to-train-smarter-with-workout-buddy-in-ios-26-watchos-26); [Gadget Hacks](https://apple.gadgethacks.com/how-to/apple-watch-gets-ai-workout-buddy-in-ios-26-watchos-26/)
- **Garmin Morning Report** appears automatically "when you first interact with your watch after waking". On supported devices it includes the DSW. There was a 2023 firmware bug (14.13) where the suggested workout went missing from it — [Garmin Rumors wiki: Morning Report](https://wiki.garminrumors.com/Morning_Report); [Garmin Forums bug thread](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-255-series/323497/bug-14-13---suggested-workout-not-in-morning-report)
- **Garmin Sleep Coaching** gives "tailored feedback comparing sleep data against a personal baseline, with an emphasis on HRV insights" — [Yahoo Tech](https://tech.yahoo.com/general/articles/garmin-could-finally-add-napping-164623611.html)

### Inferences
- An "evening fallback" (morning session missed, so offer a shorter or easier version before a cut-off time tied to bedtime) is an open differentiator. No cited product does it explicitly. It should respect sleep: avoid late hard sessions within about 3 hours of the planned bedtime. That cut-off is a design suggestion, not a sourced number.
- Most products converge on 50 minutes for inactivity. The Mi Band 6 has its own on-band idle alert, so Tempo could configure that rather than push from the phone.

### Gaps
- Whether Garmin DSW changes the same day after an unplanned morning activity is reportedly yes ("adjusts after each recorded activity"), but I found no detail on how it appears on the watch.
- I could not confirm the exact timing of Apple's evening "close your rings" push (background knowledge suggests early evening, but it is unverified).

## Q4. Notification inventory: types, timing, content, actions, frequency limits, controls

### Takeaway
Notifications cluster around three moments: morning (report or readiness), goal events (close to goal, goal hit, target hit) and evening (bedtime or wind-down, day review). Hourly move or stand nudges come on top. Each type is a separate toggle. Apple has 5 Activity toggles, all on by default. Oura, Whoop and Athlytic let you toggle each category, and Athlytic adds out-of-range health alerts. Few products use actionable buttons. Garmin uses an on-watch "Start" for the suggested workout, Oura's inactivity alert can be cleared by moving, and Oura's Rest Mode prompt is a one-tap enable.

### Cited Findings
| Product | Notification | Timing | Source |
|---|---|---|---|
| Apple | Stand Reminder | :50 past the hour, if the hour's stand isn't met | [iMore](https://www.imore.com/how-customize-notifications-activity-app-apple-watch) |
| Apple | Daily Coaching ("close to goal", monthly challenge) | any time of day | [iMore](https://www.imore.com/how-customize-notifications-activity-app-apple-watch) |
| Apple | Goal Completions (celebration) | on Move/Exercise/Stand goal hit | [iMore](https://www.imore.com/how-customize-notifications-activity-app-apple-watch) |
| Apple | Special Challenges | ahead of holidays/occasions | [iMore](https://www.imore.com/how-customize-notifications-activity-app-apple-watch) |
| Apple | Activity Sharing | friends' activity | [iMore](https://www.imore.com/how-customize-notifications-activity-app-apple-watch) |
| Apple | Workout Buddy voice | start/during/end of workout, headphones only | [Apple Newsroom](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/) |
| Whoop | Strain Target reached (push + haptic) | when target hit | [Whoop support](https://support.whoop.com/s/article/Strain-Coach?language=en_US) |
| Whoop | Sleep Planner bedtime | nightly | [Whoop](https://www.whoop.com/us/en/thelocker/feature-update-whoop-app-sleep-planner/) |
| Whoop | Day in Review / wind-down prompts | end of day | [Whoop](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/) |
| Whoop | Haptic smart alarm | wake window | [Whoop](https://www.whoop.com/us/en/thelocker/new-whoop-4-0-feature-sleep-coach-with-haptic-alerts/) |
| Oura | Inactivity alert | after 50 min inactive; 10 min to reset | [Oura help](https://help.ouraring.com/activity/inactivity-alerts) |
| Oura | Bedtime guidance | 1 h before suggested bedtime | [Oura blog](https://ouraring.com/blog/ideal-bedtime/) |
| Oura | Rest Mode suggestion | on elevated temperature | [Oura blog](https://ouraring.com/blog/ouras-new-rest-mode-helps-optimize-your-recovery/) |
| Garmin | Morning Report (sleep, HRV, readiness, DSW) | first wrist interaction after waking | [Garmin Rumors wiki](https://wiki.garminrumors.com/Morning_Report) |
| Athlytic | Metric out of normal range (HRV, RHR, SpO2, resp, temp) | when detected; user-configurable | [Athlytic App Store](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755) |

- Oura has a dedicated "Managing Your Notifications" settings article, with per-type toggles — [Oura support](https://support.ouraring.com/hc/en-us/articles/360025579173-Managing-Your-Notifications)
- All Apple Activity notification types are on by default and can each be switched off — [How-To Geek](https://www.howtogeek.com/275101/how-to-completely-disable-all-the-activity-notifications-on-your-apple-watch/)

### Inferences
- A sensible Tempo budget is about 3 scheduled touchpoints a day (morning plan, an optional mid or late-day nudge, evening wind-down) plus event-driven ones (target hit). Each should have its own toggle. All-on-by-default is Apple's choice, and it drives complaints (see Q6).
- An Android notification with action buttons ("Start", "Swap to easy", "Skip today", "Rest mode") would go beyond what most of these products expose.

### Gaps
- I found no published frequency caps (e.g. a maximum per day) for any product.
- Whoop's full notification-settings list, and the Whoop Coach proactive push cadence, were not confirmed because the support site was blocked.
- I could not verify whether Garmin Connect sends a phone push for DSW or only shows it on the watch.

## Q5. Tone and coaching language; explaining "why"

### Takeaway
Products explain "why" by naming the contributors: Garmin's readiness contributors, Oura's contributor list and Rest Mode messages, and Whoop's Strain Target tied to recovery. Tone is encouraging and permission-giving ("you can still do it", "friendly reminder", "focus on recovery when you feel tired"). Apple and Whoop have moved to LLM- or voice-generated personalised lines (Workout Buddy in 2025, Whoop Coach on OpenAI).

### Cited Findings
- Oura Rest Mode is framed as letting you "focus on recovery when you feel tired, unwell, or need to slow down". It removes pressure to meet activity goals — [Oura blog](https://ouraring.com/blog/ouras-new-rest-mode-helps-optimize-your-recovery/)
- Oura's inactivity alert is described as a "friendly reminder to stretch your legs" — [Oura help](https://help.ouraring.com/activity/inactivity-alerts)
- Apple's evening line is "You can still do it" — [Flow Journal](https://www.flowjournal.org/2020/07/apple-watch-notifications/)
- Workout Buddy uses a text-to-speech model built from Fitness+ trainer voices. It "celebrates your achievements in real-time" and references milestones and history — [Apple Newsroom](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/); [AppleInsider](https://appleinsider.com/inside/watchos-26/tips/how-to-train-smarter-with-workout-buddy-in-ios-26-watchos-26)
- Whoop's Strain Target is pitched as "real-time guidance so you do not have to interpret numbers manually". It translates scores into actions — [Whoop support](https://support.whoop.com/s/article/Strain-Coach?language=en_US)
- Garmin DSW shows the workout type and its purpose (e.g. base, threshold, recovery) based on what "fills the biggest gap" — [therunninggenie](https://therunninggenie.com/blog/garmin-daily-suggested-workouts-explained)

### Inferences
- Tempo should use the "one-line why" pattern: "Easy 30 min today — HRV is 12% under your baseline and you've had 3 hard days." It works on-device with templates, and no LLM is needed.

### Gaps
- I could not retrieve verbatim Garmin DSW or Training Readiness message strings, or Whoop push text, because the primary pages were blocked.

## Q6. Known user complaints

### Takeaway
The recurring themes are:
- notifications that are annoying or poorly timed (Workout Buddy turned off by a reviewer; Apple on-by-default nudges);
- adaptive plans that change targets with no explanation (Garmin Coach HR zones);
- daily suggestions that ignore the user's real schedule and are reliability-buggy (Garmin DSW missing from the Morning Report and calendar);
- rigid or manual plans (TrainingPeaks has no auto-adapt; Runna limits moves to ±1 week).

### Cited Findings
- A TechRadar reviewer "tried watchOS 26's Workout Buddy but had to turn it off" (the article is critical of how intrusive it was) — [TechRadar](https://www.techradar.com/health-fitness/i-tried-watchos-26s-workout-buddy-but-had-to-turn-it-off-heres-why)
- Garmin Coach's "new adaptive workouts" caused a sudden change in suggested HR zones, per a forum complaint — [Garmin Forums](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/402015/garmin-coach-new-adaptive-workouts-sudden-change-of-suggested-hr-zones-in-workouts)
- Users complained that missed DSW workouts can't be rescheduled and are just lost — [Garmin Forums](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-945/251132/daily-suggested-workout-skipping-missing-a-training)
- Bugs: DSW missing from the Morning Report (firmware 14.13), DSW not appearing on the calendar, and Garmin fixes in 2024 for the DSW prompt not appearing — [Garmin Forums](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-255-series/323497/bug-14-13---suggested-workout-not-in-morning-report); [Notebookcheck](https://www.notebookcheck.net/Garmin-releases-new-stable-update-for-Fenix-7-Fenix-7-Pro-and-other-smartwatches-with-Daily-Suggested-Workouts-fix-plus-more-improvements.855344.0.html)
- Users debate whether to move or skip workouts on low Garmin readiness (a TrainerRoad forum thread). This points to unclear guidance when a plan conflicts with readiness — [TrainerRoad forum](https://www.trainerroad.com/forum/t/garmin-low-training-readiness-move-workout-or-skip/79182?page=2)
- Guides titled "when to ignore" Garmin DSW exist, which implies users often override them — [therunninggenie](https://therunninggenie.com/blog/garmin-daily-suggested-workouts-explained); [gneta: Are they any good?](https://www.gneta.app/blog/garmin-suggested-workouts-guide)
- TrainingPeaks has no automatic rescheduling, so adjustments are manual — [coachbox review](https://coachbox.app/en/compare/trainingpeaks-review/)
- Runna moves are limited to within ±1 week — [Runna support](https://support.runna.com/en/articles/10137793-how-to-use-your-training-calendar)

### Inferences
- Design implications for Tempo:
  1. Offer an explicit "move / swap easier / skip" choice instead of silent drops.
  2. Explain every change.
  3. Make each notification type opt-out, and default to a minimal set.
  4. Let readiness override the plan and say so ("Plan said intervals; readiness low, swapped to easy").

### Gaps
- Reddit threads (r/whoop, r/ouraring, r/Garmin, r/AppleWatch) could not be fetched. Specific Whoop and Oura complaint themes, such as Whoop Strain Target being unattainable on low recovery or Oura nudges seen as nagging, are not sourced here and should be verified.
- I found no review data on Runna's or Fitbod's notification volume.
