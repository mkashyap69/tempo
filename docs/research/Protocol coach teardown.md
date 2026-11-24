# Protocol coach teardown

As of Nov 24, 2026 · Proposal for the owner. Nothing here is decided until it lands in `docs/decisions.md`.

Subject: an early-access "AI coach" app built on Apple Health plus blood tests, called "the protocol app" here (competitor names stay out of the repo, `docs/decisions.md` 2026-10-16). Sources: its public landing page, read on 24 Nov 2026, and 16 screenshots of the iOS app (version 2.0.0, build 108) on its first day with one account, taken by the owner the same day (not stored in the repo, because they show personal details). Its blog and privacy page were not read. Where it processes data is inferred from the screens.

## Summary

The protocol app's pitch is **"Scores are the busywork. We do it for you."** It shows few numbers. It gives instructions ("Hold HR under 148 today. I'll handle the rest.") tied to a goal the user states in their own words, and it adjusts them every day.

What it is:

- **Platform:** iPhone and a web app. **Apple Health is its only health-data connection.** The page says so in the footer, though its marketing art shows a watch, band, ring and CGM. It reaches every one of those devices through Apple Health, the same way Tempo does.
- **Inputs:** Apple Health, blood-test reports the user uploads, and a home blood draw booked through a partner lab "where available".
- **Business:** free during early access. "Founders Edition" gives the first 1,000 users a numbered card, "yours for life". The company is a private limited company in India.
- **Regulatory stance:** "a general wellness product … does not diagnose, treat, cure, or prevent any disease". Phrases like "It is a pattern, not a diagnosis" and "prepare better questions for a qualified healthcare professional" are used throughout the page.

## What it does

| Feature | How it's shown |
| --- | --- |
| Goal in your words | "A real conversation, not a quiz." Example goal: "deadlift 180 again, no flare-up." The app maps a "protocol" to it |
| Three moments a day | **07:02 morning brief** (adherence 91 %, recovery 78 % +9, resting HR 48 −3, one line: "You slept through for the first time in eight days. Today we push the Zone 2 block to 52 minutes"). **18:24 workout recap** (HR band 50–190 with a ceiling, "In band 47/52 min", "Ceiling hits 2", "Exactly the stimulus we wanted"). **22:40 adaptation** (Zone 2 block 52 → 56 min, protein +12 g, wake window 06:50, "Tomorrow's protocol is set. Sleep on it.") |
| Small daily changes, bigger shifts when needed | "Micro-adjusted from your data daily; larger shifts when the goal needs them" |
| The Method | Question → Hypothesis → 2-week Experiment → Review → Guidance updated. The example is "Why does my energy dip at 3pm?", comparing meal timing, afternoon energy logs and sleep |
| Proactive agent | Unprompted: "Your afternoon HRV dips have coincided more often with Tuesday's strength sessions than with shorter sleep. Moving them to mornings is one experiment to consider." Prompted: "big week at work. can I still train?" → "Week rebalanced: calendar updated, tonight's wind-down moved to 10:15" |
| Blood work | Uploads, "100+ markers tracked", trends across panels ("Why has my ApoB crept up? … tracks your bulking phase") |
| Home blood draw | Booked through an independent partner, depending on location |
| "Always on" | A feed of overnight work ("02:14 ApoB drift flagged for Saturday's draw") |

## The app, screen by screen (screenshots, day 1)

**Layout.** There are four tabs: Home · Train · Food · Body. An **"Ask" bar with a mic** sits on the tab bar on every screen; while scrolling it shrinks to the tab icon plus the bar. Every screen opens on a "What it knows" chip and the avatar. Every screen uses the same template: a dark, warm gradient hero with **one large number and its unit**, **one first-person serif sentence**, then a segmented control, then a white sheet of cards. That makes it very consistent and easy to scan.

**Home.**
- "Good evening, *name*. Today is ◎ 3 targets." Below it, Recovery – · Sleep 7 h 00 · HRV –. Recovery and HRV were blank on day 1, although Body showed 7 of 7 nights of sleep.
- Two buttons: **Change today** and **Why this plan**.
- A goal card: "Lose fat, keep muscle". Its empty state is honest: "No weight or waist yet. Your Sunday weigh-in starts the line, and lifts you tell me will show whether muscle is holding." It's labelled "Set by *app* · Tue 24 Nov", with a Change button.
- A bottom sheet: **"TODAY · 1 OF 3 DONE / Next: Protein at every meal"** with a progress bar. It expands to a checklist grouped by Body / Food / Sleep:
  - Daily steps 8,000, ticked from data
  - Protein at every meal (1.6–2 g/kg spread over 3–4 meals; "log meals in chat")
  - Sleep 22:30–06:30, which **"ticks itself from your sleep"**
- No workout was among day 1's targets: all three were habits.

**Train.**
- Hero: "16 workouts in six weeks", read from Health, then Volume – · Done – · PRs 0, and This week / History / Progress.
- Progress has estimated 1RM ("Tell me your sets after a session. Two sessions of a lift and I can show where it's heading."), weekly volume in tonnes, and Consistency ("Once you have a plan, I mark each day against it. **Days with no data stay blank, never a miss.**").
- Cardio shows sessions and time over six weeks.
- Sets are logged only by chat, text or voice.

**Food.**
- Hero: protein in grams ("no target yet") and "Send me a photo of your next meal and I'll count it". Then kcal / carbs / fat, and Today / Trends.
- "Set your daily targets, suggested from your body goal":
  - Calories 1,500: "About 2,000 kcal keeps your weight (from your Apple Health energy over 2 weeks); 500 under loses about 0.5 kg a week; never under 1,500"
  - Fibre 30 g, carbs 40 % (150 g), fat 30 % (50 g)
  - **Use these / Adjust**
- Then a list of meals.

**Body.** Three segments:
- **Wearables:** last night 7 h 00 asleep · 7-night average 8 h 27 · target 8 h 00 · nights 7 of 7, with a bar chart of 7 nights. "Your signals" has a "Change view" chip and cards for steps, active energy and walking speed, each "since 25 Oct" with a delta. The deltas look broken: "↑9009.0" on 9,128 steps and "↑283.2" on 289.4 kcal, which suggests a near-empty first day was used as the baseline.
- **Body:** "Your weight, and where it's heading, shows here", Log today's weight, "What's changing" links to Food and Train, and the same steps chart again.
- **Blood:** "0 reports. Book a blood draw at home, or upload a recent test, and I'll tell you **what to act on, what to watch and what's fine.**" Upload takes a PDF (up to 25 MB), a photo, or up to 10 photos in order, under the heading "1 minute to read it". Footnote: "Your report stays private to you. *App* reads it to plan around it and never shares it." That implies the report is read on their server.

**What it knows (memory).**
- "Your file · updated today 21:42 · 5 things it knows · Pages 3 · Sources 5 · Forgotten 0". "Everything I plan with, in one place. Tap anything that's wrong and I'll fix it or forget it."
- Each line has its provenance ("What you told *app* · 24 Nov"):
  - Goals: lose fat while keeping muscle
  - Routine: trains Mon/Wed/Fri about 60 min; full gym; wakes 06:30, wants 8 h, bed by 22:30
  - Preferences: will report sets by text or voice
- **Never remember (+ Add):** "Name anything you'd rather *app* never wrote down." Up to 30 changes a day.

**Profile.**
- Hero: "1 day with *app*", "I know 5 things about you so far. The more you tell me, the sharper my calls get." Then Sources 1 · Brief – · Goal "Early days", and Edit goal / What it knows.
- Rows:
  - Your goal; What it knows; About you (age, sex)
  - Connected devices (Apple Health); Reminders and briefs (2 on); **iMessage: briefs and answers in Messages** (off); Sleep target; **Plan: "Protocol and the rules *app* follows"**
  - Units (coming soon); Your data: export everything; Delete account; Sign out (Sign in with Apple)

**What the screens confirm.**
- It's chat-first: meals by photo, sets by text or voice, and the goal and routine come from conversation. The memory and the reports live on their server. Without chat, Train and Food stay empty.
- Day 1 already has a goal, three targets and a sleep window, which makes it feel personal fast.
- Weak spots: Recovery and HRV blank despite a week of Health data; delta bugs; the steps chart shown twice; a generic 8,000-step target and a 1,500 kcal floor; no strain or training load at all.

## Where Tempo stands

Tempo already has or does better:

- **Android and Health Connect.** The protocol app has Apple Health only.
- **Everything stays on the phone, with transparent scores.** Every score carries an `algo_version`. An LLM coach almost certainly sends health data to a server and a model provider. That's unverified, because we didn't read their privacy page.
- **An adaptive plan with goals, periods and tapers** (P1/P2), today's picks sized to readiness (C7), and Move or skip with reasons (D1).
- **Journal experiments** (14 days, compared with the 14 days before, with covariates, 2026-10-16) and the impact engine. This is the same method as theirs, already built.
- **Morning brief leading with the call** (N2), wind-down with tomorrow's key session (2026-10-31), and rescoring when a workout ends (W2).
- **Blood markers in Tempo Age** (PhenoAge from nine markers entered by hand) and "what to ask the lab for" (U1).

Where it's ahead:

1. **Concrete targets inside a session.** "Hold HR under 148" plus an in-band recap is clearer than a zone name and strain.
2. **Showing tomorrow's changes as diffs** (52 → 56 min, +12 g) at a fixed evening moment, with the reason.
3. **Experiments that start from a question** the user has, not from a journal entry.
4. **Blood work as data over time.** Many markers are read from uploaded reports and charted against training phases. Ours are nine numbers typed in, used only for PhenoAge.
5. **Calendar awareness** ("big week at work").
6. **Talking to it:** goals in your words, and asking questions.
7. **Launch marketing:** numbered Founders spots and careful wellness wording.

## What to take, in our rules

| # | Idea | Fits our rules? | Cost | Recommendation |
| --- | --- | --- | --- | --- |
| L1 | **HR ceiling for easy sessions.** The plan card says "Keep HR under N" (top of Z2 from HR max or Karvonen). The live workout shows in band / over; the recap shows "In band 47/52 min · over the ceiling 2×" | Yes, all on the phone | S–M | **Do first.** It uses zones and live HR we already have, and makes "easy" concrete |
| L2 | **"Tomorrow is set" diff.** The wind-down card and notification show what changed in tomorrow's plan, as before → after, with one reason | Yes | S | **Do.** Same notification, no new kind, so the caps stay the same |
| L3 | **Question-first experiments.** "Ask a question" offers templates (afternoon dip, poor sleep, low recovery), each choosing the journal entries and the outcome. Add an optional afternoon energy rating next to the morning feel | Yes | M | **Do.** It's a new way into the engine we already have |
| L4 | **Lab report import.** Pick a PDF or photo, read it with on-device text recognition (iOS Vision / ML Kit), confirm each marker, store in an append-only `lab_results` table, chart markers over time against training phases | Yes, if text recognition runs on the phone | L | **Plan for after the beta.** Add to the Longevity backlog |
| L5 | **Calendar-aware week.** Read the phone calendar (read-only, on device) to suggest a lighter week when it's packed | Yes, but it's a new permission and needs a decisions line | M | Later. The week template (U3) covers most of it |
| L6 | **Founders cohort for the beta.** Numbered spots for wave 1 and 2 testers, with Pro for life | Marketing only | S | Consider for B6 |
| L7 | **Wellness wording.** Put "a pattern, not a diagnosis" and "questions for a qualified professional" into insight copy, store listings and the Health Connect declaration | Yes | S | **Do in B5** |
| L8 | **Chat coach / goal in your words** | **No.** Health data would go to a model provider, which breaks the end-to-end rule and the network allowlist. An on-device model is possible but untested | L | Don't do it now. Record an open question: whether an on-device model could answer "can I still train?" from the plan engine |
| L9 | **Home blood draw** | No: operations, regulation and a new network partner | — | Skip |

From the screenshots:

| # | Idea | Fits our rules? | Cost | Recommendation |
| --- | --- | --- | --- | --- |
| L10 | **Day targets that tick themselves.** Today's three to four targets (session, steps, sleep window, plus one habit from the goal) as one strip: "1 of 3 done · Next: …", with a progress bar. Each target ticks from data where it can ("ticks itself from your sleep") and is never marked missed without data | Yes. It uses the plan, step goal and sleep plan we already compute | S–M | **Do.** It's the clearest "what now" we've seen. It sits below the day's call and doesn't replace the rings |
| L11 | **"What Tempo uses" page.** Every input the plan and scores use, each with where it came from (you told us · measured from Health · estimated · default) and when: goal, availability and week template, HR max and resting HR, sleep need and window, step goal, weight, injuries, sources. Tap to correct; "estimated" items say what would firm them up. Pair it with **"The rules Tempo follows"** (plain-language plan rules, from `docs/decisions.md`) | Yes, all on the phone. It's a view over existing settings | M | **Do.** It's strong on trust, cheap for us, and needs no chat |
| L12 | **"Why this plan" one tap from Today**, next to Move or skip, as two equal buttons | Yes | S | **Do.** The reasons already exist (D1) |
| L13 | **Empty states that promise something.** Say what fills a card and when ("Two sessions of a lift and I can show where it's heading", "Your Sunday weigh-in starts the line", "Days with no data stay blank, never a miss"). Audit every empty card | Yes. Copy only | S | **Do**, as an F1 one-voice pass |
| L14 | **Food targets from Health.** Maintenance from active plus resting energy over 14 days; targets for losing fat or gaining (protein 1.6–2 g/kg from Health weight, fibre, kcal) with the arithmetic shown, and Use these / Adjust. Read dietary energy and protein from Health (read-only) when another app logs food. No photo logging | Mostly. It needs new Health kinds, a `TODO(verify)` and a decisions line | M | Later. A protein target as a day target (L10) is the cheap first step for "lose fat" and Get stronger |
| L15 | **Weight "where it's heading".** A Body view with the trend (7-day mean) and the rate per week against the goal | Yes. We read weight from Health (U2) | S | **Do** with L14, or alone |
| L16 | **Blood in three buckets:** act on · watch · fine, per marker, from reference ranges on the phone, in wellness wording. A lighter version of L4 | Yes | S once markers exist | With L4 |
| L17 | **A first day that feels personal.** Onboarding ends with today's targets and a sleep window already set, not "learning". Read 90 days of history at first launch so Recovery and HRV show on day 1 where Health has the data. Our 90-day first read of new kinds already does most of this; check that it reaches the first Today | Yes | S | **Verify on the first-run task test (F1)** |
| L18 | **Screen template.** One hero number with its unit and one first-person sentence per tab | Design | — | Compare with our Today and Progress at the next design review; no change now |
| — | Chat bar on every screen, meals by photo, sets by voice, iMessage briefs, a server-side memory | No (L8) | — | Skip. Our versions are typed logs, the strength log and notifications and widgets |

## What it confirms about Health connectors

The protocol app shows a watch, band, ring and CGM in its marketing, but connects only to Apple Health. That supports the Nov 24 advice on WHOOP and Garmin: reach them through Apple Health and Health Connect, check what each app writes, and leave direct vendor APIs alone for the beta.

## Checklist

- [ ] L10 day targets that tick themselves on Today ("1 of 3 done · Next: …")
- [ ] L11 "What Tempo uses" page and "The rules Tempo follows"
- [ ] L12 "Why this plan" next to Move or skip
- [ ] L13 empty-state copy pass
- [ ] L15 weight trend and rate on Body / Progress
- [ ] L17 check the first Today after onboarding shows Recovery and HRV from backfilled Health data
- [ ] L14 food targets from Health energy: decision line first
- [ ] L1 HR ceiling: plan card, live in-band display, recap line (algo note if strain is unchanged)
- [ ] L2 tomorrow diff on the wind-down card and notification
- [ ] L3 question templates for experiments; afternoon energy rating (schema bump)
- [ ] L7 wellness wording pass (with B5)
- [ ] L4 lab report import: add to backlog with a decision line
- [ ] L6 Founders cohort: owner decision for B6
- [ ] Open question: on-device model for "can I still train?" (L8)
