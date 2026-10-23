# Algorithm review: the science behind Tempo's scores

Written 2026-10-23, against `algoVersion` 9. This goes through every formula in `packages/scoring` (plus the sleep and HR parts of `health_source`), checks it against published research and against what other apps publicly say they do, and ends with a prioritised plan (§12).

It started from a sleep score comparison on 23 Oct: Tempo 73, Apple Health 82, same night (2:02 → 9:14, 7 h 07 m asleep). Working through that gap uncovered bugs that reach well beyond the sleep score.

**How to read the verdicts:** ✅ sound · ⚠️ works but weaker than the evidence supports · ❌ a bug or a choice that conflicts with the evidence. Citations are to the primary papers; industry practice is what companies say publicly, since their formulas are proprietary.

---

## 1. Summary

**Three feedback loops, all on the sleep → need → recovery path.** These are the most important findings, because each one distorts several scores at once.

| # | Loop | Effect |
|---|---|---|
| L1 | Sleep debt is measured against each past night's *stored need*, and that need already includes debt (`daily.dart:247`). | Once debt reaches the 2 h cap it stays there: every need is ≥ 8.5 h, so a normal 7 h night adds 1.5 h of shortfall. Seen 23 Oct: debt exactly 2h 00m, need 8h 49m. |
| L2 | The base need is learned from the best-recovered third of nights, but recovery includes sleep performance (weight 0.3), which is sleep ÷ need. | Longer nights score higher recovery, so they get picked, so the learned need drifts toward your *longest* nights rather than the nights that left you best recovered. |
| L3 | Recovery includes sleep performance, which inherits L1 and L2. | An inflated need lowers recovery as well as the sleep score. |

**Other ❌ findings**

- **Sleep efficiency is measured from the first to the last asleep minute** (`SleepSession.inBed`, `sleep.dart:14`), so it can't see time spent falling asleep. It reads 97–99 % almost every night (99 % on 23 Oct) and contributes nearly nothing to the score.
- **Resting HR switches between definitions from day to day:** the lowest 5-min window of the night when there is HR, otherwise the source's own resting HR (`daily.dart:221`). Both feed one baseline, so its mean and SD mix two measures.
- **HR max only ever goes up, on any single minute** (`updatedHrMax`). One optical artefact (cadence lock at 200+ bpm) raises HR max permanently, which lowers every later day's TRIMP, strain and zones.
- **The acute:chronic load ratio** (`load.dart`) uses the rolling-average, coupled form and Gabbett's 0.8–1.3 "sweet spot". The research community has largely walked both back since 2019 (§6).

**What's already good:** sleep regularity (SRI), social jetlag, brisk cadence, HR recovery, body signals, Tempo Age's sourcing and confidence, the journal's ridge regression, the feel ↔ recovery check, keeping wrist-estimated stages out of the score, and ln-HRV. The codebase cites its sources and labels its own starting values, which makes it much easier to audit than most.

**What's missing across the board:** no algorithm has been validated against an outcome or a reference device. Every constant is either a literature value or "a starting value to calibrate", and the calibration hasn't been done. §11 proposes a validation harness, which turns the open gates (C1, T1 backtest, F1 diary) into measurements rather than impressions.

---

## 2. Sleep: detection, need, debt, score

### 2.1 Detection and sessions — ✅ / ⚠️

`detectSessions` merges sleep runs across wake gaps of ≤ 30 min, or ≤ 90 min when quiet and worn. The rules come from real captured nights, and the 6 Oct cases are documented. Fine for the band.

⚠️ For Health sources the session starts at the first asleep minute. Apple Watch and most Android watches also write an *in bed* interval (`HKCategoryValueSleepAnalysis.inBed`, Health Connect `SleepSessionRecord`). `grid.dart:198` reads it but only as a sleep mark, so the session never starts at lights-out. That is the cause of the efficiency problem in §2.5.

### 2.2 Base sleep need — ⚠️ (and loop L2)

**What we do:** 7.5 h default. After 14 nights with recovery, the median sleep of the best-recovered third of the last 60 nights, clamped to 6.5–9.5 h.

**Evidence:**
- Adults need 7–9 h (Hirshkowitz 2015, NSF; Watson 2015, AASM/SRS consensus "≥ 7 h"). Individual need varies by roughly ±1 h and is fairly stable over months.
- The best-supported way to estimate personal need from free-living data is how long you sleep when unconstrained:
  - **Kitamura 2016** (*Sci Rep*): extended time in bed for 9 days; sleep length settled at the individual's need, on average 8.4 h, against a habitual 7.4 h.
  - **Roenneberg's** free-day oversleep correction: sleep on free days is longer by roughly the workweek debt.
- Picking nights by "next-day recovery" isn't wrong in principle (Whoop describes something similar). But the recovery score must not include sleep length itself, or it just selects long nights (L2).

**Verdict:** the idea is sound, the implementation is circular. Learn need from HRV + resting HR recovery only (no sleep term), and cross-check it against average free-day sleep (we already compute free days for social jetlag).

### 2.3 Sleep debt — ❌ (loop L1)

**What we do:** debt = Σ over the last 7 nights of (stored need − slept), capped at 2 h, with no decay. Need tonight = base + 0.5 × debt + 0.03 × yesterday's strain.

**Evidence:**
- **Van Dongen 2003** (*Sleep*), the reference experiment for chronic restriction: impairment builds up against a fixed individual need, not against a need that itself grows with debt.
- **Kitamura 2016:** paying back 1 h of debt took about 4 days of extended sleep, and the payback isn't 1:1.
- **Belenky 2003:** after restriction, three nights of recovery sleep didn't fully restore performance.
- So the usual model is a fixed personal baseline, a shortfall that adds up, and repayment that is partial and slow.

**Industry:** Rise (circadian app) counts debt over 14 nights against a fixed personal need. Whoop's need adds a debt term, but measures the debt itself against baseline need. Oura and Apple don't put debt in the score at all. Debt measured against a debt-inflated need appears in no product or paper we could find.

**Fix:**
1. Measure debt against the **base** need: Σ (base − slept − naps), recent nights weighted more (e.g. half-life 4 nights, matching Kitamura's repayment time).
2. Count surplus sleep as repayment (negative shortfall, so long nights reduce debt), at a capped rate.
3. Keep the cap, but show it as "at least 2 h" when it binds.

### 2.4 Strain term in need — ⚠️

+0.03 h per strain point (up to +38 min at strain 21). Hard exercise mostly redistributes sleep architecture (more slow-wave sleep) rather than raising total need much. Meta-analyses (Kredlow 2015; Dolezal 2017) find small increases in total sleep, on the order of 10 min. Whoop uses a strain term, but its size isn't published.

**Fix:** keep it, but cut the weight to about a third (≈ +10–15 min for a hard day), and label it as a starting value.

### 2.5 Sleep score v2 — ⚠️ / ❌

**What we do:** sufficiency (sleep ÷ dynamic need) 60 %, bedtime vs 14-night median 15 % (0 points at 90 min off), efficiency 10 % (65 → 90 %), wake bouts ≥ 5 min 10 % (−15 each), HR dip 5 %.

**Evidence and practice:**

| Component | Research anchor | Industry |
|---|---|---|
| Duration | ≥ 7 h (AASM/SRS); NSF 7–9 h | Apple 50/100 against a fixed guideline; Fitbit ~50/100; Oura against an age band |
| Timing / regularity | SRI (Phillips 2017; Windred 2024) beats bedtime SD for health outcomes | Apple: bedtime vs your average, 30/100; Oura: "timing" around midnight–3 am |
| Efficiency | NSF quality consensus (**Ohayon 2017**, *Sleep Health*): ≥ 85 % good, ≤ 74 % poor | Oura, Fitbit |
| Continuity | Ohayon 2017: WASO ≤ 20 min good, ≥ 51 min poor; awakenings > 5 min: 0–1 good, ≥ 4 poor | Apple "Interruptions" 20/100; Oura "restfulness" |
| Latency | Ohayon 2017: ≤ 30 min good, ≥ 46 min poor | Oura "latency" |
| Nocturnal HR dip | Real physiology, but the evidence is about blood-pressure dipping; HR dip is weaker | Fitbit "restoration" (sleeping HR vs resting HR) |

**Problems:**
1. Sufficiency inherits L1/L2: 60 % of the score scales with an inflated need. *This alone is the 73 vs 82 gap:* with need = 7.5 h, the same night scores ≈ 82.
2. Efficiency can't drop below ~95 % (§2.1), so it is a fixed +10.
3. "Wake bouts" uses a Tempo-specific step (−15 each) instead of Ohayon's published bands.
4. Sleep latency is computed (`sleep_plan.dart:85`) but not scored.
5. The HR dip's evening window (3 h before sleep, awake minutes) picks up dinner, alcohol and evening workouts. That's arguably signal, but it isn't "sleep quality".

**Recommendation** (matching the "camp 1" choice discussed with the owner on 23 Oct, still to be confirmed):
- **Sufficiency 50 %** against **base need** (learned, clamped 7–9 h). Debt and tonight's need stay on screen as guidance ("go to bed by…"), not as a score penalty.
- **Regularity 20 %**: bedtime deviation as now, but on Apple's gentler curve (0 points at ~3 h off rather than 90 min). Or blend with the 7-night SRI once there's enough history.
- **Efficiency 10 %**, from in-bed time when the source has it, on Ohayon's 74 → 85 % bands. Drop the component when no in-bed data exists, rather than scoring a fake 99 %.
- **Continuity 15 %**: WASO and awakenings > 5 min on Ohayon's bands.
- **Latency 5 %**, only when in-bed data exists.
- **HR dip:** move it out of the sleep score into recovery/body signals, or keep it at ≤ 5 %.
- Keep stages out (§3).

Then re-run the 23 Oct night and a backtest, and check the score distribution: median ≈ 75–80, most nights between 60 and 90, which matches the published Apple/Oura distributions.

---

## 3. Sleep stages (band) — ✅ as labelled

A heuristic stager from HR level, HR variability and motion. Consumer wrist staging agrees with polysomnography only roughly: four-class epoch accuracy is around 60–70 %, best for wake/sleep and worst for deep vs light. See Walch 2019 (*Sleep*, Apple Watch raw data), de Zambotti 2019, and Chinoy 2021 (*Sleep*, seven consumer devices vs PSG).

The code already treats stages as an estimate and keeps them out of the score. That's the right call, and also what Apple does.

Minor: `sdLo` and `sdHi` are both the median (`sleep_stages.dart:128-129`), so the "low variability" and "high variability" tests share one threshold. Either name it once or use the 0.4/0.6 quantiles. There are no golden tests against a reference stager. If a Health night with Apple stages is ever available for the same night as band data, that's a free comparison.

---

## 4. Recovery

### 4.1 Structure — ⚠️

**What we do:** recovery = logistic(1.5 × weighted mean z), with HRV 0.4, resting HR 0.3, sleep performance 0.3. Baselines are the mean/SD of the last 30 days from the same source. 14 nights of calibration. Vitals penalty up to −15.

**Evidence:**
- HRV-guided training is the best-validated readiness approach: Kiviniemi 2007; Plews 2013 (*Sports Med*); Javaloyes 2019 (*IJSPP*); and a 2021 meta-analysis (Düking, *Sports Med Open*) finding small benefits over pre-planned training.
- Those protocols agree on three points:
  1. Use **ln RMSSD** from a standardised window (waking or a fixed sleep segment).
  2. Judge the **7-day rolling mean**, not a single day, because daily CV is about 7–10 % (Plews 2012).
  3. Compare against the **smallest worthwhile change** (SWC = ±0.5 × SD of the baseline) and a 60-day normal range, rather than a raw z.
- Resting HR is a weaker but useful co-signal (Buchheit 2014, *Front Physiol*).

**Problems:**
1. **A single-night z on HRV** reacts to one bad reading. Fix: blend the night's value with the 7-day rolling ln-HRV, e.g. z of (0.5 × tonight + 0.5 × 7-day mean), and use SWC bands.
2. **Mean/SD baseline is not robust.** A week of illness or travel widens the SD, and every later day then looks "normal". Fix: median and MAD × 1.4826, excluding days already flagged by body signals or a pause.
3. **Sleep performance is censored at 100** and carries L1–L3. Fix: use the corrected sufficiency (sleep ÷ base need, uncapped up to ~120 %), or the sleep score.
4. **Apple's HRV is SDNN from short, irregularly timed readings**, not overnight RMSSD. Comparing each night only with earlier nights of the same kind (as now) is correct. But a night with only one or two readings shouldn't carry the full 0.4 weight: scale the HRV weight by how many readings there were.
5. **The logistic slope (1.5) and colour cut-offs (34/67)** were never fitted. Whoop says its distribution centres in the high 50s to low 60s. Check ours on backtest data and set the slope so roughly a third of days are green, a third yellow, a third red at baseline. Or keep it, but document the resulting distribution.

### 4.2 Resting HR — ❌ (definition switching)

**What we do:** the lowest 5-min rolling mean of the night (≥ 50 % coverage), otherwise the source's resting HR.

**Evidence and practice:** Oura uses the lowest 5-min average of the night. Whoop says it weights the last slow-wave period. Apple's `restingHeartRate` is a daytime estimate made while still. These are three different numbers: for the same person, the sleep minimum typically sits 5–10 bpm below Apple's daytime figure.

**Problems:**
- On a Health source with readings every ~5 min, a "5-minute window at ≥ 50 % coverage" can rest on a single reading, so the minimum is an extreme-value statistic of noise.
- Falling back to `sourceRhr` puts a daytime number into a sleep-minimum baseline.

**Fix:**
- Use a percentile rather than a minimum: the 10th percentile of asleep HR, with a 30-min window.
- Require a minimum number of readings.
- Store *which* definition was used (like `hrvKind`), and baseline only against the same definition.

### 4.3 Vitals penalty — ✅

Breathing rate, SpO₂ and temperature more than 1.5 SD the wrong way take up to 15 points off, and never add any. This matches the illness-detection literature: Mishra 2020 (*Nat Biomed Eng*), Radin 2020 (*Lancet Digital Health*), Smarr 2020 (temperature). Keep it. It would be better on robust baselines (§4.1 point 2).

---

## 5. Strain and TRIMP

### 5.1 TRIMP — ⚠️

**What we do:** Banister TRIMP per minute with the **male** coefficients (0.64 e^{1.92x}) for everyone, x = HRR fraction, below 30 % HRR ignored and the rest rescaled.

**Evidence:**
- Banister's coefficients are sex-specific: **0.86 e^{1.67x} for women** (Morton, Fitz-Clarke & Banister 1990). Using the male curve for women under-weights moderate intensities.
- The 30 % floor is non-standard. It's defensible (it removes everyday activity), but the floor-then-rescale step changes the shape of the curve, so the result is no longer Banister's TRIMP, and published strain values aren't comparable. It is calibrated, and the calibration is documented in tests.

**Fix:** use the profile's sex. Floor the HRR fraction *without* rescaling (x ≤ 0.3 → 0, otherwise the plain Banister x), then refit k so the documented calibration days keep their strain values.

### 5.2 HR max — ❌

**What we do:** the default is 190 (or the user's setting). Afterwards HR max is the highest single minute ever recorded.

**Evidence:**
- **Tanaka 2001** (*JACC*): 208 − 0.7 × age, SD ≈ ±10 bpm.
- Wrist PPG during intervals and lifting often reports cadence-locked HR, and those spikes are artefacts.
- A single-minute maximum is the least robust statistic there is, and HR max feeds TRIMP, zones, strain, activity detection and the HR-recovery threshold.
- The app's profile already defaults to Tanaka (`profile.dart:148`), but the scorer defaults to a flat 190 (`score_service.dart:35`).

**Fix:**
- Start from Tanaka by age (the profile's `effectiveMaxHr`) rather than 190.
- Raise HR max only when ≥ 2 consecutive minutes (or ≥ 30 s of second-level samples in a live session) exceed it during a recorded workout, and never by more than 5 bpm at a time.
- Let the user reset it. Keep `TODO(verify)` until it has been checked against a chest strap.

### 5.3 Strain scale and strength — ✅ / ⚠️

The 21-point saturating scale is Whoop-like and fine.

sRPE (Foster 2001) for lifting is the accepted method.

`setTrimp` is a flat 1.6 per hard set scaled by RIR. The comment says "heavier work taxes more per set", but the code doesn't use load or reps. Either remove the comment or add a rep-range factor. Fitting the set constant against logged sRPE is part of the T1 4-week lifting check.

---

## 6. Cardio load (7/28) — ❌ by current evidence

**What we do:** the rolling mean of 7 days ÷ rolling mean of 28 days, with the 7 days included in the 28. Bands: < 0.8 detraining, 0.8–1.3 building, > 1.3 overreaching.

**Evidence:**
- The acute:chronic workload ratio (Gabbett 2016, *BJSM*) became popular as an injury-risk measure, and has since been heavily criticised:
  - **Lolli 2019** (*BJSM*): including the acute window in the chronic window ("coupling") builds in a spurious correlation.
  - **Williams 2017** (*BJSM*): exponentially weighted averages (EWMA) track load better than rolling means.
  - **Impellizzeri 2020** (*IJSPP*) and **Wang 2020**: the "sweet spot" doesn't hold up as an injury predictor, and the ratio has poor statistical properties.
- Training platforms (TrainingPeaks, Intervals.icu, Garmin's training load) use **Banister's fitness–fatigue model** instead: CTL = 42-day EWMA ("fitness"), ATL = 7-day EWMA ("fatigue"), TSB = CTL − ATL ("form"). Coaches read form ranges such as −10 to −30 as productive and below −30 as overreaching.

**Fix:**
- Switch to EWMA (7-day and 42-day time constants).
- Show form (CTL − ATL) and a ramp rate (CTL change per week; > ~5–8 TRIMP-equivalent per week is aggressive).
- Keep the ratio only as an internal input, uncoupled, and stop describing it as an injury signal.
- Keep the null-day handling (a day without data isn't 0). It's correct and many apps get it wrong.

---

## 7. Zones and activity detection — ✅ / ⚠️

Zones as % of HR max (50/60/70/80/90) match Apple/Garmin defaults. **Karvonen (% of HR reserve)** tracks lactate and ventilatory thresholds better across fitness levels; Garmin offers it as an option. It would be a cheap setting, since resting HR is already known. Fix §5.2 first, because zones inherit HR max.

Activity detection (≥ Z2 HR or a step count, with gaps allowed, sport guessed from cadence) is a heuristic and is presented as a guess for the user to confirm. That's fine. It has no measured precision/recall: add a confusion table from confirmed-vs-detected workouts to the validation harness (§11).

---

## 8. Everyday metrics (E1) — ✅

- **Sleep regularity:** SRI (Phillips 2017), banded on Windred 2024's UK Biobank quintiles. Correct, and better than most apps.
- **Social jetlag:** Wittmann 2006 / Roenneberg 2012. Correct.
- **Brisk minutes:** ≥ 100 steps/min (Tudor-Locke 2018) and WHO 2020's 150 min/week. Correct.
- **Longest still stretch:** a reasonable proxy for sedentary bouts. The evidence on breaking up sitting (Dunstan 2012; Diaz 2017, *Ann Intern Med*) supports using the longest bout. ✅
- **HR recovery:** Cole 1999 (*NEJM*, 1-min) and Shetler 2001 (2-min ≤ 22 bpm). Correctly treated as a personal trend, because field recovery isn't a clinical exercise test. ✅
- **Body signals:** two or more signals off means "rest" (Mishra 2020; Radin 2020). Correct. Robust baselines (§4.1) would help here too.

One inconsistency: Tempo Age's regularity lever uses **bedtime SD**, while Everyday uses **SRI**. Use SRI in both, because the mortality evidence Tempo Age cites (Windred 2024) is SRI-based.

---

## 9. Tempo Age — ✅ / ⚠️

Hazard ratios from cited cohorts, years = 8 × log₂(HR) (Gompertz), group overlap shrinkage, per-lever caps, a confidence score, PhenoAge from labs (Levine 2018), and a limit on change per week. This is carefully built.

**Problems:**
1. **VO₂ max estimated from Uth 2004** (15.3 × HRmax / HRrest) comes from 46 trained Danish men. Its error in the general population is ±15–20 % or more, and it feeds the lever with the biggest cap (±5 y). It also inherits the HR-max ratchet (§5.2). **Fix:** without a watch VO₂ max, cap the fitness lever at ±2 y and widen the ± range. Use Apple/Garmin VO₂ max when available (`HKQuantityTypeIdentifierVO2Max`, cardio fitness). Consider the non-exercise estimate from Nes 2011 (HUNT: age, sex, waist, resting HR, activity), which was validated on a population sample.
2. **Multiplying observational hazard ratios treats them as independent and causal.** The group shrinkage handles overlap within a group, but not across groups: active people also sleep better and smoke less. **Fix:** add a global shrink (e.g. × 0.8 on the summed years) or a cap on total deviation (±10 y without labs). Keep the "estimate for wellness" wording.
3. **Long sleep penalty** (1.30 per hour above 8.5 h, Cappuccio 2010): the long-sleep association is widely thought to be mostly reverse causation (illness causes long sleep). Halve it and cap it at +1 y.
4. **Sleep regularity:** switch to SRI (§8). Windred 2024 reports SRI-quintile hazard ratios directly.

---

## 10. Journal impact, insights and feel — ✅ / ⚠️

**Impact v2:** ridge regression on standardised behaviours with strain and weekend as covariates, a seeded bootstrap, ≥ 5 days of each kind, and a minimum effect size. A good design.

**Problems:**
1. **Days are autocorrelated** (recovery today predicts tomorrow), so an ordinary day-level bootstrap gives ranges that are too narrow. **Fix:** a moving-block bootstrap (blocks of ~7 days; Künsch 1989).
2. **Many behaviours × several outcomes means multiple comparisons.** At 15 behaviours, about one will look "real" by chance. **Fix:** shrink harder as the number of behaviours grows, or only report an effect whose range excludes zero after a Benjamini–Hochberg-style correction across the behaviours shown.
3. **The outcome should be the corrected sleep score / recovery,** after L1–L3 are fixed, or effects on sleep will be partly effects on the debt artefact.

**Insights v1** (simple with vs without) should be retired in favour of impact v2 once v2 is the shown result, so two methods don't disagree on screen.

**Feel:** Spearman between recovery and morning feel, ≥ 0.5 counted as "tracks". This is Tempo's only built-in validation, so it should be extended into the harness (§11). Literature on subjective vs HRV agreement: Saw 2016 (*BJSM*) found subjective measures often more responsive than objective ones. So low agreement doesn't automatically mean recovery is wrong.

---

## 11. Validation harness (new)

Every proposed change should be judged by the same numbers, run in `tools/backtest` over the owner's 2020–2026 Apple Health export and any tester exports (with consent, on device):

1. **Reliability:** day-to-day noise of each score on stable weeks. Report the typical error and the minimal detectable change (MDC₉₅ = 1.96 × √2 × SEM). A score shouldn't move more than its MDC without a cause.
2. **Construct validity:**
   - recovery vs next-morning feel (Spearman, already built)
   - recovery vs next-day self-reported RPE for the same session
   - sleep score vs Apple's sleep score on the same nights (where watchOS 26 writes it, `TODO(verify)` whether it's readable from HealthKit), with a Bland–Altman plot
   - HR max vs a measured max test
3. **Known-group checks:** recovery should drop after nights with alcohol logged and in the days before body signals fire. If it doesn't, the weights are wrong.
4. **Distribution checks:** each score's percentiles across users at baseline, so colours mean the same thing for everyone.
5. **Loop checks** (regression tests for L1–L3): a simulated user sleeping exactly their base need for 30 nights must end with debt 0 and need = base. A user sleeping 1 h short must end with debt at the cap, and must return to 0 within ~10 nights of full sleep.
6. **Before/after report** for every algo bump: how many days' colours changed, and the mean change per score. Paste it into `docs/decisions.md` with the bump.

---

## 12. Plan

Phases are named **A0–A4** (algorithm). A0 and A1 should land **before the beta** (B-phases), because beta users will compare Tempo's numbers with Apple Health's, as the owner just did. Each phase is one `algoVersion` bump, with old rows recomputed by the existing stale-algo pass, unit tests for every formula (as CLAUDE.md requires), and a line in `docs/decisions.md`.

### A0 — Validation harness (no algo bump)

| ID | Item | Where |
|---|---|---|
| A0.1 | Loop regression tests (§11.5): constant-sleep and short-sleep simulated users through `scoreDay` | `packages/scoring/test` |
| A0.2 | Backtest prints per-score distribution, day-to-day noise and MDC, and colour-change counts between two algo versions | `tools/backtest` |
| A0.3 | Backtest compares sleep score with Apple's own score where available (`TODO(verify)` HealthKit type) | `tools/backtest` |
| A0.4 | Validation section on the Developer screen: feel ↔ recovery Spearman, recovery vs body-signal days | app, Developer |

**Gate:** A0.1 fails on `algoVersion` 9 (proving the loop) and runs in CI.

### A1 — Correctness fixes, algo 10 (before the beta)

| ID | Item | Fixes |
|---|---|---|
| A1.1 | Debt against **base** need, recency-weighted (half-life ~4 nights), surplus sleep repays at ≤ 50 %, cap 2 h | L1 |
| A1.2 | Learn base need from a recovery made of HRV + resting HR only; cross-check against average free-day sleep; clamp 7–9 h (or keep 6.5–9.5, but show the user their figure) | L2 |
| A1.3 | Recovery's sleep input = sleep ÷ base need, uncapped to 120 % | L3 |
| A1.4 | Session start from the source's in-bed record when there is one; efficiency and latency only when in-bed data exists, otherwise dropped | §2.1, §2.5 |
| A1.5 | Resting HR: 10th percentile of asleep HR (30-min smoothing, minimum reading count); store `rhrKind`; baseline per kind | §4.2 |
| A1.6 | HR max: start from Tanaka / profile; raise only on ≥ 2 consecutive minutes in a workout, at most +5 bpm a step; one source of truth with the profile | §5.2 |
| A1.7 | Strain need term down to ~0.01 h per strain point | §2.4 |

**Gate:** A0.1 passes; the 23 Oct night scores within ±5 of Apple's 82; backtest colour changes reviewed and logged.

### A2 — Sleep score v3 (with A1 or right after; owner picks)

| ID | Item |
|---|---|
| A2.1 | Weights: sufficiency vs base need 50, regularity 20, continuity 15, efficiency 10, latency 5 (dropping out when not measured) |
| A2.2 | Efficiency, WASO, awakenings and latency on Ohayon 2017's good/poor bands |
| A2.3 | Gentler bedtime curve (0 points at ~180 min off); optionally blend with 7-night SRI |
| A2.4 | HR dip moves to recovery/body signals (or stays at ≤ 5 %) |
| A2.5 | Sleep screen: "needed tonight" and debt shown as guidance with "go to bed by", separate from the score |

**Gate:** the sleep score's median across backtest nights is 75–80, and agreement with Apple's score has a Bland–Altman bias within ±5 points.

### A3 — Recovery and load, algo 11

| ID | Item |
|---|---|
| A3.1 | Robust baselines (median/MAD), excluding paused and body-signal days, for recovery, body signals and the vitals penalty |
| A3.2 | HRV: blend tonight with the 7-day rolling ln-HRV; smallest-worthwhile-change bands; weight scaled by the night's reading count |
| A3.3 | Fit the logistic slope and colour cut-offs to the backtest distribution (≈ thirds), or document why not |
| A3.4 | Cardio load to EWMA: fitness (42 d), fatigue (7 d), form and ramp rate; retire the coupled 7/28 ratio and the "overreaching = injury" wording; update the strain-target nudges that read the ratio |
| A3.5 | TRIMP: sex-specific Banister coefficients; floor without rescaling; refit k on the documented calibration days |
| A3.6 | Optional HR-reserve (Karvonen) zones in Settings |

**Gate:** feel ↔ recovery Spearman on the owner's data is no worse than on algo 10, and recovery dips on body-signal days in at least 70 % of cases.

### A4 — Tempo Age, journal and strength polish, algo 12

| ID | Item |
|---|---|
| A4.1 | Fitness lever: watch VO₂ max when available; otherwise Nes 2011 non-exercise estimate, capped at ±2 y with a wider range |
| A4.2 | Global shrink or cap on Tempo Age's total years without labs; long-sleep hazard halved and capped |
| A4.3 | Tempo Age regularity lever on SRI (Windred 2024 quintiles) |
| A4.4 | Journal impact: moving-block bootstrap; multiple-comparison control; retire Insights v1 once impact v2 is the shown result |
| A4.5 | Strength: fit `setTrimp` against logged sRPE from the T1 lifting check; fix or remove the "heavier work" comment |
| A4.6 | Stager: separate low/high variability quantiles; golden tests against any night with both band and Apple stages |

**Gate:** Tempo Age moves less than 0.5 y over a stable month (test-retest), and the journal's false-positive rate on shuffled-label data stays under 5 %.

### Order and effort

1. **A0.1 + A1** first: about 2–3 days. This fixes the visible bugs and is low-risk, because each item is local and has an obvious test.
2. **A2:** a day or two. It's mostly weights and bands. The owner decides between "Apple-like" and "Whoop-like" (23 Oct discussion), and A2 assumes Apple-like.
3. **A3:** 3–5 days. The load change also touches UI copy and the coach's strain nudges.
4. **A4:** after the beta starts, driven by tester data.

### Open decisions for the owner

- **A-O1:** Sleep score against base need (Apple/Oura style, recommended) or against tonight's need (Whoop style)?
- **A-O2:** Base-need clamp: 7–9 h (consensus) or keep 6.5–9.5 h?
- **A-O3:** Replace the 7/28 ratio on screen with fitness / fatigue / form, or keep the ratio UI and only change the maths?
- **A-O4:** May tester validation data (feel vs recovery, score distributions) be collected as opt-in diagnostics? This needs a line in `docs/network.md` first.

---

## References

- Arem H et al. 2015. Leisure time physical activity and mortality. *JAMA Intern Med*.
- Belenky G et al. 2003. Patterns of performance degradation and restoration during sleep restriction and subsequent recovery. *J Sleep Res*.
- Buchheit M. 2014. Monitoring training status with HR measures. *Front Physiol*.
- Cappuccio FP et al. 2010. Sleep duration and all-cause mortality. *Sleep*.
- Chinoy ED et al. 2021. Performance of seven consumer sleep-tracking devices compared with polysomnography. *Sleep*.
- Cole CR et al. 1999. Heart-rate recovery immediately after exercise as a predictor of mortality. *NEJM*.
- de Zambotti M et al. 2019. Wearable sleep technology in clinical and research settings. *Med Sci Sports Exerc*.
- Diaz KM et al. 2017. Patterns of sedentary behavior and mortality. *Ann Intern Med*.
- Düking P et al. 2021. Monitoring and adapting endurance training on the basis of HRV: systematic review and meta-analysis. *Sports Med Open*.
- Foster C et al. 2001. A new approach to monitoring exercise training. *J Strength Cond Res*.
- Gabbett TJ. 2016. The training–injury prevention paradox. *BJSM*.
- Hirshkowitz M et al. 2015. National Sleep Foundation's sleep time duration recommendations. *Sleep Health*.
- Impellizzeri FM et al. 2020. Acute:chronic workload ratio: conceptual issues and fundamental pitfalls. *IJSPP*.
- Javaloyes A et al. 2019. Training prescription guided by HRV in cycling. *IJSPP*.
- Kitamura S et al. 2016. Estimating individual optimal sleep duration and potential sleep debt. *Sci Rep*.
- Kodama S et al. 2009. Cardiorespiratory fitness as a predictor of all-cause mortality. *JAMA*.
- Kredlow MA et al. 2015. The effects of physical activity on sleep: a meta-analytic review. *J Behav Med*.
- Künsch HR. 1989. The jackknife and the bootstrap for general stationary observations. *Ann Stat*.
- Levine ME et al. 2018. An epigenetic biomarker of aging for lifespan and healthspan (PhenoAge). *Aging*.
- Lolli L et al. 2019. Mathematical coupling causes spurious correlation within the conventional ACWR. *BJSM*.
- Mishra T et al. 2020. Pre-symptomatic detection of COVID-19 from smartwatch data. *Nat Biomed Eng*.
- Morton RH, Fitz-Clarke JR, Banister EW. 1990. Modeling human performance in running. *J Appl Physiol*.
- Nes BM et al. 2011. Estimating VO₂peak from a nonexercise prediction model: the HUNT study. *Med Sci Sports Exerc*.
- Ohayon M et al. 2017. National Sleep Foundation's sleep quality recommendations. *Sleep Health*.
- Paluch AE et al. 2022. Daily steps and all-cause mortality. *Lancet Public Health*.
- Phillips AJK et al. 2017. Irregular sleep/wake patterns are associated with poorer academic performance. *Sci Rep*.
- Plews DJ et al. 2012/2013. HRV in elite triathletes; Training adaptation and HRV in elite endurance athletes. *EJAP*; *Sports Med*.
- Radin JM et al. 2020. Harnessing wearable device data to improve state-level real-time surveillance of influenza-like illness. *Lancet Digital Health*.
- Roenneberg T et al. 2012. Social jetlag and obesity. *Curr Biol*.
- Saw AE et al. 2016. Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures. *BJSM*.
- Shetler K et al. 2001. Heart rate recovery: validation and methodologic issues. *JACC*.
- Tanaka H et al. 2001. Age-predicted maximal heart rate revisited. *JACC*.
- Tudor-Locke C et al. 2018. Walking cadence (steps/min) and intensity in 21–40 year olds. *IJBNPA*.
- Uth N et al. 2004. Estimation of VO₂max from the ratio between HRmax and HRrest. *EJAP*.
- Van Dongen HPA et al. 2003. The cumulative cost of additional wakefulness. *Sleep*.
- Walch O et al. 2019. Sleep stage prediction with raw acceleration and PPG heart rate from a consumer wearable. *Sleep*.
- Wang C et al. 2020. Methodological issues with the ACWR. *Sports Med*.
- Williams S et al. 2017. Better way to determine the acute:chronic workload ratio? *BJSM*.
- Windred DP et al. 2024. Sleep regularity is a stronger predictor of mortality risk than sleep duration. *Sleep*.
- Wittmann M et al. 2006. Social jetlag: misalignment of biological and social time. *Chronobiol Int*.
