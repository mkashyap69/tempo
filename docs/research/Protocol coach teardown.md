# Protocol coach teardown

As of Nov 24, 2026 · Proposal for the owner. Nothing here is decided until it lands in `docs/decisions.md`.

Subject: an early-access "AI coach" app built on Apple Health plus blood tests, called "the protocol app" here (competitor names stay out of the repo, `docs/decisions.md` 2026-10-16). Source: its public landing page only, read on 24 Nov 2026. Its blog, privacy page and web app were not read, so anything about how it stores or processes data is unknown.

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

## What it confirms about Health connectors

The protocol app shows a watch, band, ring and CGM in its marketing, but connects only to Apple Health. That supports the Nov 24 advice on WHOOP and Garmin: reach them through Apple Health and Health Connect, check what each app writes, and leave direct vendor APIs alone for the beta.

## Checklist

- [ ] L1 HR ceiling: plan card, live in-band display, recap line (algo note if strain is unchanged)
- [ ] L2 tomorrow diff on the wind-down card and notification
- [ ] L3 question templates for experiments; afternoon energy rating (schema bump)
- [ ] L7 wellness wording pass (with B5)
- [ ] L4 lab report import: add to backlog with a decision line
- [ ] L6 Founders cohort: owner decision for B6
- [ ] Open question: on-device model for "can I still train?" (L8)
