# Notification and Coaching UX for Tempo Coach

Source note: academic sites (jmir.org, academic.oup.com, pmc, arxiv, dartmouth) were blocked by the egress proxy during this research. Their findings below come from search-result abstracts and snippets of the primary papers, not full-text reads. Figures are quoted as reported in those abstracts. Industry "opt-out per weekly volume" statistics are widely repeated by aggregators and their original methodology could not be verified, so treat them as directional only.

## 1. Frequency vs engagement / opt-out; habituation; recommended caps

### Takeaway
A single well-timed notification has a large short-term effect: about 3.5x the odds of opening the app in the next hour (Drink Less). But in HeartSteps, the effect of activity prompts decayed by about 2% per day and could no longer be told apart from zero by about day 28. "More" therefore buys little. The evidence supports a small daily budget (about 1–3 pushes), with intervention "dose" treated as a cost.

### Cited Findings
- **HeartSteps v1 (42-day MRT, n=37).** Up to 5 decision points per day; a suggestion was sent with p=0.6. On average, a suggestion raised the 30-minute step count by 14% (+35 steps). On day 1 the effect was +66% (+167 steps), and it fell linearly by about 2% per day until it was no longer distinguishable from zero around day 28. Walking suggestions: +24% on average, +107% (+271 steps) at the start — [Klasnja et al. 2019, Ann Behav Med](https://academic.oup.com/abm/article/53/6/573/5091257); [NIH ODP slides](https://prevention.nih.gov/sites/default/files/2019-07/Klasnja_Using%20Micro%20Randomized%20Trials%20to%20Optimize%20the%20Design%20of%20Mobile%20Health%20Interventions%209%20July%202019.pdf)
- **Drink Less MRT** (one 8 pm notification per day, first 30 days). Getting a notification versus none raised the probability of opening the app in the next hour 3.5-fold (95% CI 2.91–4.25). A bank of 30 novel messages did about as well as the one standard message. The notification effect did not change significantly over time. 50% of users had disengaged by day 22 — [Bell et al. 2023, JMIR mHealth uHealth](https://mhealth.jmir.org/2023/1/e38342); [LSHTM PDF](https://researchonline.lshtm.ac.uk/id/eprint/4670198/1/Bell-etal-2023-How-notifications-affect-engagement-with.pdf)
- **Bidargaddi et al. MRT** (1,255 users, 89 days). A tailored health push made users 3.9% more likely to engage in the next 24 hours. The effect was largest at mid-day on weekends — [Bidargaddi et al. 2018, JMIR mHealth uHealth / PubMed](https://pubmed.ncbi.nlm.nih.gov/30497999/)
- **Personalized HeartSteps** models "dosage": recent intervention load reduces the benefit of the next prompt. It sends only if the posterior advantage exceeds a positive threshold, to capture negative delayed effects. The authors note that "too much intervention can gradually become part of the problem rather than part of the solution" — [Liao et al., Personalized HeartSteps](https://pubmed.ncbi.nlm.nih.gov/34527853/); [Springer ML 2024 follow-up](https://link.springer.com/article/10.1007/s10994-024-06526-x)
- **Industry benchmarks.** Health & fitness push opt-in rate is 43.2% on Android and 33.5% on iOS. Average monthly pushes per user in the medical/health/fitness category rose from 144 (2023) to 151.4 (2024) — [OneSignal Mobile App Benchmarks 2024](https://onesignal.com/mobile-app-benchmarks-2024)
- **Frequently cited opt-out figures** (origin unclear, likely older Localytics surveys): "46% opt out at 2–5 msgs/week"; "1 weekly push → 10% disable". Repeated via aggregators — [MobiLoud](https://www.mobiloud.com/blog/push-notification-statistics/); [Business of Apps](https://www.businessofapps.com/marketplace/push-notifications/research/push-notifications-statistics/). Methodology not verified.
- **Apple HIG:** "Avoid sending multiple notifications for the same thing, even if someone hasn't responded… people may turn off all notifications from your app" — [Apple HIG Notifications](https://developers.apple.com/design/human-interface-guidelines/components/system-experiences/notifications/) (via search snippet)
- **Android guidance:** don't send generic engagement messages ("Haven't seen you in a while!"), rating requests, syncing/background status, recovered errors or greetings. Match the importance level to the real urgency, because "disguising unimportant notifications as urgent creates alarm fatigue" — [Android Notifications design guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)

### Inferences
- Proposed Tempo cap: at most 2 proactive coach pushes per day by default (Morning Brief plus at most one contextual nudge), and at most about 8–10 per week. Event-driven items the user explicitly opted into (smart alarm, band battery low, workout auto-detected → RPE) count separately but are rate-limited too. A user setting can raise or lower the cap.
- Expect novelty decay. Rotate content, and tie each nudge to a real data change (a new signal) rather than a schedule, because content that carries information resists habituation better. This is a hypothesis: Drink Less found novel wording made no difference, which suggests relevance and timing matter more than wording variety.
- Treat each push as having a cost. Keep a rolling "dose" (pushes in the last 24h and 7d) and require a higher expected benefit when the dose is high.

### Gaps
- No rigorous public data was found that links pushes per day to opt-out specifically for wearable coaching apps (Whoop/Oura/Garmin don't publish this).
- The original methodology behind the "46% opt out at 2–5/week" figure could not be verified.

## 2. Timing: receptivity, availability, quiet hours, learning best times

### Takeaway
Receptivity depends on context and on the person. Never interrupt during sleep, driving or an active workout ("unavailable"). Learn each user's responsive windows from their own open and act latencies. Defaults: morning brief just after wake (detected from the band's sleep end), evening wind-down before the learned bedtime, mid-day for activity nudges.

### Cited Findings
- **HeartSteps availability rules.** The user counted as unavailable if walking or running, within 90 s of finishing an activity bout, or driving (phone activity recognition). The design assumed users would be available about 70% of the time. Decision points sat at 5 user-specified times: morning commute, mid-day, mid-afternoon, evening commute, after dinner — [Klasnja 2019](https://academic.oup.com/abm/article/53/6/573/5091257); [Personalized HeartSteps](https://www.researchgate.net/publication/340014346_Personalized_HeartSteps_A_Reinforcement_Learning_Algorithm_for_Optimizing_Physical_Activity)
- **Künzler et al. 2019 (IMWUT, 6-week Ally app MRT).** Receptivity (just-in-time and later responses) was associated with both intrinsic factors (device type, age, personality) and contextual ones (time of day, battery level, device interaction, physical activity, location). Android users and older users were more receptive — [Künzler et al. 2019 IMWUT](https://www.researchgate.net/publication/337909002_Exploring_the_State-of-Receptivity_for_mHealth_Interventions_Proceedings_of_the_ACM_on_Interactive_Mobile_Wearable_and_Ubiquitous_Technologies_IMWUT_34_Article_140)
- **Mishra, Künzler et al. 2021 (IMWUT).** Machine-learning models trained on this context data detected receptive states in the wild and improved response rates over a random-time control (follow-up study) — [Detecting Receptivity for mHealth Interventions in the Natural Environment](https://doi.org/10.1145/3463492)
- **Bidargaddi 2018.** Tailored pushes worked best at mid-day on weekends — [PubMed](https://pubmed.ncbi.nlm.nih.gov/30497999/)
- **Mehrotra et al., CHI 2016** (pre-2018 but foundational; 10,372 notifications, 20 users). Response time and perceived disruption depend on presentation, alert type, sender relationship and the user's current task. Uninteresting or irrelevant notifications are mostly swiped away without being opened. People act quickly when the content is important, urgent or useful — [Mehrotra et al. 2016](https://pure-oai.bham.ac.uk/ws/files/29196179/Mehrotra_2016_CHI.pdf)
- **Apple:** Time Sensitive interruptions are only for events "happening now or will happen within an hour". They break through Focus and scheduled summary; users can disable them — [Apple HIG via search](https://developers.apple.com/design/human-interface-guidelines/components/system-experiences/notifications/); [WWDC21 "Send communication and Time Sensitive notifications"](https://developer.apple.com/videos/play/wwdc2021/10091/)
- **Annual Review of Psychology** overview of JITAIs (state of the field, "where are we now") — [Annual Reviews](https://www.annualreviews.org/content/journals/10.1146/annurev-psych-121024-044244) (not read in full)

### Inferences
- Tempo has unusually rich availability signals from the band itself: asleep or in bed, live HR elevated or a workout in progress, and nap detection. Use these as hard "unavailable" gates. Add OS signals where possible: Android Do-Not-Disturb, driving activity recognition, iOS Focus (respected automatically unless Time Sensitive).
- Default quiet hours = learned sleep window ± 30 min, plus a user-editable window. Never send coaching pushes during quiet hours. Only the user-set smart alarm may fire then.
- Anchor the Morning Brief to the detected wake time (sleep end synced from the band) rather than a fixed clock. If no sync has happened, fall back to a time the user chooses.
- Learn per-user windows. Bucket the day into about 4–5 slots (HeartSteps-style). Track open/act rate and latency per slot × weekday/weekend, and pick slots with a simple bandit (see §5).

### Gaps
- Künzler's exact effect sizes per factor (e.g. % response by time of day) could not be extracted because the full text was blocked.
- No evidence was found specific to "during meetings". Calendar-based suppression is a reasonable inference, but it needs calendar permission and would conflict with the on-device/no-network goal only if a cloud calendar were used.

## 3. Content: actionable, personalised, positive, autonomy-supportive

### Takeaway
Each notification should give one data-based "why" plus one optional action, be short (Android: title ≤30 characters, body ≤40 before expanding), use invitational language ("could", "want to?") instead of "should/must", offer a choice, and never shame.

### Cited Findings
- **Android content rules.** Title max ~30 characters and single-line, most important information first, don't repeat the app name. Body max ~40 characters, previewing rather than repeating the title — [Android design guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **Autonomy-supportive language** uses "may/could/would" rather than controlling "should/must". In a 2x2 experiment (JMIR 2019), offering a choice raised effectiveness more than autonomy-supportive wording alone, especially for people with a high need for autonomy — [Altendorf et al. 2019, JMIR](https://www.jmir.org/2019/10/e14074/)
- **Self-determination theory meta-analysis** of techniques that promote autonomous motivation for health (Gillison et al. 2019) — [Health Psychology Review PDF](https://selfdeterminationtheory.org/wp-content/uploads/2019/03/2019_GillisonEtAl_HPR_MetaAnalysis.pdf) (not read in full)
- **Supporting autonomy is a prerequisite for autonomous motivation**, which predicts long-term achievement of health goals (Ng et al. 2012 meta-analysis) — [Ng & Ntoumanis 2012](https://selfdeterminationtheory.org/SDT/documents/2012-NgNtoumanis_PPS.pdf)
- **Mehrotra:** irrelevant content gets dismissed; useful or urgent content gets timely attention — [Mehrotra 2016](https://pure-oai.bham.ac.uk/ws/files/29196179/Mehrotra_2016_CHI.pdf)
- **Whoop pattern.** Strain Coach gives a daily strain target from morning recovery: for example, 85% recovery → target 14–18; 35% → keep strain under 10 with active recovery. Sleep Coach sets the bedtime from the day's strain. The AI coach adds context-aware nudges (hydration, timing, intensity) using location, weather and physiology — [Whoop support: AI Coach](https://support.whoop.com/s/article/How-to-Use-the-AI-Powered-WHOOP-Coach?language=en_US); [Whoop Sleep](https://support.whoop.com/s/article/WHOOP-Sleep?language=en_US); secondary: [liveworksleep](https://liveworksleep.com/whoop-app-features/)
- **Oura** flags possible illness symptoms when the body is "under strain" and nudges the user to pay attention — [humanwindow comparison (secondary)](https://humanwindow.com/oura-ring-vs-whoop/)

### Inferences (proposed Tempo copy rules)
- Template: **[signal] → [meaning] → [one optional action]**. Example: title "Recovery 41% · HRV down" / body "Easy day could help — want a Zone 2 plan?"
- Use second person and present tense. Allowed verbs: could, might, want to, try. Banned: should, must, failed, missed, lazy, "don't forget", "you haven't…", and exclamation-mark guilt.
- Always offer an easy "not today" so the user can decline without friction. Treat a dismissal as information, not failure.
- Frame things positively and around gains ("Banked 7h sleep — good base for a hard session"). Be neutral and non-alarming for low readiness. Leave out medical claims; illness-like signals use cautious wording ("your night HR ran 6 bpm above usual").
- Content needs to make sense on a lock screen. Hide sensitive health values on the lock screen by default (Android visibility PRIVATE with a public version; iOS hiddenPreviewsBodyPlaceholder).

### Gaps
- No primary source was found with Whoop, Oura, Garmin, Apple Fitness, Duolingo or Headspace push copy verbatim. Product teardowns found were secondary blogs.
- Evidence on loss vs gain framing specifically for wearable readiness messages was not found in this pass.

## 4. Actionable patterns: inline actions, snooze, quick RPE, deep links, grouping, digests, streaks

### Takeaway
Use 1–3 inline actions (Android allows up to 3 collapsed; iOS categories have similar limits), deep-link the tap to the exact screen, group same-type items under a summary, and prefer digests (morning brief / evening wrap-up) to many single pushes. Streaks drive retention but cause anxiety and abandonment after a break. If Tempo uses streaks at all, they should be forgiving (rest days count, automatic freezes) and never be push-nagged.

### Cited Findings
- **Android:** up to 3 actions when collapsed, 5–6 when expanded. Don't duplicate the tap action. Group same-type notifications under a parent summary, and make each child understandable on its own. Remove stale notifications. Tapping should navigate to the relevant UI — [Android design guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **Android channels** (8.0+): every notification belongs to a channel. Once created, the user owns the channel settings and the app cannot change them. Name channels descriptively and avoid too many — [Braze: notification channels](https://www.braze.com/resources/articles/what-are-notification-channels-anyway); [Android guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **iOS interruption levels** (passive / active / timeSensitive / critical) and the notification summary (iOS 15+). Passive notifications land silently. Choosing a level honestly builds trust — [OneSignal on WWDC21](https://onesignal.com/blog/ios-notification-changes-updates-from-apples-wwdc-21/); [WWDC21](https://developer.apple.com/videos/play/wwdc2021/10091/)
- **Streak downsides.** Long-streak users report anxiety, doing sessions while sick, and meaningless completions. Streaks can push ADHD and neurodivergent users toward avoidance and abandonment. Reported return rates after losing a short streak are very low (~0.9–1.4%); streak-freeze users keep streaks longer — [Yu-kai Chou on streak design](https://yukaichou.com/gamification-analysis/streak-design-gamification-motivation-burnout/); [The Decision Lab: Streak Creep](https://thedecisionlab.com/insights/consumer-insights/streak-creep-the-perils-of-too-much-gamification); [Klarity on ADHD](https://www.helloklarity.com/post/breaking-the-chain-why-streak-features-fail-adhd-users-and-how-to-design-better-alternatives/); [Trophy streak examples](https://trophy.so/blog/streaks-feature-gamification-examples). These are practitioner and vendor sources; the numeric claims are not peer-reviewed.

### Inferences (Tempo patterns)
- **Morning Brief** (1 push, Passive/LOW on Android, or Active if the user opts in): recovery, sleep, today's target strain, and one suggestion. Actions: [Open plan] [Swap to easy] [Snooze 1h].
- **Post-workout RPE**: triggered when the band detects a workout end. Body: "Hard 42-min run detected. How did it feel?" Actions: [Easy] [Moderate] [Hard]. A tap writes sRPE without opening the app, and the notification is removed after the answer or once stale (e.g. 6h).
- **Evening wind-down**: an optional bedtime suggestion about 45 min before the target bed time. Actions: [Got it] [Later 30m] [Not tonight].
- **Group** multiple pending items into one "Tempo" summary. Retract stale ones (an old morning brief once the next day starts).
- **Deep link** every notification and widget to its exact screen (e.g. `tempo://coach/today`, `tempo://workout/{id}/rpe`).
- **Streaks**: prefer "consistency" metrics (e.g. 5 of the last 7 nights in the sleep window) over break-on-miss streaks. Rest days never break anything. Never send "your streak is at risk" pushes.

### Gaps
- Exact iOS limits on visible action count were not verified in this pass. iOS shows actions on long-press, and Apple advises keeping them few.
- No peer-reviewed data on streak freezes in health (as opposed to language-learning) apps was found.

## 5. Adaptive suppression and learning from responses (bandits)

### Takeaway
Send only when the user is available and the expected benefit beats a threshold that rises with recent dose. Learn per-user slot preferences with Thompson sampling or a contextual bandit, and back off after ignored or dismissed pushes. HeartSteps is the template (5 decision points per day, availability gate, dose-aware threshold, Thompson sampling).

### Cited Findings
- **Personalized HeartSteps:** an online RL algorithm decides 5 times a day whether to send. The context includes prior intervention dose and recent activity. It uses Thompson sampling with a positive threshold instead of zero, to account for negative delayed effects (burden). Availability is checked first, with no send if walking or driving — [Personalized HeartSteps (PubMed)](https://pubmed.ncbi.nlm.nih.gov/34527853/); [ICML poster](https://people.seas.harvard.edu/~samurphy/seminars/Peng%20ICML%20poster%20June%202019.pdf)
- **"Did we personalize?"** (Machine Learning 2024) gives a resampling method to check whether an online RL algorithm actually personalised in HeartSteps — [Springer 2024](https://link.springer.com/article/10.1007/s10994-024-06526-x)
- **RoME (NeurIPS 2024):** a robust mixed-effects bandit for mHealth that pools information across users while personalising; motivated by learning notification timing from smartwatch context — [RoME NeurIPS 2024](https://proceedings.neurips.cc/paper_files/paper/2024/file/e7b3e34d118d1fc6135b0bcbf3254d58-Paper-Conference.pdf)
- **Adaptive bandit experiments in a mental-health texting system** (about 1,100 users) — [PMC 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11044947/) (not read in full)
- **Apple:** don't resend for the same thing if ignored — [Apple HIG](https://developers.apple.com/design/human-interface-guidelines/components/system-experiences/notifications/)

### Inferences (on-device Tempo algorithm, simple enough for pure Dart in `packages/scoring` or the app layer)
- **Outcome signal per push:** acted (inline action or deep-link tap) within 2h = 1, opened = 0.5, dismissed or ignored = 0. Optionally add a proximal behavioural outcome (e.g. bedtime adherence, workout matching the target).
- **Slot selection:** a Beta–Bernoulli Thompson sampler per (category × slot × weekday/weekend). Start from population priors (e.g. Beta(2,2)). This is small, explainable and fully on-device.
- **Backoff:** after 3 consecutive ignored pushes in a category, halve that category's frequency. After 5, pause it for 7 days and show an in-app card ("Coach nudges paused — turn back on?") instead of pushing. Reset when the user engages. Explicit "Not today" counts as engagement (respect plus feedback), not as ignoring.
- **Dose-aware gate:** send only if P(act) × value(category) > θ + λ·dose_24h. Hard caps sit on top.
- **Keep some randomisation** (e.g. 10–20% exploration, or HeartSteps-style randomisation probabilities clipped to [0.1, 0.9]) so the model keeps learning and the app can measure whether nudges help at all. Log every decision with its `algo_version`, which fits the project's derived-data rule.

### Gaps
- No published thresholds for "back off after N ignored" were found. The values above are design proposals, not evidence-based constants.

## 6. Platform guidelines and user control / accessibility

### Takeaway
Use OS-native controls (Android channels per category; iOS interruption levels plus in-app per-category toggles), ask permission in context after explaining the benefit, label urgency honestly, and give users clear per-category toggles, quiet hours and a global "pause coach".

### Cited Findings
- **Android 13+** requires runtime POST_NOTIFICATIONS permission. Describe the benefit first with contextual in-app UI. If the user dismisses that UI, don't show the system dialog — [Android guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **Android importance levels:** HIGH (sound + heads-up) only for time-critical items; DEFAULT for reminders; LOW (silent) for non-critical content; MIN for non-essential content — [Android guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **Lock-screen visibility:** public / private / secret per notification — [Android guide](https://developer.android.com/design/ui/mobile/guides/home-screen/notifications)
- **Users own channels** after creation and the app can't override them — [Braze](https://www.braze.com/resources/articles/what-are-notification-channels-anyway)
- **iOS:** Time Sensitive only for things happening now or within the hour; users can disable it; assign levels honestly — [Apple HIG](https://developers.apple.com/design/human-interface-guidelines/components/system-experiences/notifications/); [WWDC21](https://developer.apple.com/videos/play/wwdc2021/10091/)

### Inferences (Tempo channel map)
| Channel | Android importance | iOS level | Default |
|---|---|---|---|
| Morning brief | LOW | passive | on |
| Coach nudges (activity / recovery) | DEFAULT | active | on, capped |
| Bedtime / wind-down | DEFAULT | active | on |
| Workout RPE check-in | DEFAULT | active | on |
| Health alerts (e.g. elevated resting HR, possible illness) | DEFAULT | active (not Time Sensitive) | on |
| Smart alarm | HIGH / alarm | timeSensitive (or OS alarm) | user-set |
| Band status (battery, disconnected) | LOW | passive | on |
| Foreground sync service | MIN (ongoing) | n/a | required on Android |

- In-app settings mirror the channels, with toggles, quiet hours, a max-per-day slider (1–4), and "Pause coach for 1d / 3d / 1w" (this links to the existing pause mode).
- **Accessibility:** short, plain sentences. Don't encode meaning only through colour or emoji in notification text. Write numbers with units ("HRV 42 ms") so screen readers announce them sensibly. Haptics/sound follow the system.

### Gaps
- Material 3 guidance on notification-specific accessibility wasn't found as a distinct source.
- Apple HIG full text could not be fetched (the page renders client-side). Quotes come from search-indexed copies of the HIG.
