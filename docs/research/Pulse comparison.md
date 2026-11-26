# Pulse comparison

As of Nov 26, 2026 · Proposal for the owner. Nothing here is decided until it lands in `docs/decisions.md`.

Subject: **Pulse** (`github.com/adityaongit/pulse`, read at its default branch on 26 Nov 2026), an open-source recovery, strain and sleep app. Sources: its README, `AGENTS.md`, the 12 algorithm specs in `docs/algorithms/`, the scoring code in `src/core/`, the UI spec (`docs/design/spec.md`, ~400 KB), its coach and push code, and its phone screenshots. Every Pulse number quoted below was read from those files.

## Summary

Pulse is Tempo's closest open-source twin: same three scores (Sleep, Recovery, Strain 0–21), same red/yellow/green bands at 34 and 67, a biological age from hazard ratios and the Gompertz rule, a journal whose impact is measured on next-day recovery. It differs in almost everything around the scores:

| | Pulse | Tempo |
|---|---|---|
| What it is | Self-hosted **web app** (Next.js + Postgres in Docker), multi-user with invites and an admin panel; a Capacitor shell; a separate on-device Android app (Pulse Mobile, Health Connect) | Native **Flutter** app for iOS and Android, on-device first; E2E-encrypted sync planned on GCP |
| Data | **Google Health API** (Fitbit Air, Pixel Watch), pulled server-side over OAuth | Apple Health / Health Connect (any watch or ring), or the Mi Band 6 over BLE |
| Business | **PolyForm Noncommercial**, free, "not affiliated with WHOOP" | Commercial beta, freemium with Pro |
| Scoring origin | Recovery, strain, sleep, baselines, illness and readiness are a **port of noop** (another PolyForm NC project); its own models on top | Own engine, algo 12, audited in `Algorithm review.md` |
| Look | A deliberate copy of the leading strap's 2025 app (its spec says "copying the current … app") | Own design system |
| Coach | **LLM chat** with the user's own API key (Anthropic, OpenAI, Google, OpenRouter or a local model), tools over the user's data | **Rule-based adaptive coach**: goals, periodisation, picks, live workouts, strength progression |

**Where Tempo is ahead:** the plan (Pulse tells you how you are, Tempo tells you what to do and adapts the week), strength logging and progression, live workouts with GPS, Live Activity and widgets, iPhone and any Health-writing device, Tempo Age (groups, overlap by group, confidence %, ranges, blood PhenoAge), sleep need and debt that don't inflate, the journal's ridge regression, the validation harness, and privacy that doesn't need a server you run yourself.

**Where Pulse is ahead:** HR-only stress for any watch (Tempo shows none to Health users), per-input points on Recovery, an evening forecast of tomorrow's recovery, an illness signal that stands down after alcohol, sauna or travel, a zone "typical range" on each workout, three bedtime choices with weekday/weekend wake times, a demo mode with 180 seeded days, and a consistent kit with five honest metric states. Also web and desktop, which Tempo doesn't target.

**Recommended:** take nine ideas (§7), all pure Dart or small UI work, none needing a schema change except one. Don't take its look, its Energy Bank, its ACWR "sweet spot", its 8 h sleep-need floor or its server-side LLM coach (§8).

**Licence rule.** Pulse is PolyForm Noncommercial and its scoring is ported from noop under the same licence. Tempo is commercial, so we may not copy or translate either codebase. Treat it exactly like Gadgetbridge: read it to understand the method, then write our own Dart from the cited papers. Everything recommended below rests on a published paper or a plain idea, never on their constants as such.

---

## 1 · Product and platform

| | Pulse | Tempo |
|---|---|---|
| Install | Self-host: Google Cloud project, Health API, OAuth consent screen, Docker, an HTTPS hostname (Tailscale suggested). Or the Android-only Pulse Mobile from GitHub releases | App Store / Play (beta B0–B6) |
| Platforms | Browser (PWA, phone to laptop, three nav forms: tab bar, rail, sidebar), Android shell, iOS shell pointing at a server | iOS and Android native |
| Devices | Fitbit Air / Pixel Watch through Google; Health Connect in Pulse Mobile | Anything writing Apple Health / Health Connect; Mi Band 6 direct |
| Accounts | better-auth, username or email + password; invite / open / closed sign-up; owner + admins | B1 without accounts today; accounts planned (G0–G4) |
| Where data lives | Postgres on the owner's server, plaintext to whoever runs it; 4 MB a person a month | On the phone; sync E2E encrypted, server never sees plaintext |
| Notifications | Web push: "Recovery ready", "can't sync", "Your brief is ready" | Field-tuned coach nudges, wind-down, health alert, journal reminder, Live Activity, ongoing notification |
| Testing | Vitest golden tests beside every algorithm, Playwright journeys, a per-user isolation test, parity tests against noop | Pure-Dart unit tests, golden packet tests, backtest CLI, validation harness (A0) |

The two are aimed at different people. Pulse suits a technical Fitbit owner who wants the strap's experience without paying for it and is happy to run a server for family. Tempo suits anyone with a phone and a watch or band who wants to be told what to do today.

## 2 · Algorithms, side by side

### 2.1 Recovery

| | Pulse (noop port) | Tempo (algo 12) |
|---|---|---|
| Inputs and weights | HRV **0.55**, resting HR 0.20, sleep performance 0.15, respiration 0.05, skin temp 0.05 (symmetric: any deviation hurts), overnight RHR slope 0.05, yesterday's effort vs normal 0.05 | HRV 0.25 + HRV 7-night trend 0.10, resting HR 0.25, last night's sleep 0.15, 7-night sleep balance 0.10, load 0.15; breathing, SpO₂ and temperature as a penalty only (≤ 15) |
| Baseline | Winsorized EWMA, σ = 1.253 × spread, floor spreads per metric, outliers rejected once settled | 30-day median and MAD, minimum spread, z capped at ±2.5 |
| Curve | Logistic, k 1.6, centre −0.2: **an average night scores ~58 %** | Logistic, slope 1.5: an average night scores 50 % |
| Gate | 7 accepted HRV nights; confidence calibrating / building / solid | Provisional at 4 nights, full at 14 |
| Explanation | Each input shows its value, baseline ± spread, a slider and **"−10 pts"**: the score minus the score with that input held at normal | Each input shows its value and "normal x"; only the vitals penalty is in points |

**Reading.** Pulse is HRV-dominated: one noisy HRV night swings the score more than any other input can pull it back. Its load term is 5 % and has no multi-night sleep term, so a hard week followed by a normal-HRV night reads green, which is the gap our Recovery v2 closed. Its 58 % midpoint makes an ordinary day look a little better than ours; neither is wrong, but a user comparing the two apps on the same night will see Pulse higher. The marginal-points display is the part worth taking (§7, P2).

### 2.2 Strain

| | Pulse | Tempo |
|---|---|---|
| Load | Edwards TRIMP: minutes × zone weight 1–5 by %HRR (50/60/70/80/90 %); Banister optional | Banister TRIMP per minute above a 30 % HRR floor, sex-specific |
| Scale | Log map onto 0–100 ("Effort", denominator = 24 h in zone 5), shown × 21/100 | 21 · (1 − e^(−TRIMP/40)) |
| HR max | 99.5th percentile of all HR history once 600 samples exist, else Tanaka | Set or Tanaka; rises only after two sustained minutes above it, ≤ 5 bpm a day |
| Target | 28-day mean strain × band multipliers (green 1.0–1.25, yellow 0.8–1.0, red 0.5–0.75), capped when ACWR > 1.3, lifted 10 % when < 0.8; cold start 14–18 / 10–14 / 6–10 | Six recovery tiers, then sized to chronic TRIMP × factors, nudged by the 7:28 ratio; a rest cap when overreaching and under 50 % |

**Reading.** Edwards zones are coarse steps: 69 % and 61 % HRR count the same. Banister is continuous and our choice holds. Their percentile HR max is more robust than our old "any minute" rule but still lets a run of cadence-lock minutes in; our sustained-minute rule is stricter. Their target idea (your own mean × band) is close to what we arrived at in V3. The difference is the framing: Pulse still calls ACWR 0.8–1.3 the "sweet spot" in its reports; `Algorithm review.md` §6 explains why we walked that back.

### 2.3 Sleep

| | Pulse | Tempo |
|---|---|---|
| Score | Duration vs need 50 %, efficiency 20 %, **restorative (deep + REM share, with a deep floor) 20 %**, regularity (SRI) 10 % | Duration vs base need 50 %, bedtime vs your median 20 %, continuity 15 %, efficiency 10 %, time to fall asleep 5 %; wrist stages kept out |
| Need | Upper quartile of your nights, **floored at 8 h** (9 h under 18), capped 9.5 h | Median of the nights after which HRV and resting HR were best, 7–9 h |
| Debt | 14-night ledger, carry 0.55, cleared under 10 min | Against the base need, half-life 4 nights, surplus repays half, cap 2 h |
| Tonight | Need + 0.05 h per strain point above your 28-day mean + 0.2 × debt − naps; three bedtimes at **100 / 85 / 70 %** of need ("Peak / Perform / Get by"); wake time = median of the last 14 weekday or weekend wakes, whichever tomorrow is; in-bed time from your median efficiency | Base + 0.5 × debt + 0.01 × yesterday's strain; one bedtime; sleep type and the 21-day sleep plan |
| Regularity | SRI (Phillips 2017), 7 noon-to-noon days, naps count, unworn days skipped | SRI and social jetlag (E1) |

**Reading.** Two choices in Pulse would fail our own review. The 8 h floor on need means a healthy 7 h sleeper is always "short", the same symptom we fixed as loop L1. And 20 % of the score rests on wrist-estimated deep and REM, which consumer devices stage poorly. What's good: the three bedtime options and the weekday/weekend wake split (§7, P6).

### 2.4 Stress and energy

| | Pulse | Tempo |
|---|---|---|
| Stress | Every **still, awake minute** (no steps within ±2 min, not in a workout or sleep) scored 0–3 from how far its HR sits above your daytime resting HR (10th percentile of hourly still-minute means, folded into a baseline); logistic so a calm minute reads ~0.3 | The band's own stress index only. For Health users: "Not available", the screen is hidden |
| Energy | **Energy Bank** 0–100: starts at 0.6 × recovery + 0.4 × sleep, drains per awake minute, per zone weight and per high-stress minute, refills on calm minutes and naps; top 3 drains named. Their own doc says it is a heuristic tuned so a demo day ends at 15–40 | None (the "beating heart" and day timeline show the day) |

**Reading.** The stress method is the most useful thing in Pulse for us: it needs only minute HR and steps, which every Health source has. The open question is HR density. Fitbit writes HR every few seconds; an Apple Watch outside a workout writes roughly every few minutes, so many minutes would be blank (TODO(verify) on both phones before promising it). Energy Bank is an invented curve; we shouldn't ship a number with no evidence behind it.

### 2.5 Health monitor and illness

| | Pulse | Tempo |
|---|---|---|
| Daily view | **"N of 5 in range"** for resting HR, HRV, respiration, SpO₂, skin temp; range = baseline ± 2σ (or Google's own personal range); SpO₂ low bound never under 95 % | Body signals on Recovery; Today shows a card only when two or more are off |
| Illness | ≥ 2 signals at z ≥ 2 to raise; per-signal cap; **damped (× 0.45) when the journal says alcohol, sauna or travel** | Two or more off → rest day and health alert |
| Heart rhythm | ECG readings and irregular-rhythm notifications listed with a not-a-diagnosis line | None |

**Reading.** Both use corroboration. Pulse's confounder damping is a cheap way to stop a false "you may be getting ill" the morning after drinks (§7, P3). The "5 of 5 in range" tile gives a reassuring daily answer; our calm-by-default Today only speaks when something is off. Keep ours, but offer the count on the Recovery screen.

### 2.6 Biological age

| | Pulse Age | Tempo Age |
|---|---|---|
| Inputs | 9: sleep duration, SRI, zones 1–3, zones 4–5, strength minutes, steps, VO₂ max, resting HR, lean mass (FFMI, needs weight + body fat + height) | 13 levers in groups, plus blood (PhenoAge) |
| Overlap | One global shrink 0.75, then × 9/n for missing inputs (needs ≥ 5 of 9) | Per-group shrink 1/(1 + (k − 1)ρ), cross-group shrink |
| Reference | A fit person (FRIEND 75th percentile VO₂ max, 10k steps), so most people read older | Typical (50th percentile) adult |
| Output | Age ± 15 y, Pace of Aging (30-day vs 6-month, −1 to 3×), weekly | Age with range and confidence %, pace, focus lever, weekly cap |
| Fitness | FRIEND percentile shown as Poor → Superior | FRIEND 50th percentile as reference |

**Reading.** Ours is more careful. The × 9/n renormalisation inflates whatever is present when inputs are missing, and a "fit" reference makes the headline negative for most users. Two things worth borrowing: the **lean mass lever** from Health weight and body fat, and the FRIEND **category** ("Good, 60th percentile for your age") as a plain fitness line (§7, P8).

### 2.7 Journal and behaviour impact

| | Pulse | Tempo |
|---|---|---|
| Entries | 9 yes/no tags by default (alcohol, late caffeine, late meal, screen in bed, meditation, stretching, sauna, travel, illness), user tags, plus in-app logs for water, food, weight, mood, symptoms, cycle | ~100-item catalogue with quantities, automatic entries from data, quick tags on the timeline, experiments |
| Method | Plain yes-minus-no difference on next-day recovery, HRV z and sleep, **90 % bootstrap CI**, ≥ 5 days each side, 90-day window | **Ridge regression** across behaviours (adjusts for those that co-occur), seeded 80 % bootstrap range |
| Automatic | "Behaviour chips" on Recovery from data: 86 %+ sleep, 7+ strain, workout before 08:00, wake within 30 min of your median, each marked helped / hurt / neutral from history | Automatic entries in Journal v2 |

**Reading.** Tempo's method is stronger: a plain difference credits alcohol with what the late night did. Nothing to take here except the idea of showing data-derived chips right on Recovery ("what yesterday did"), which we already partly do with automatic entries.

### 2.8 Smaller models

- **Recovery forecast** (evening): recent mean + nudges for today's strain, tonight's planned sleep and reversion to the mean, with a ± band. Tempo has no evening estimate of tomorrow. (§7, P4)
- **Zone typical range** on a workout: the 25th–75th percentile of your share in each zone across the last 30 days of the same sport, from 3 sessions up. (§7, P5)
- **Reports**: ISO week and calendar month, deltas vs the previous period, band counts, best and worst day, top 3 clear journal effects. Tempo has the week in review; a month view is cheap.
- **HR recovery** after workouts: both have it.

## 3 · Features

| Area | Pulse only | Both | Tempo only |
|---|---|---|---|
| Scores | Energy Bank, HR-only stress, recovery forecast, Pace of Aging dial | Recovery, Strain, Sleep, bio age, cardio load, HR recovery, SRI | Strain target sized to chronic load, sleep type, social jetlag, brisk minutes, longest still stretch, feel vs recovery |
| Planning | Strain target, three bedtimes | Bedtime | Goals, blocks, periodisation, taper, week template, picks, injury mode, pause, move or skip, tune-ups, next goal |
| Training | Activity list, zones with typical range | Workouts from the source, zones | Live workout (GPS, pace, Live Activity, ongoing notification), strength log with progression and muscle freshness, saved routines, form videos, quick start, manual activities |
| Health | Health Monitor "N of 5", ECG / irregular-rhythm list, symptom log | Body signals / illness flag, weight, cycle | Blood tests with ranges, PhenoAge, food targets from Health energy, weight rate |
| Logging | Water, food, weight, mood, symptoms, period and ovulation **typed into Pulse** (also through the coach with an approve tap) | Journal | Quick tags, experiments, workout notes and reflections |
| Coach | LLM chat, morning brief push, "About you" notes | | Rule-based coach with reasons, coach moments, week story, insights log |
| Views | My Dashboard (pick and order metric rows), web and laptop layouts, monthly report, streak counter | Trends, calendar, week review | Day timeline, widgets, share cards, weather wash |
| Ops | Self-host, multi-user, admin panel, invites, demo mode with 180 seeded days | Backups / export | Mi Band BLE, data health, source check, "What Tempo uses", "How Tempo plans" |

## 4 · Journeys

Pulse's spec lists ten journeys; set against Tempo's (`User flow and journey.md` §9):

| Moment | Pulse | Tempo |
|---|---|---|
| Morning | Open → three dials animate → one insight card (swipe for more) → monitors → "My Day". Answers **how am I** | Today leads with the day's call and the session. Answers **what do I do** |
| Workout | Strain dial → activity → zones with typical range, HR recovery | Start from the plan or (+), live screen, rescoring on finish, reflection |
| Evening | "Tonight's sleep" card with Peak / Perform / Get by | Wind-down notification naming tomorrow's key session, Tonight line |
| Past day | Date pill or calendar on any screen, `?d=` carries across screens | Calendar and earlier days (D1) |
| Long run | Health tab → Pulse Age orb → factor sheets | Progress → Tempo Age, focus lever |
| Illness | Alert on Home, "3 of 5 out of range", vital sheet with shaded normal | Rest card, health alert, plan eases |
| Journal | Round centre button = Check in, from any screen | (+) sheet, quick tags, morning "Yesterday, quickly" |
| First run | Google Cloud setup or install the Android app; "Importing history 0 of 180 days" banner; dials show reasons until enough nights | Health-first onboarding, source check, first-import backfill gives Recovery on day 1 |
| Token lost | Red sync dot, "Reconnect Google" banner on every screen | Source check / data health |

Pulse has no weekly arc beyond the report, no goal, and nothing that changes tomorrow because of today. Its strongest journey is **browsing the past**: one date switcher, the same on every screen, and links that keep the day.

## 5 · UX and UI

**What Pulse does well**

- **One kit, five honest states.** Every metric renders value, provisional, calibrating, no data (with a reason code) and loading through one component; it never shows a made-up number. We do this screen by screen.
- **The score never scrolls away.** When the dials leave the screen, three mini rings stay in the header.
- **Explanations as small centred cards**, not tall sheets.
- **Numbers carry their baseline** everywhere: "Baseline 54 ± 8 ms", "−10 pts".
- **Responsive by CSS only**: one nav, three forms (tab bar, rail, sidebar).
- **Demo mode** makes every screen reviewable without a device, and its screenshots are regenerated from it.

**Where it is weaker**

- **It is a copy.** Dark only, three dials, uppercase tracked labels, glass tab bar and round action, "Peak / Perform / Get by", "My Day", "Your daily outlook": the spec cites the strap's screens as the authority on every look question. Fine for a free hobby project; a trade-dress risk for a paid one. We stay off it.
- **Home is long and numbers-first**: dials, insight, two monitors, My Day, outlook, activities, journal week, Energy Bank, tonight's sleep, nine dashboard rows, a chart, week review. That is the 15-block Today we cut down in F1 and D4–D5.
- **No decision.** The only "do" on Home is the strain target and an insight; there is no session, no reason, no change to the week.
- **Setup is for engineers.** A Google Cloud project, a consent screen and Docker before the first score. Google expires test grants every 7 days.
- **Dark only.** Their spec rules out a light theme.

## 6 · Engineering practices worth noting

- Every algorithm doc follows one shape: code path, flow diagram, formula, inputs with units, constants marked *cited* / *spec* / *tunable*, edge rules, worked examples that are also tests, sources. Our docs have the content; the fixed shape makes them easier to audit.
- **Causality rule**: a day's score may depend only on that day and earlier days; a later night never changes history. We recompute on algo change, which is right, but we should state and test causality explicitly.
- **Per-user isolation test** over every screen query: relevant to us only once the backend exists (G-phases), then worth copying as a test idea.

## 7 · What to take

In order of value for effort. Each is our own implementation from the cited source, not from Pulse's code.

| # | Item | Why | Work |
|---|---|---|---|
| P1 | **HR-only stress for Health users**: score still, awake minutes from HR vs your daytime resting HR (your own baseline of quiet daytime HR), 0–3 or low/medium/high, hourly bars. Turns the hidden Stress screen on for every watch user | Our biggest visible gap vs Pulse, the strap and Garmin | Pure Dart in `scoring`; gate on HR density (minutes with HR per waking hour) and say "not enough heart-rate readings" when the watch samples too rarely. TODO(verify) Apple Watch and a Health Connect watch's daytime HR density first |
| P2 | **Recovery inputs in points**: each row shows "−10 points" = today's score minus the score with that input at your normal | Answers "why is it 39?" in one glance; we already show points for the vitals penalty | UI + a pure function over `recoveryScore`; note in copy that rows don't add up exactly |
| P3 | **Illness signal stands down for confounders**: when the journal (or quick tags) says alcohol, sauna, late heavy meal or travel across time zones, body signals still show but the rest call and health alert are held, with "may be the drinks" | Fewer false alarms the morning after; Mishra 2020 and Radin 2020 both note alcohol as a confounder | `everyday.dart` / `nudges.dart`; no schema change |
| P4 | **Tomorrow's recovery, tonight**: an evening estimate with a band ("likely 55–70 if you're in bed by 22:45"), from the recent mean, today's strain against normal and tonight's planned sleep | Gives the wind-down notification a reason the user feels | Pure Dart, validated by the A0 harness against the next morning before it ships |
| P5 | **Typical range on workout zones**: shade the middle half of your last 30 days of the same sport | Makes a workout's zones mean something without a lecture | Activity detail only |
| P6 | **Bedtime options**: full need, 85 %, 70 %, each with its bedtime; wake time from your weekday or weekend median depending on tomorrow | Gives a choice on late nights instead of one bedtime that's already missed | `sleep_plan.dart` + the Tonight line |
| P7 | **Demo mode**: a build flag or hidden switch that fills the store with 180 seeded days (illness week, training block, short-sleep week) | Store review (both stores need to see the app working without a watch), screenshots, design review, widget tests | Seed generator in `tools/`; never on in release builds by default |
| P8 | **Lean mass lever and fitness category**: FFMI from Health weight + body-fat % + height (Sedlmeier 2021), and "Good · 60th percentile for your age" from the FRIEND table we already cite | Uses data many scale owners already have | `longevity.dart`, algo bump; body fat is a new read-only Health kind (TODO(verify)) |
| P9 | **Mini rings in a collapsing header** on Today, and one day switcher shared by the day screens | Score stays visible; past days are one gesture | UI only |

Also cheap: a **month** view in the week-in-review screen, and the fixed doc shape (§6) for new algorithm notes.

## 8 · What not to take

- **The look.** Copying the strap's chrome and names is a legal and brand risk for a paid app and adds nothing we need.
- **Energy Bank.** No published model; constants tuned to make a demo day end between 15 and 40. It would also be a fourth headline number against F1's "one voice".
- **ACWR "sweet spot" framing** in reports or targets (`Algorithm review.md` §6).
- **An 8 h floor on sleep need** and **deep/REM share in the sleep score**: both conflict with our algo 10 findings.
- **HRV at 0.55 of recovery**: too volatile on one night; Recovery v2's split (tonight + 7-night trend) is the better answer.
- **A server-side LLM coach.** It would send plaintext health data to a model provider, which our non-negotiables forbid without an E2E-compatible design and a `docs/decisions.md` line. If we want "ask about your data" later, options are an on-device model, or a per-question, user-read, user-sent summary (the same pattern as feedback). Not for the beta.
- **In-app food logging.** D3 deliberately left meal logging to the apps that write Health.

## 9 · Open questions for the owner

1. P1 depends on daytime HR density. Check one ordinary day on the iPhone + watch and on the Android phone + watch: how many minutes per waking hour carry HR? Under ~20, the stress view is better left off than shown thin.
2. P7: is a demo mode acceptable in release builds behind a hidden switch (useful for store review), or debug builds only?
3. Should Recovery show "N of M in range" every day (Pulse style), or stay calm until something is off (current D5 rule)?

## Sources

Pulse repository, default branch read 26 Nov 2026: `README.md`, `AGENTS.md`, `LICENSE`, `NOTICE`, `docs/algorithms/*.md`, `docs/design/spec.md` (§1, §4.2, §7.1, §7.21, §8), `docs/technical-details.md`, `docs/plans/future-plan.md`, `src/core/scoring/{recovery,strain,sleep,illness,forecast,drivers,confidence,trainingLoad}.ts`, `src/server/{push,journalTags}.ts`, `src/server/coach/*`, `docs/screenshots/phone-*.png`. Papers are those cited in §2 and in Pulse's own specs (Phillips 2017, Windred 2024, Kaminsky 2015, Sedlmeier 2021, Gabbett 2016, Mishra 2020, Radin 2020). No code was copied.
