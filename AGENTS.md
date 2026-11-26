# AGENTS.md

Instructions for any coding agent working on Tempo. The full project rules are in `CLAUDE.md`; read it first. This file adds the release rules every change must follow.

## Versioning

Every change that ships in the app gets a new version, so a build on a phone can be told apart from the one before it.

- The version lives in two places that must match: `version:` in `app/pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`) and `appVersion` / `appBuild` in `app/lib/src/core/version.dart`. `app/test/version_test.dart` fails if they differ.
- **Every commit that changes the app** (code, copy, assets) bumps both:
  - `BUILD` goes up by 1, always.
  - `PATCH` goes up by 1 for a fix or small change; `MINOR` goes up (PATCH back to 0) for a new screen, feature or phase; `MAJOR` stays 0 until the public release.
  - Docs-only or test-only commits don't bump.
- `appUiLabel` in `version.dart` names the UI generation (`v3 UI`); change it only when the UI generation changes.
- The version shows at the bottom of You (`Tempo 0.3.0 (2) · v3 UI`) and is in every feedback report.
- Put the new version in the commit message's first line, e.g. `0.3.1+3: Plan changes undo shows the days it restores`, and in the `docs/decisions.md` line for the change.

### History

| Version | What changed |
| --- | --- |
| 0.0.1+1 | Everything before versioning (v2 UI) |
| 0.3.0+2 | v3 UI: tabs Today · Train · (+) · Health · You, the call word, Body check, Plan changes with Undo, Privacy ledger, onboarding question, "If it feels wrong", after-session story, experiment suggestions; the version shown in You |
| 0.4.0+3 | Today and Health rebuilt to the v3 canvas: rings, call card, today's move, your day so far, one insight, the week; Health opens on Body check, then moments, Tempo Age, sleep, at a glance and Discoveries, with the charts one level down under Trends |
| 0.5.0+4 | Train rebuilt to the v3 canvas: the week as a Monday–Sunday agenda with change notes and status, plan changes summary, goal, strength freshness, quick start chips, cardio load |

Add a row with every bump.

## Seeing a change on a phone

The phone runs the build that was last installed. After pulling a branch, rebuild and reinstall (`flutter run --release` from `app/`, or the platform's release build); check the version at the bottom of You to confirm the phone has it.
