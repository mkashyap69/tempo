# Competitor teardown and next steps

As of Oct 16, 2026 · Proposal for the owner. Nothing here is decided until it lands in `docs/decisions.md`.

Subject: the leading iPhone health app built on Apple Health, called "the benchmark app" here. Sources: three of its product videos (Biological Age, strength logging, Journal), read frame by frame; its help center, blog and public feature board, read through search results (its domains are blocked from the dev container, so some help pages were seen only as snippets); third-party reviews.

## Summary

The benchmark app is an iPhone-only layer over Apple Health. Core is free; Pro ($99.99 a year) adds Biological Age, Health Records and the AI coach. It has three things we lack or do worse:

1. **Biological Age** is grouped (Sleep, Activity, Fitness, Lifestyle, Blood), shows a **confidence %**, corrects for **overlap between related inputs**, and takes **blood work** (PhenoAge).
2. **Strength logging** records every set (weight, reps, rest timer, plate calculator, supersets, 700+ exercises), tracks progression (e1RM, volume), and maps **muscle freshness**.
3. **Journal** has a catalogue of about 100 behaviours, **quantities** (caffeine mg, water ml, drinks), **automatic entries** from data, and an **impact %** on Recovery and Sleep.

What we already do better: Android and the Mi Band (the benchmark is iPhone-only, and Android sits at "planned (tbd)" on its own board), fully on-device and free, an adaptive coach with goals, periodisation and taper (the benchmark only lists periodisation as "planned (soon)"), today's picks sized to readiness, and an illness warning from body signals (the benchmark has sickness detection at "planned (soon)").

Recommended order: **J1 Journal v2 → L1 Tempo Age v2 → S1–S2 Strength log and progression → A9 algo → J2/S3 → roadmap extras.** All the scoring work is pure Dart and doesn't depend on the field gates still open (C1, C4, P1/P2, H2/H3), so it can run alongside them if the owner agrees.

## 1 · Biological Age

### What the video shows

- Hero: **23.3**, "6.4 years younger", a "+0.8 from last week" chip, a gauge spanning calendar age ±10 (19.7–39.7), "As of April 20", **"Next update in 2 days"** (it recalculates every Monday).
- **"83% confidence · High-quality age estimate with minor gaps"**, which opens an explainer.
- **Age Biomarkers**, five groups, each with a ring and "X years younger/older": Sleep 1.7 younger, Activity 1.2 younger, Fitness 4.5 younger, Lifestyle 1.7 *older*, Blood 9.6 younger.
- Expanding a group shows each biomarker on a min–max bar with its own years: Time Asleep 7h 34m (5–11 h) −0.1, Sleep Consistency 93 % −1.6, Steps 8.46k (0–16k) −0.1, Zones 2–3 111 min (0–300) **+0.4**, Zones 4–5 66 min −0.5, Strength Training …
- Biomarker detail: today's value and its years, chips to switch biomarker, a **28-day rolling average** chart (3M / 6M / 1Y) with an average line, "Reference range: < 60 female", a bar with the "Younger" zone.
- **Other Biomarkers** (tracked, not in the age): HRV baseline "Increasing · 61.3 ms", resting HR "Good · 56.1 bpm". "Edit" picks which ones show.
- An "Ask … anything" AI bar sits over every screen.

### How it is calculated

- Each factor is compared with **healthy-ageing benchmarks adjusted for age and sex**, and **published hazard ratios** turn the gap into years. Example: steps subtract years from 8,000 a day under 60 and from 6,000 at 60+, and resting HR is +9 % mortality per 10 bpm (Zhang 2016).
- **Covariance adjustment**: correlated factors (resting HR and VO₂ max, lean mass and strength training) are moderated so they aren't counted twice, so group years don't add up neatly to the total.
- **Blood** uses Levine's 9-marker **PhenoAge**. Results under 6 months old count fully, and older results count less. If a heavy marker (RDW, MCV) is missing, the blood age is left out rather than guessed.
- **Confidence** comes from completeness and recency. Physiological factors need ≥ 20 days of data in the last month.
- Weak spot: users report implausible results (a 27-year-old shown as 14.5). It shows a single precise number with no range.

### Where Tempo Age stands

`scoring/longevity.dart` already uses the same approach: hazard ratios turned into years with the Gompertz rule (8 · log₂ HR), 13 levers, a 1-year-a-week change cap, pace of ageing and a focus lever. Gaps:

| Gap | Why it matters |
| --- | --- |
| **Double count (bug).** VO₂ max is *derived from resting HR* (`longevity_service.dart:293`, Uth formula) and resting HR is also a lever | A drop in resting HR from 65 to 55 earns ~1 year from the RHR lever and ~3.7 more through VO₂ max: about 4.7 years from one change |
| No overlap adjustment between steps and active minutes, or between sleep regularity and duration | Total too extreme for active people |
| Confidence is on/off ("calibrating") | No sense of how solid the number is |
| No groups | 13 rows are harder to read than 5 groups |
| Zone 2+ minutes in one lever | The benchmark splits moderate and vigorous; vigorous minutes count about double (WHO 2020) |
| No blood, no measured VO₂ max from Health | Missing the most predictive inputs a user may already have |
| Resting HR reference 65 for everyone | Not adjusted for age and sex like the others |

### Plan · L1 Tempo Age v2 (algo bump)

1. **Fix the double count.** When VO₂ max is derived from resting HR, drop the RHR lever (or give it a weak 0.3 weight). Read **measured VO₂ max** from Apple Health / Health Connect when present (new kind, TODO(verify)) and prefer it.
2. **Overlap shrink.** Sum log-hazards inside each group, then scale the group by 1/√(1 + (k−1)·ρ) with ρ ≈ 0.3–0.5 per group (a starting value; document each ρ). Unit tests: a perfect profile can't beat the old single-lever caps by more than X.
3. **Groups:** Sleep (duration, regularity, breathing) · Activity (steps, moderate, vigorous, strength) · Fitness (VO₂ max, RHR) · Lifestyle (smoking, alcohol) · Body (BP, waist) · Blood (PhenoAge). Each gets a ring and its years.
4. **Confidence %** = Σ (lever weight × coverage over 30 days × recency) ÷ Σ (all lever weights), with ≥ 20/30 days to count as full coverage. Show "83 % · minor gaps" and what would raise it ("add a blood test", "wear at night").
5. **Show a range, not false precision:** "31.4 (29.8–33.1)", with the width from confidence and each lever's evidence strength. This is our answer to the "27 → 14.5" problem.
6. **Split activity** into moderate (Zone 2–3) and vigorous (Zone 4–5) minutes, counted as moderate + 2 × vigorous against the 150/300 targets.
7. **PhenoAge from manual blood entry** (albumin, creatinine, glucose, CRP, lymphocyte %, MCV, RDW, ALP, WBC). The formula is published (Levine 2018), so we write it ourselves in pure Dart and golden-test it against the paper's examples. Full weight under 6 months old, linear decay to 0 at 24 months; leave it out if any marker is missing. New append-only table `lab_results`.
8. **Biomarker detail:** min–max bar with a "younger" zone, a 28-day rolling chart over 3M/6M/1Y, and the reference for your age and sex. Add "Other biomarkers" (HRV trend, RHR) that are watched but kept out of the age.
9. **Weekly snapshot** on Monday with a "+0.8 since last week" chip and "Next update in N days". The daily preview stays inside the 1-year-a-week cap.

Gate: backtest 2020–2026 shows no week jumping more than 1 year; the same profile with and without derived VO₂ max differs by < 1 year; confidence matches data coverage by hand on 3 sample months.

## 2 · Strength

### What the video shows

- Workout header: elapsed time, **Finish**, a menu. Exercise cards (Back Squat · Barbell · 3 sets) with one row per set: weight, reps and a ✓. Rows are **pre-filled** from last time.
- Ticking a set starts a **rest countdown** pill between rows (00:30); each exercise has its own rest-timer button.
- **Plate calculator**: tap the weight to see the bar (45) with plates drawn, add 2.5–35, tap a plate to remove it. Changing it updates the set (95 → 145 lbs).
- A **superset link** between exercises, **Progression** (history chart) and **+ Add Set** on each card.
- A floating mini-bar: current exercise, rest elapsed, **live HR (69 ♥)** and a big ✓ for the next set.
- **Library**: search, filters (All groups, All equipment), custom exercises (Bosu ball variants…), an info sheet, and "+ Add custom exercise".

From docs and roadmap: 700+ exercises; progression by **e1RM, heaviest weight, volume, sets, reps**; **Muscular Load and Muscle Freshness** per muscle (from strength *and* cardio); AI **templates** with weights and reps from history, target strain, recovery, equipment and injuries. On the board: RPE per set and gym equipment profiles (planned soon), screen kept awake and a sound when rest ends (in progress), periodisation (planned soon).

### Where we stand

C7 picks *prescribe* strength (focus, 6 exercises with sets × reps, rest, cue, home version) and the live workout follows segments, but **nothing is logged per set**. There's no load history, so no progression and no muscle freshness. Picks choose lower, upper or full by "least recently trained". Wrist HR also under-counts strain during lifting (PLAN risk table).

### Plan

**S1 · Set logger** (schema bump; `strength_sets` append-only: workout id, exercise id, set no, kg, reps, RIR/RPE, done_at, superset group)
- Rows pre-filled from the last session, or from the pick's prescription.
- Tick → rest timer with **sound + vibration** at the end, **screen kept awake**, plate calculator (kg *and* lb, your gym's plates), supersets, add or remove sets, **RIR per set** (one tap: 0/1/2/3+). RIR is something the benchmark only has planned.
- Bundled offline library, about 150 exercises to start (JSON asset with primary/secondary muscles, equipment, home swap), plus custom exercises. Names and cues are our own writing.
- Live HR in the mini-bar on the band. Health users get a timer, as today.

**S2 · Progression engine** (pure Dart, `scoring/strength.dart`)
- e1RM (Epley, only from sets of ≤ 10 reps), best set, volume load, weekly hard sets per muscle.
- **Double progression**: hit the top of the rep range at RIR ≥ 1 on all sets → add the smallest plate step next time. Missing the bottom twice → hold. Missing it 3 times → −10 %.
- **Readiness-aware**: red recovery or "unwell" → same weight, −1 set. The P1 lighter week → −40 % sets. The goal's phase sets the rep ranges (base 8–12, build 6–10, peak 3–6).
- Picks pre-fill today's numbers from this, so the C7 prescription becomes *your* weights, not a generic template.

**S3 · Muscle freshness + strength strain**
- Per-muscle load = hard sets weighted (primary 1, secondary 0.5) with a 48–72 h exponential decay. Runs add calves, quads and hamstrings.
- A body map on the workout and Coach screens. **Picks choose focus by freshness** (replacing "least recently") and still keep "legs fresh before key runs".
- Strain correction: add a volume-load term to session TRIMP for strength workouts (calibrate against RPE × duration, i.e. session-RPE). Label it as an estimate.

Gate: 4 weeks of logged lifting where each suggested weight matches what a coach would set (owner's check), and no key run is scheduled within 48 h of a heavy lower-body day.

## 3 · Journal

### What the video shows

- A week strip with a ✓ under each completed day. Sections **Daytime**, **Nighttime** (spanning the night, e.g. Apr 21–22) and **Automatic**.
- **Quantities**, not just yes/no: Alcohol 0.0 drinks, Caffeine 188 mg, Hydration 2,118 ml, Vitamin C 31.2 mg (from Health / nutrition logs).
- **Automatic** entries filled from data (marked with a sparkle): 10,000+ steps, 20+ min cardio, 20+ min strength, 30+ min Zone 2, 67+ nutrition score. "Clear manual entries for day".
- **Insights**: Recovery and Sleep tabs; each behaviour shows a ± **impact %** on a negative/positive bar (Late meal −11 %, Limited alcohol −12 %, 10k steps −6 % on sleep), with **"Low confidence · continue logging"**.
- **Customize Journal**: tabs All / Automatic / Health Status / Lifestyle / Me…, search, about 100 toggles each with a settings gear (ashwagandha, blue-light glasses, CPAP, creatine, cold shower, ear plugs, fever, injury, intermittent fasting, hot tub, humidifier, ice bath, …), and "+" for a custom entry.

From docs: impact is a correlation and "not causation"; about 5 yes and 5 no unlock it. On the board: journal reminders, auto-tracker insights and supplement tracking are planned.

### Where we stand

5 yes/no tags, a "Yesterday, quickly" card on Today, and insights against next-morning **recovery only**: unlock at 30 check-ins, ≥ 5 each side, a plain mean difference, and confidence from consistency.

### Plan

**J1 · Journal v2** (UI + store; journal rows gain an optional `amount` and `unit`)
- A **catalogue** of about 60 entries in 4 groups (Lifestyle, Health status, Supplements & meds, Sleep environment), searchable, plus custom entries. Users switch on only what they track. The morning card shows only the switched-on ones.
- **Quantities and times**: drinks, caffeine mg plus *time of last caffeine*, water, **first/last meal time** (this also gives a fasting window: fasting is the most-voted request on the benchmark's board, 780+ votes).
- **Automatic entries** from our own data, needing no logging: brisk 30+, steps over target, Zone 2 30+, strength done, **late workout (< 3 h before bed)**, nap, **travel (phone time-zone change)**, late bedtime vs usual, high-strain day. Read caffeine, water and alcohol from Health where present (read-only, TODO(verify) per kind).
- A **journal reminder** as a new C4 nudge kind, within the existing caps and quiet hours.

**J2 · Impact engine v2** (pure Dart, `scoring/insights.dart`). This is where we beat the benchmark instead of copying it:
- **More outcomes:** recovery, sleep performance, night HRV (or stress), night RHR, time asleep, deep share. Use the right lag (behaviour on day D → night D → morning D+1).
- **Adjust for confounders**: ridge regression of the z-scored outcome on all active tags plus yesterday's strain, weekday/weekend and sleep debt. Late meals often come with alcohol, so a plain mean blames both.
- **Shrink small samples toward zero** (empirical-Bayes prior) and show **effect ± range in real units** ("≈ −4 recovery points, likely −1 to −7"), not a bare %.
- **Many-tags guard**: with about 60 tags some will look significant by chance, so require the range to exclude 0 *and* hold in both halves of the history.
- **Dose-response** for amounts (each drink, caffeine after 2 pm by mg).
- **N-of-1 experiments**: "Try 14 days with no caffeine after 2 pm". Tempo schedules on/off blocks, reminds you, and reports the result with a range. The benchmark doesn't have this.

Gate J1: 14 days logged with the reminder, with no day where an automatic entry is wrong when checked by hand. Gate J2: on synthetic data with a planted effect and a planted confounder, the engine finds the first and not the second (unit test), and on 90 days of real data no tag's sign flips between the two halves without its range including 0.

## 4 · Algorithm improvements (A9)

| Area | Today | Change | Why |
| --- | --- | --- | --- |
| Recovery inputs | HRV/stress 0.4, RHR 0.3, sleep 0.3 | Add **respiratory rate**, **SpO₂** and **wrist temperature** deviations as a penalty only (no bonus), from the body-signals code | The benchmark uses all five. Deviations predict illness (Mishra 2020) |
| Wrist temperature | Not read | Read Apple sleeping wrist temperature / Health Connect skin temperature (TODO(verify)) | Feeds recovery, body signals and the cycle later |
| Sleep score | Hours ÷ need | v2: sufficiency 60 %, regularity (SRI) 15 %, efficiency 10 %, continuity (wake bouts) 10 %, HR dip 5 %. Band stages stay out of the score (wrist stages are unreliable) | Closer to how leading apps score sleep, and regularity is already measured (E1) |
| Strain | HR TRIMP | + strength volume term (S3) | Wrist HR under-counts lifting |
| Strain target | From recovery colour | From recovery **and** the 7/28-day load ratio (already in `load.dart`) | Stops recommending the same strain after a big week |
| Data source | One source; sleep from one app | **Priority per metric** (HR, HRV, sleep, steps) | A top request on the benchmark's board that it doesn't support itself |

Every change bumps `algo_version`, recomputes, and is backtested on 2020–2026 before shipping. Every constant is listed as a starting value to calibrate.

## 5 · Benchmark roadmap: what users ask for and our answer

| Request on the benchmark's board | Status there | Our position | Action |
| --- | --- | --- | --- |
| Android app | planned (tbd) | **Have** | Lead with it |
| Fasting tracker | planned (tbd), 780+ votes | Missing | J1 meal times → fasting window |
| Sickness detection notification | planned (soon) | **Have it as a card** | Add a `health` nudge when ≥ 2 body signals are off |
| Abnormal-metric alerts | planned (tbd) | Partly (body signals) | Same nudge, one per day at most |
| Journal reminders | planned (tbd) | Missing | J1 |
| Supplements / medication | planned (soon) | Missing | J1 catalogue group |
| RPE per set, gym equipment profiles | planned (soon) | Missing | S1 (RIR), S2 (plates and equipment) |
| Rest sound, screen awake | in progress | Missing | S1 |
| Periodisation | planned (soon) | **Have (P1/P2)** | Tie strength phases to it (S2) |
| Data source priority for every metric | requested | Sleep only | A9 |
| Sync without opening the app | planned (soon) | **Have** (background sync) | Verify through the H3 gate |
| Activity calendar, widgets | in progress / requested | Calendar yes, widgets no | Home-screen widget with the three scores (later) |
| Yearly "Wrapped", daily report, sharing | requested | Weekly report yes | Year in review from local data (later) |
| AI chat / Claude connector | Pro / under review | **Not allowed** (no network) | Stay on-device: "Why?" explainers on every number, and a local data export the user can take anywhere |
| Nutrition score, photo logging | Pro feature | Missing | Out of scope for now (needs a food database); read macros, water and caffeine from Health only |

## Target audience

People with a cheap band or any watch, often on Android, who want premium-strap-level coaching without a subscription, a cloud account or an iPhone. Every feature above is chosen to work offline, on Android and on the Mi Band's per-minute data, and to stay honest about what a wrist can't measure (ranges and confidence instead of false precision).

## Checklist

Status as of Oct 16, 2026 (built in this branch; see `docs/decisions.md`).

**Now (fix and quick wins)**
- [x] L1.1 Fix the VO₂ max / RHR double count in Tempo Age (algo bump, test)
- [x] Health nudge when ≥ 2 body signals are off (reuses C4)
- [x] Journal reminder nudge

**J1 · Journal v2**
- [x] Catalogue (70 entries), groups, search, custom entries
- [x] Amounts and times (drinks, caffeine mg plus last time, water, meal times / fasting)
- [x] Automatic entries from our data (brisk, steps, Zone 2, strength, late workout, nap, late bed, hard day)
- [ ] Travel from a phone time-zone change (travel stays a manual entry)

**L1 · Tempo Age v2**
- [x] Overlap shrink per group
- [x] 6 groups with years (rows, not rings)
- [x] Confidence % and a range
- [x] Split moderate and vigorous minutes
- [x] Measured VO₂ max: typed in from a watch (the Health plugin has no VO₂ max type)
- [x] PhenoAge from manual labs (stored in settings so backups carry them; tests against the published coefficients)
- [x] Biomarker detail: bar, 30-day average over 3M/6M/1Y, age/sex reference
- [ ] Monday snapshot (Tempo Age still updates daily under the 1-year-a-week cap; the "since last week" card stays)

**S1–S3 · Strength**
- [x] `strength_sets` table and the set logger (pre-fill, rest timer, sound, screen awake, plates, supersets, RIR)
- [x] Offline library of 155 exercises
- [ ] Custom exercises
- [x] Progression engine: e1RM, double progression, readiness and lighter-week aware
- [ ] Rep ranges by block phase (the goal's dose still sets them)
- [x] Picks pre-fill your weights
- [x] Muscle freshness; picks choose focus by freshness (a list of muscles, not a body map)
- [x] Strength set load in strain

**J2 · Impact engine v2**
- [x] Multiple outcomes with correct lag
- [x] Ridge with confounders, shrinkage, ranges in real units
- [x] Many-tags guard, dose-response
- [x] N-of-1 experiments

**A9 · Algo**
- [x] Respiratory rate, SpO₂ and temperature as recovery penalties
- [x] Read wrist/skin temperature (TODO(verify) on phones)
- [x] Sleep score v2 (sufficiency, regularity, efficiency, continuity, HR dip), the sleep number on Today, Sleep, Trends and the widget
- [x] Strain target that uses the load ratio
- [x] Data source priority per metric (sleep, heart rate, HRV, steps)
- [ ] Backtest 2020–2026 for every change (runs on a synthetic export here; needs the real export on the owner's machine)

**Later**
- [ ] Home-screen widget, year in review

## Sources

- The benchmark app's product videos (Biological Age, strength logging, Journal), help center, blog and public feature board, plus third-party reviews. Links are kept out of the repo.
- Science: Levine 2018 PhenoAge (Aging), Kodama 2009, Zhang 2016, Paluch 2022, WHO 2020 activity guidelines, Windred 2024, Mishra 2020. The rest are as cited in `scoring/longevity.dart`.
