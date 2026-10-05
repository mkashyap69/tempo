# Training science for adaptive daily workout prescription (general fitness / longevity)

Scope note: about 22 search/fetch calls. PubMed/PMC full texts were blocked by the egress proxy, so many findings come from abstracts and search snippets of primary papers. Where the only source is a blog or vendor page, it is flagged. Items marked "(prior knowledge, not verified this session)" are in Inferences/Gaps only.

## 1. Load metrics: TRIMP/Banister, ACWR, monotony/strain, ramp rate

### Takeaway
Use HR-based TRIMP (Banister or Edwards zones) as the session load unit, with fitness/fatigue exponential averages (CTL/ATL-style). Use Foster monotony (target ≤ 2.0) as a soft guard. Treat ACWR and the "10% rule" as UX heuristics, not as injury predictors: the evidence for both is weak or negative.

### Cited Findings
- Banister TRIMP = duration (min) × HRR fraction × weighting, where weighting = 0.64·e^(1.92·HRR) for men and 0.86·e^(1.67·HRR) for women. Edwards TRIMP = Σ minutes in five %HRmax zones (50–60, 60–70, 70–80, 80–90, 90–100) × weights 1–5. — [Veohtu: TRIMP & training stress](https://www.veohtu.com/trimp.html); [iamcoach TRIMP explainer](https://www.iamcoach.ai/blog/trimp-training-load-explained) (secondary sources restating Banister 1991 and Edwards 1993)
- Fitness–fatigue (impulse–response) model: performance = k1·fitness − k2·fatigue, with time constants τ1 (fitness) and τ2 (fatigue). Original values were about k1 = 1, k2 = 1.8–2.0, τ1 ≈ 45–50 d and τ2 ≈ 11 d. The common "42/7-day" CTL/ATL constants are exponential, so a session's impact halves in about 14.7 d and 2.4 d respectively. — [Fellrnr: Modeling Human Performance](https://fellrnr.com/wiki/Modeling_Human_Performance); [Frontiers in Physiology 2020 fitness-fatigue review](https://www.frontiersin.org/articles/10.3389/fphys.2020.00480/full)
- Foster session-RPE load = RPE (CR-10) × duration (min). Monotony = weekly mean daily load ÷ SD of daily load. Strain = weekly load × monotony. — [Foster presentation, Science & Cycling](https://science-cycling.org/wp-content/uploads/2019/07/Foster-presentatie-gecomprimeerd.pdf); [Frontiers in Neuroscience 2017 sRPE review (Haddad et al.)](https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2017.00612/full)
- Monotony > 2.0 combined with high load is treated as a risk factor for illness and overtraining. In Foster's early work, about 89% of illnesses and injuries were explained by spikes in individual strain in the preceding 10 days. — [Foster presentation](https://science-cycling.org/wp-content/uploads/2019/07/Foster-presentatie-gecomprimeerd.pdf); [athletemonitoring workload guide](https://www.athletemonitoring.com/wordpress/wp-content/uploads/2017/06/Workload-Management-Basics.pdf) (practitioner source)
- ACWR critique (Impellizzeri et al., IJSPP 2020, "Conceptual issues and fundamental pitfalls"):
  - The ratio has no established causal relation to injury.
  - It is mathematically inaccurate, because the numerator is not normalised by the denominator even in the uncoupled version.
  - The acute and chronic windows lack a physiological rationale.
  - It is "not consistently and unidirectionally related to injury risk".
  - The authors conclude there is no evidence supporting ACWR in load-management systems or training recommendations.
  — [IJSPP 15(6):907](https://journals.humankinetics.com/downloadpdf/journals/ijspp/15/6/article-p907.xml); [Editorial: ACWR, is there scientific evidence? (Frontiers/PMC8138569)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8138569/)
- 10% rule: Buist et al. randomised 532 novice runners to a graded programme (<10%/week over 13 weeks) or a standard programme (>10%/week over 8 weeks). Injury incidence was 20.8% vs 20.3%, so there was no preventive effect. A systematic review also found no evidence for a clearly defined 10% threshold, although gradual progression as a principle is still supported. — [PMC9528699: running injuries & training parameters SR](https://pmc.ncbi.nlm.nih.gov/articles/PMC9528699/); [PMC6253751: training load change and RRI SR](https://pmc.ncbi.nlm.nih.gov/articles/PMC6253751/)

### Inferences
- Implementation for a wrist-HR-only band:
  - Compute Edwards TRIMP, which is simpler and robust to HRR errors, or Banister TRIMP from the HR stream.
  - Keep EWMA "fitness" (τ ≈ 42 d) and "fatigue" (τ ≈ 7 d) per user, with form = fitness − fatigue.
  - Use EWMA rather than a rolling-average ACWR. Impellizzeri's critique applies to both, so present it only as a "load trend" and not as an injury-risk score.
- Ramp guard: cap the planned weekly load increase at roughly 10% (or about 3–5 CTL points a week for TSS-like units), and treat it as a conservative default rather than a proven threshold. Buist shows a stricter ramp does not reduce injuries for novices, so a hard block on overshoot isn't justified. Prefer warnings.
- Monotony guard: if 7-day monotony exceeds 2.0, insert an easy or rest day and vary session sizes. For longevity users this rule mainly stops the coach from prescribing identical moderate sessions every day.

### Gaps
- Gabbett's ACWR "sweet spot" of 0.8–1.3 and the danger zone above 1.5 (BJSM 2016) come from prior knowledge and were not verified this session. They come from team-sport cohorts and are contested (see above).
- No validated TRIMP thresholds were found for general-population or longevity users. Personal baselines are needed.

## 2. Readiness: HRV-guided, RHR-only, sleep-based adjustment

### Takeaway
HRV-guided training gives similar or slightly better fitness gains than fixed plans, usually with fewer hard sessions. The canonical rule is a 7-day rolling lnRMSSD compared with an SWC band of mean ± 0.5 SD over a longer baseline. If the rolling value falls outside the band, swap the hard session for easy work or rest. Evidence for RHR-only guidance is weak and mostly practitioner-level.

### Cited Findings
- Kiviniemi et al. 2007 (Eur J Appl Physiol 101:743–751): 26 moderately fit men were assigned to predefined training, HRV-guided training or control for 4 weeks of 40-minute runs, each at low or high intensity. Daily morning HF-HRV decided the session: high intensity if HRV held or rose, low or rest if it fell. Between groups, VO2peak changes were not significantly different. The authors still concluded HRV prescription improves fitness effectively. — [Kiviniemi 2007 PDF](http://lifemedicalcontrol.com/LMC_Pro/wp-content/uploads/2011/08/Kiviniemi.pdf); [Semantic Scholar](https://www.semanticscholar.org/paper/Endurance-training-guided-individually-by-daily-Kiviniemi-Hautala/9423055991cb4fec572ee0313c85401e7b052422)
- Vesterinen et al. 2016 (MSSE): 40 recreational runners were assigned to HRV-guided or predefined training. The HRV group did fewer HIIT sessions and still improved 3 km performance more. — [ResearchGate](https://www.researchgate.net/publication/295900195_Individual_Endurance_Training_Prescription_with_Heart_Rate_Variability)
- Javaloyes et al. (IJSPP 2019), recreational and trained cyclists:
  - Method: a 7-day rolling lnRMSSD average was compared with an SWC of baseline mean ± 0.5 × SD. When the rolling value fell outside the SWC, the session changed from moderate or high intensity to low intensity or rest.
  - Results: the HRV-guided group improved peak power by 5.1 ± 4.5%, VT2 by 13.9 ± 8.8% and 40-min time trial performance by 7.3 ± 4.5%.
  — [ResearchGate](https://www.researchgate.net/publication/325434300_Training_Prescription_Guided_by_Heart_Rate_Variability_in_Cycling); [Alan Couzens PDF copy](https://www.alancouzens.com/blog/Training_prescription_guided_by_HRV_in_cycling.pdf)
- Meta-analyses disagree:
  - Granero-Gallegos et al. 2020 (IJERPH) found a larger VO2max effect for HRV-guided training than for control training, with the best results in amateur and female subgroups.
  - Other pooled analyses found no significant VO2max difference between HRV-guided and predefined training. These include Medicina/Applied Sciences 2020 and Manresa-Rocamora et al. 2021, a methodological SR/MA (PMC8507742).
  — [Granero-Gallegos 2020](https://www.mdpi.com/1660-4601/17/21/7999/htm); [Applied Sciences 2020 SR/MA](https://www.mdpi.com/2076-3417/10/23/8532); [Manresa-Rocamora 2021](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8507742/); [J Sci Med Sport 2021 wearable HRV SR/MA](https://www.sciencedirect.com/science/article/pii/S1440244021001080)
- HRV-guided high-intensity functional training produced similar health and fitness gains to predetermined training, with less effort. — [MDPI JFMK 6(4):102](https://www.mdpi.com/2411-5142/6/4/102)
- 2025 cyclists study: individual training was prescribed from HRV, heart rate and well-being scores, which shows composite readiness inputs in use. — [Scientific Reports 2025](https://www.nature.com/articles/s41598-025-13540-z)
- RHR-only heuristics are practitioner sources only:
  - An RHR elevation of about 5 bpm or more above personal baseline is commonly treated as a warning. A 3–4 bpm rise is within daily noise.
  - An elevation lasting 3 or more consecutive days is seen as a stronger sign of non-functional overreaching or illness.
  - A rule of thumb is to reduce that day's training if RHR is more than 5% above baseline, and to reduce until it normalises if it is more than 10% above.
  — [Welltory blog](https://welltory.com/blog/overtraining-hrv-drops-resting-heart-rate); [TrainingPeaks coach blog](https://www.trainingpeaks.com/coach-blog/the-4-signs-of-overtraining/); [Outside Run](https://run.outsideonline.com/training/recovery/think-youre-overtraining-check-your-resting-heart-rate/) (low-quality evidence)
- One study compared morning and nocturnal HR/HRV responses to intensified training in recreational runners. This is relevant because the Mi Band gives nocturnal HR. — [PMC11541970](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11541970/) (full text not retrieved)

### Inferences
- Codable readiness rule, adapted from Javaloyes/Kiviniemi:
  - Baseline = 30–60 day mean and SD of the nightly metric. Use nocturnal RMSSD if the band exposes RR intervals; otherwise use nocturnal minimum or average RHR.
  - Today's value = 7-day rolling mean. The normal band is baseline ± 0.5 SD.
  - Inside the band: run the plan as written.
  - RHR above the band (HRV below), or a single-day RHR at least 5 bpm above baseline: downgrade hard sessions to Zone 2 or easy, and keep easy sessions easy.
  - Outside the band for 3 or more days, or RHR at least 10% above baseline: rest or active recovery only, and suggest checking for illness.
- How much to reduce: the studies use a binary swap (hard → low intensity or rest) rather than a percentage reduction. Mirroring that (intensity class downgrade, volume kept or trimmed) is the most evidence-faithful choice.
- Sleep: no RCT found for sleep-guided prescription. A reasonable heuristic is a downgrade when last night's sleep was under about 6 h or under about 75% of the person's learned need, combined with the RHR flag.

### Gaps
- No trial validates RHR-only (no HRV) daily prescription in general-population users.
- No trial of sleep-duration-guided session selection was found.
- Not found: evidence on how wrist PPG nocturnal HRV accuracy affects HRV-guided rules.

## 3. Missed sessions and same-day rescheduling (evening exercise and sleep)

### Takeaway
Coaching practice: don't stack or double up missed work. Move a missed key session only if it doesn't crowd the next key session; drop easy or recovery sessions. For a same-day move, exercise ending at least 4 h before sleep has no measurable sleep cost. Inside 4 h, prefer light strain. Avoid vigorous exercise ending 1 h or less before bed.

### Cited Findings
- Coaching guidance:
  - Classify the missed session as key (long or intervals) or non-key (recovery, short aerobic, core).
  - Reschedule key sessions only if that doesn't affect other workouts.
  - Non-key sessions can simply be dropped.
  - Stacking missed sessions onto later days "can backfire and lead to fatigue or injury".
  — [Be The Fear coaching blog](https://www.bethefear.com.au/be-the-fear-blog/what-to-do-when-you-miss-a-workout) (practitioner source)
- Stutz, Eiholzer & Spengler 2019 (Sports Med 49:269–287), SR/MA of 23 studies on evening exercise in healthy people:
  - Evening exercise raised REM latency (+7.7 min) and slow-wave sleep (+1.3 percentage points) and lowered stage-1 sleep (−0.9 pp).
  - The authors concluded that evening exercise does not impair sleep and, if anything, does the opposite.
  - Exception: sleep-onset latency, total sleep time and sleep efficiency may be impaired after vigorous exercise ending 1 h or less before bedtime.
  - Higher physical stress relative to a person's usual activity was associated with lower sleep efficiency and more wake after sleep onset.
  — [Springer](https://link.springer.com/article/10.1007/s40279-018-1015-0)
- Leota et al. 2025 (Nature Communications), about 14,689 WHOOP users and about 4 million nights over 1 year:
  - Later and higher-strain exercise was associated with delayed sleep onset, shorter and poorer sleep, higher nocturnal RHR and lower nocturnal HRV.
  - Bouts ending at least 4 h before sleep onset were not associated with sleep changes, regardless of strain.
  - Recommendation: finish at least 4 h before sleep, or choose lighter strain inside that window.
  — [Nature Communications](https://www.nature.com/articles/s41467-025-58271-x); [Monash](https://research.monash.edu/en/publications/dose-response-relationship-between-evening-exercise-and-sleep/)
- High-intensity evening exercise did not disrupt sleep in endurance runners. — [Eur J Appl Physiol 2019](https://link.springer.com/article/10.1007/s00421-019-04280-w)
- 150,000 nights of real-world data argued against discouraging evening physical activity. — [PMC8599432](https://pmc.ncbi.nlm.nih.gov/articles/PMC8599432/)

### Inferences
Codable missed-session rules:
1. **Priority order.** Readiness-permitting, the key session of the week ranks first. Default order: interval/VO2 > long Zone 2 > strength (if fewer than 2 strength sessions done this week) > other easy sessions.
2. **Missed easy session.** Drop it, and optionally add a little volume to the next easy day. Don't re-add it in full.
3. **Missed key session.**
   - If tomorrow is easy, move the key session to tomorrow.
   - If tomorrow is also a key session, keep the higher-priority one and drop the other.
   - Never place two hard days back to back, and never two sessions in one day.
4. **Same-day reschedule (morning → evening).** Compute the time to the user's typical sleep onset, learned from band data.
   - At least 4 h left: offer the original session.
   - 1–4 h left: offer a lower-strain version (Zone 2 or easy strength).
   - Under 1 h: offer mobility or a walk only, or defer to tomorrow.
   - Scale the strictness by "relative strain" (Stutz), so a session that is unusually hard for this user gets stricter treatment.
5. **Weekly floor.** If the WHO minimums are at risk (strength < 2 days, aerobic < 150 moderate-equivalent min), prefer short "minimum dose" sessions over skipping.

### Gaps
- No peer-reviewed study was found on outcomes of different missed-session policies (skip vs reschedule vs merge). This is practitioner consensus only.
- No evidence was found on the minimum recovery gap between two sessions on the same day for general-population users.

## 4. Weekly structure, periodisation and dose (fitness, Zone 2/VO2max, strength, longevity)

### Takeaway
- Anchor the plan on WHO 2020 doses: 150–300 min moderate or 75–150 min vigorous aerobic activity a week, plus strength training on at least 2 days.
- Build mostly low intensity with 1–2 hard sessions a week; a 4×4 at 90–95% HRmax is a well-evidenced VO2max session.
- Strength at 30–60 min a week captures most of the mortality benefit.
- Deload every 4–8 weeks by cutting volume 40–60%.
- For longevity, step counts plateau at about 6–8k (age 60+) or 8–10k (under 60).

### Cited Findings
- WHO 2020 (Bull et al., BJSM):
  - Adults should do 150–300 min a week of moderate or 75–150 min of vigorous aerobic activity, or an equivalent combination.
  - Muscle strengthening at moderate or greater intensity, working all major muscle groups, on at least 2 days a week.
  - "Some physical activity is better than none" and more is better.
  — [BJSM / PMC7719906](https://pmc.ncbi.nlm.nih.gov/articles/PMC7719906/); [WHO guidelines PDF](https://iris.who.int/server/api/core/bitstreams/faa83413-d89e-4be9-bb01-b24671aef7ca/content)
- Helgerud et al. 2007 (MSSE 39:665–671), 40 moderately trained men, 3 sessions a week for 8 weeks with work matched across groups:
  - 4×4 min at 90–95% HRmax with 3 min recovery at 70% raised VO2max by 7.2%.
  - 15/15 intervals raised it by 5.5%.
  - Long slow distance (70% HRmax) and lactate-threshold work (85%) produced no significant change.
  - Stroke volume rose about 10%, and only with intervals.
  — [Helgerud 2007 PDF](https://rcc.hslu.ch/fileadmin/user_upload/downloads/sport/Aerobic_High-Intensity_Intervals_Improve_J.Helgerud_2007.pdf)
- Intensity distribution:
  - Polarised training showed a small VO2peak advantage over other distributions (SMD 0.24, 95% CI 0.01–0.48; 17 studies, 437 athletes). This is reported via secondary summaries as Oliveira et al. 2024.
  - Rosenblat et al. found polarised marginally better in elite athletes, with the relationship reversing toward pyramidal in recreational athletes.
  - A 2024 multilevel meta-analysis in trained cyclists examined distribution, duration and volume.
  — [J Sci Med Sport 2024 multilevel MA](https://www.sciencedirect.com/science/article/pii/S1440244024005966); [PMC12568352: TID theory review 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12568352/); summary statistics via [pheidi.training](https://pheidi.training/articles/polarized-vs-pyramidal-training/) and [sensai.fit](https://www.sensai.fit/blog/polarized-vs-threshold-vs-pyramidal-training-intensity-distribution) (secondary; verify the primary papers)
- Muscle strengthening (Momma et al. 2022, BJSM, cohort meta-analysis):
  - The association with mortality is J-shaped, with the largest reduction (about 10–20%) at about 30–60 min a week for all-cause mortality, cardiovascular disease and cancer.
  - For diabetes the curve is L-shaped.
  - Combined with aerobic activity, risk was about 40% lower for all-cause mortality, 46% lower for CVD and 28% lower for cancer.
  — [PMC9209691](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9209691/)
- Steps (Paluch et al. 2022, Lancet Public Health, 15 cohorts): the mortality benefit plateaus at about 6,000–8,000 steps a day for age 60+ and about 8,000–10,000 for under 60. Higher counts showed no harm. A 2025 Lancet Public Health dose–response meta-analysis updates this. — [Paluch 2022](https://www.thelancet.com/journals/lanpub/article/PIIS2468-2667(21)00302-9/fulltext); [Lancet Public Health 2025](https://www.thelancet.com/journals/lanpub/article/PIIS2468-2667(25)00164-1/fulltext)
- Deloading (Bell et al. 2023, Sports Med Open, Delphi of strength and physique coaches): deload after about 4–8 weeks of progressive training, for 5–7 days, cutting volume about 40–60% while keeping intensity and exercises the same. — [Springer](https://link.springer.com/article/10.1186/s40798-023-00633-0)
- A one-week deload during supervised resistance training was tested in an RCT (PeerJ 2024). — [PeerJ](https://peerj.com/articles/16777/) (outcome details not retrieved)

### Inferences
Suggested goal templates (per week, before readiness adjustment):

| Goal | Aerobic | Strength | Notes |
|---|---|---|---|
| Longevity / general fitness | 150–200 min, about 80% easy (Zone 2) plus 1 interval session | 2× full-body, about 30–45 min, non-consecutive days | Step target 7–10k by age |
| Zone 2 / VO2max | 3–4 easy sessions, one longer (60–90 min) | 1–2× | 1× 4×4 at 90–95% HRmax; add a 2nd hard day only if readiness is stable |
| Strength | 2–3 easy aerobic sessions (≥ 150 min moderate-equivalent total) | 3×, non-consecutive | Volume progression of about 5–10% a week |
| Weight | 200–300 min, mostly moderate | 2× (preserves lean mass) | Daily steps emphasised |

- Block structure: 3 build weeks plus 1 deload week (volume −40–50%, intensity kept), or 4+1 for strength. This sits within the Delphi's 4–8 week range.
- Hard-day spacing: at least 48 h between interval sessions and between strength sessions that work the same muscles.

### Gaps
- No RCT was found defining a minimal Zone 2 dose for longevity specifically. "Zone 2" as a longevity concept is mostly expert opinion; the WHO moderate-minutes framing is the evidence-based fallback.
- The primary paper for the Oliveira 2024 polarised MA could not be retrieved, so its numbers above come from secondary summaries.
- Seiler's 80/20 descriptive work (elite intensity distribution) wasn't fetched this session.
- Evidence on "weekend warrior" patterns (doses packed into 1–2 days) was not searched.

## 5. Adherence and behaviour change (implementation intentions, flexibility, JITAI, HeartSteps)

### Takeaway
Implementation intentions ("if-then" plans that state when and where) have small-to-medium effects on physical activity, d ≈ 0.24–0.31, and work better when they include barrier planning. Just-in-time nudges raise short-term activity, but the effect decays over weeks. Contextual walking prompts help; anti-sedentary prompts did not.

### Cited Findings
- Bélanger-Gravel et al. 2013 (Health Psychology Review), 26 studies: implementation intentions had an effect size of 0.31 [0.11, 0.51] after the intervention and 0.24 [0.13, 0.35] at follow-up. They were more effective when barrier management was included. — [Taylor & Francis](https://www.tandfonline.com/doi/abs/10.1080/17437199.2011.560095)
- A PLOS One 2018 SR/MA of RCTs also examined implementation intentions and physical activity in adults. — [PLOS One](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0206294)
- Reinforcing implementation intentions with imagery increased physical activity habit strength and behaviour (Divine et al. 2025, Br J Health Psychol). — [Wiley](https://bpspsychub.onlinelibrary.wiley.com/doi/full/10.1111/bjhp.12795)
- HeartSteps micro-randomised trial (Klasnja et al. 2019, Ann Behav Med), 44 adults over 6 weeks with 3,594 suggestions across 6,061 decision points:
  - Overall, a suggestion raised steps in the next 30 min by 14% (+35 steps).
  - A walking suggestion raised them by 24% (+59), and by 107% (+271) at the start of the study. The effect decayed over time.
  - Anti-sedentary suggestions had no detectable effect.
  — [Ann Behav Med](https://academic.oup.com/abm/article/53/6/573/5091257)
- JITAI meta-analysis: medium effect on objective behaviour change (g = 0.77, 95% CI 0.32–1.22) and a larger effect against waitlist (g = 1.65). — [PMC10373115](https://pmc.ncbi.nlm.nih.gov/articles/PMC10373115/)
- A 2026 review of JITAI RCTs on physical activity:
  - Step effects ranged from +371 to +1,327 steps a day, with high heterogeneity (I² = 85%).
  - MVPA effects ranged from +13 to +200 min a week.
  - 37 studies with 6,939 participants were included.
  — [Frontiers Public Health 2026](https://www.frontiersin.org/journals/public-health/articles/10.3389/fpubh.2026.1934024/full)
- An earlier systematic review of JITAIs to promote physical activity (Hardeman et al. 2019, IJBNPA). — [IJBNPA](https://link.springer.com/article/10.1186/s12966-019-0792-7)
- RCT of a just-in-time adaptive app to increase daily steps (AJPM 2024). — [AJPM](https://www.ajpmonline.org/article/S0749-3797(24)00315-5/fulltext) (results not retrieved)

### Inferences
- Onboarding: ask for an if-then plan per session slot (time, place, cue, e.g. "after morning coffee") plus one barrier plan ("if it rains, then indoor 4×4 on the bike").
- Nudges:
  - Send contextual walking or session prompts at the user's planned slot or at a detected idle window when readiness allows.
  - Cap the frequency, because effects decay with habituation. Rotate the wording.
  - Don't rely on generic "stand up" anti-sedentary prompts.
- Flexibility: let the user swap days and offer "minimum-dose" fallbacks (10–20 min). This is consistent with the WHO message that some activity beats none.

### Gaps
- No direct RCT comparison of flexible vs rigid exercise plans was found within the call budget.
- Habit-stacking-specific trials were not found. Habit formation via context-dependent repetition is supported indirectly by the imagery and implementation-intention work.
- HeartSteps V2/V3 (the 2020s versions with reinforcement learning) results were not retrieved.

## 6. Concrete thresholds and heuristics to code (summary)

### Takeaway
These are evidence-anchored defaults; each one should be configurable and versioned (`algo_version`).

### Cited Findings
- 7-day rolling HRV (or RHR) vs baseline ± 0.5 SD decides hard vs easy. — [Javaloyes 2019](https://www.researchgate.net/publication/325434300_Training_Prescription_Guided_by_Heart_Rate_Variability_in_Cycling)
- Monotony above 2.0 is a warning. — [Foster](https://science-cycling.org/wp-content/uploads/2019/07/Foster-presentatie-gecomprimeerd.pdf)
- Fitness and fatigue are tracked as EWMA with τ ≈ 42 d and 7 d. — [Fellrnr](https://fellrnr.com/wiki/Modeling_Human_Performance)
- Exercise should end at least 4 h before sleep for neutral sleep impact; avoid vigorous exercise in the last hour before bed. — [Leota 2025](https://www.nature.com/articles/s41467-025-58271-x); [Stutz 2019](https://link.springer.com/article/10.1007/s40279-018-1015-0)
- VO2max session: 4×4 min at 90–95% HRmax with 3 min recovery at about 70%. — [Helgerud 2007](https://rcc.hslu.ch/fileadmin/user_upload/downloads/sport/Aerobic_High-Intensity_Intervals_Improve_J.Helgerud_2007.pdf)
- Strength 2 or more days a week, about 30–60 min a week in total. — [WHO 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7719906/); [Momma 2022](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9209691/)
- Aerobic 150–300 min moderate or 75–150 min vigorous a week. — [WHO 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7719906/)
- Deload every 4–8 weeks: 5–7 days at −40–60% volume. — [Bell 2023](https://link.springer.com/article/10.1186/s40798-023-00633-0)
- Steps 6–8k (age 60+) or 8–10k (under 60) daily for the mortality plateau. — [Paluch 2022](https://www.thelancet.com/journals/lanpub/article/PIIS2468-2667(21)00302-9/fulltext)
- RHR ≥ 5 bpm above baseline means downgrade; elevated for 3 or more days means rest or check for illness. — practitioner only: [TrainingPeaks](https://www.trainingpeaks.com/coach-blog/the-4-signs-of-overtraining/)

### Inferences
Decision order for "today's session":
1. Hard red flags: RHR ≥ 10% above baseline, an illness flag, or 3 or more days out of band. Result: rest or recovery.
2. Readiness out of band. Result: downgrade hard → easy, keep the duration.
3. Fatigue: ATL far above CTL, or monotony above 2. Result: easy day.
4. Otherwise run the planned session. Pick by priority, catching up on a missed key session only if the gap rules allow it.
5. Apply the time-to-bed rule for evening sessions.
6. Check the weekly WHO floor. Add a short fallback session if the user is behind and readiness allows.

### Gaps
- None of these combined decision trees has been validated as a whole in a general-population RCT. They are a synthesis.
