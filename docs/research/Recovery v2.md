# Recovery v2: physiology only, whatever data is there

Status: built as algo 12 (3 Nov 2026). See §5 for what changed from this design. Owner question, 3 Nov 2026: recovery must never depend on the journal; it should come from heart rate, HRV, sleep and the other signals available, the way Apple, Whoop, Garmin and COROS do it.

## 1. Where we are (algo 11)

Recovery today already uses **no journal input**. `scoreDay` (`packages/scoring/lib/src/daily.dart`, `recoveryInputsFor`) takes:

| Input | Source | Weight |
|---|---|---|
| Overnight HRV (ln, blended with the week) | Health (watch) | 0.4 × reading-count factor |
| Overnight stress index (HRV stand-in) | Mi Band | 0.4 |
| Resting HR (10th percentile of asleep HR) | both | 0.3 |
| Sleep against base need | both | 0.3 |
| Night vitals (breathing rate, SpO₂, wrist temp) | where present | penalty only, up to −15 |

Each input is a z-score against your own last 30 days (median/MAD, minimum spread, capped ±2.5), weighted, then turned into 0–100 by a logistic. Missing inputs drop out and the rest renormalise.

The journal (and morning feel) touch recovery only as *explanations*: "Last time" cards, impact insights and the feel ↔ recovery check. The Today "What Tempo is learning" card listed "Journal insights" next to "Personal recovery", which read as a dependency; it is now marked optional.

What algo 11 lacks, compared with the products below:

- no **training-load** input: a strain-19 day with a normal resting HR the next morning reads as fully recovered;
- **sleep is one night only**: no multi-night sleep balance;
- **HRV is tonight-vs-30 days only**: no long-term trend ("HRV status / balance");
- breathing rate and temperature only **subtract**, never inform the score itself;
- no **confidence**: a night with 40 HR readings scores as surely as one with 500;
- 14 nights before any score.

## 2. What others do (public descriptions, as best known; `TODO(verify)` the details before quoting them in the app)

| Product | Readiness score | Main inputs | Notes |
|---|---|---|---|
| **Whoop** | Recovery 0–100 % | HRV (largest share), resting HR, respiratory rate, sleep performance; SpO₂ and skin temp as context | Personal baseline over ~30 days; needs a few nights to calibrate. |
| **Garmin** | Training Readiness 0–100; Body Battery | Sleep score, recovery time (from training load), HRV status, acute load, sleep history, stress history | HRV status compares a 7-night average with a personal long-term band (needs ~3 weeks). Load is a first-class input. |
| **Oura** | Readiness 0–100 | Resting HR, HRV balance, body temperature, recovery index, sleep, sleep balance, previous-day activity, activity balance | Explicit multi-day "balance" terms for sleep, HRV and activity. |
| **COROS** | Recovery % and timer; daily HRV | Training load (recovery timer), overnight HRV and resting HR vs baseline | Recovery is load-driven; HRV is shown as a status. |
| **Apple** | No single score | Vitals app flags outliers (heart rate, respiratory rate, wrist temp, SpO₂, sleep duration) against your typical range; Training Load compares recent effort with your normal | Deliberately no readiness number; "two or more vitals out of range" is the signal. |

Common ground: every product uses **only measured physiology and load**, judged **against your own baseline**, with **multi-day trends** next to last night. None uses self-report in the score (Whoop's journal and Oura's tags are for insights only). That matches what the owner asked for.

## 3. Recovery v2 design

### 3.1 Inputs (all optional; whatever is present is used)

| Group | Signal | How it is judged | Weight (all present) |
|---|---|---|---|
| **Autonomic** | Overnight HRV (RMSSD or SDNN, per kind), or the band's stress index | Tonight's deviation from your 30-day normal **and** your 7-night average against a 60-day band (HRV status) | 0.35 |
| | Resting HR (asleep 10th percentile) | Tonight vs 30-day normal, minimum spread 2.5 bpm | 0.20 |
| **Sleep** | Tonight against base need | as now | 0.15 |
| | Sleep balance: last 7 nights against need, recency-weighted | new | 0.10 |
| **Load** | Yesterday's strain against your chronic load; 3-day acute vs 42-day chronic | high yesterday or a hot 3 days lowers recovery; never raises it above neutral | 0.15 |
| **Vitals** | Breathing rate, wrist temperature, SpO₂ | Apple-style outlier check against your range: one out = small step down, two or more out = larger, capped | 0.05 in the score, plus the existing penalty cap |

Missing groups drop out and the rest renormalise, as now. Watch with HRV: all groups. Band: stress index in place of HRV. Phone only (steps + in-bed): sleep and load only, and the score says so (3.3).

**Journal, morning feel and tags are never inputs.** They stay in insights, "Last time" and validation.

### 3.2 Combining

- Each signal → capped z (±2.5, minimum spreads as in algo 11).
- Weighted mean → logistic, as now, so 50 % stays "your normal".
- Load can only pull down (asymmetric), like Garmin's acute load and Oura's previous-day activity: a rest day doesn't make you "more recovered" than your normal.
- The vitals penalty stays as the illness guard (body signals), unchanged.

### 3.3 Confidence and what it was built from

Every score carries a confidence (high / medium / low) from which groups were present and the night's data quality (HR readings, HRV readings, worn minutes). Today shows a quiet line under the ring: "From heart rate, HRV and sleep", or "From sleep and load only: wear a watch overnight for a full score". Low confidence never shows a red colour on its own.

### 3.4 Calibration

- Nights 1–3: no recovery, as Whoop.
- Nights 4–13: a **provisional** score from population-anchored defaults blended with your own data, labelled "provisional".
- Night 14+: fully personal (as now). HRV status (the 60-day band) appears after 21 nights, as Garmin does.

### 3.5 Validation (gates before shipping algo 12)

- Owner backup replay: feel ↔ recovery Spearman no worse than algo 11 (0.49), days at ≤ 5 no more than algo 11.
- The 31 Oct case: a strain-17 day must lower 1 Nov's recovery even when resting HR alone wouldn't.
- Loop tests (A0.1) still pass; journal-free test: identical scores with the journal table empty and full.
- Multi-tester backtest for the colour cut-offs (A3.3).

## 4. Build steps (algo 12)

1. `recoveryInputsFor`: add sleep balance, load and vitals-in-score inputs; HRV 7-day vs 60-day term.
2. `RecoveryShare` gains the new keys so Today's "why" line and the Recovery screen explain them.
3. Confidence and "built from" on `DailyScore` (derived, carries `algo_version`).
4. Provisional nights 4–13.
5. A journal-independence test in `packages/scoring/test`.
6. `docs/decisions.md` line; stale-algo pass recomputes stored days.

## 5. As built (algo 12, 3 Nov 2026)

- Weights: tonight's HRV (or the band's stress index) 0.25, HRV trend 0.10, resting HR 0.25, last night's sleep 0.15, 7-night sleep balance 0.10, load 0.15 (`RecoveryParams`).
- **Vitals stay a penalty**, not a 0.05 input: only the penalty is stored per day, so Today's breakdown couldn't rebuild a vitals input and the "why" line would disagree with the score. Their 0.05 went to resting HR.
- HRV trend: the 7-night mean against a 60-day robust normal, judged once 21 nights are in it; the stress index the same way, lower being better.
- Sleep balance: last 7 nights' sufficiency (capped 120 %), weights 1, 0.8, 0.64, … , against meeting the need (100 %, spread 15); needs 3 nights.
- Load: max of yesterday's strain and the 3-day mean above the 28-day median (spread floor 3), pulling down only; needs 7 days of strain.
- A day needs at least one night signal (HRV/stress, resting HR or sleep): load alone never makes a score (20 Oct, band off overnight, stays unscored).
- Provisional from night 4 on Today, in a neutral colour, without population-anchored defaults (the minimum spreads already keep early z small); fully personal at night 14 as before.
- Confidence ("From HRV, resting HR, sleep and load"; high / medium / low) is derived from the breakdown at display time (`recoveryBasis`), not stored.
- No journal, feel or tag reaches `scoreDay`: its inputs are minutes, stress readings, score history and night vitals only.

Owner backup replay (24–25 rated mornings): feel ↔ recovery Spearman 0.49 → 0.55; days at ≤ 5: 2 → 1; mean day-to-day change 24 → 19; 1 Nov (after a strain-17 day) 34 → 23; colours unchanged at 1 green / 7 red (cut-offs still for the multi-tester backtest).
