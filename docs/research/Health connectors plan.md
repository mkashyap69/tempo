# Health connectors: Tempo without a Mi Band

As of Oct 6, 2026 · Status: decided and built (H0–H4); D1–D4 signed off by the owner, see docs/decisions.md. Device gates H2/H3 still to run.

## Summary

Let someone with no Mi Band 6 pick **Apple Health** (iOS, HealthKit) or **Health Connect** (Android) as their data source during onboarding, and get the same Today / Coach / Trends / Longevity experience from whatever their watch or ring writes there: heart rate, sleep and stages, steps, workouts, HRV, resting HR, SpO₂.

"Google Health" here means **Health Connect**. The Google Fit APIs are deprecated, and Health Connect is the on-device store that Fitbit, Pixel Watch, Samsung Health, Garmin, Oura, Mi Fitness and others write to. Both connectors are on-device stores read through local OS APIs, so the "fully on-device, no network" rule still holds.

The work is mostly a **seam**, not new scoring. Scoring already takes `List<Minute>` + stress readings and doesn't care where they came from. `tools/backtest/lib/health_export.dart` already maps Apple Health HR and sleep records onto minutes, and has been run on 2020–2026 data. The app already depends on the `health` plugin (write-only today, `app/lib/src/core/health_export.dart`). What's new is: read permissions, an append-only raw table for Health records, a resampler from records to minutes, a recovery variant that uses real HRV, and hiding band-only features.

## Decisions (owner, 2026-10-06)

D1 yes (read-only Health, not locked to the band), D2 one source per install, D3 yes (real HRV feeds Recovery), D4 stays personal and sideloaded. Where the build differs from the proposal below, docs/decisions.md wins: baselines are per source by filtering on `daily_scores.source` (no metric suffix), and the re-read window is 3 days with a 10-day re-read once a day.

### As proposed

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | Amend the locked "Mi Band 6 only / direct BLE only" decision in PLAN.md and CLAUDE.md to "Mi Band 6 over BLE, or Apple Health / Health Connect as a read-only source" | Yes. BLE stays the first-class path; Health is an alternative, never a runtime dependency for band users |
| D2 | One source at a time, or merge band + Health | **One primary source per install** in v1. Switching source starts fresh baselines. Merging (e.g. band for HR, Health for workouts) is H5, later |
| D3 | Recovery input when real HRV exists | Use HRV (ln RMSSD / ln SDNN, higher is better) in place of the stress proxy, as its own metric with its own baseline. Bump `algoVersion` |
| D4 | Audience | Still personal / sideloaded. If it ever goes to the App Store or Play, both stores add review requirements (privacy policy, Health Connect declaration form). Out of scope here |

## What each source gives us vs the band

| Signal | Mi Band 6 (today) | Apple Health | Health Connect | Gap / handling |
| --- | --- | --- | --- | --- |
| Heart rate | Every minute, all day | Apple Watch: ~every 4–10 min at rest, ~every 5 s in workouts; others vary | Depends on writer: Pixel/Fitbit, Samsung, Garmin write anything from per-minute to sparse | Resample to minutes, forward-fill short gaps, track **HR coverage** per day |
| Steps | Per minute | Intervals (often several min) | Intervals | Spread each interval's steps evenly across its minutes |
| Sleep + stages | Band flag, we stage from HR + motion | `SleepAnalysis`: inBed, asleepCore/Deep/REM, awake (watchOS 9+) | `SleepSessionRecord` with stages | **Use the source's stages as-is**; skip our `stageSleep` when stages exist |
| HRV | None (stress index as proxy) | SDNN, Apple Watch, mostly overnight | RMSSD (`HeartRateVariabilityRmssdRecord`) where the writer supports it | Better than the band: feeds Recovery directly (D3) |
| Resting HR | Derived from night minutes | `RestingHeartRate` daily | `RestingHeartRateRecord` | Derive ours when night HR is dense enough; else use the source's value |
| SpO₂ | Per minute at night | `OxygenSaturation` | `OxygenSaturationRecord` | Map into `spo2_samples` (quality null) |
| Stress | Band index | — | — | **Not available.** Stress screen hidden |
| Motion / intensity | Per minute | — | — | Not available; sleep detection only needed when no stages come with sleep |
| Off-wrist | Band kind code | — | — | No HR and no steps ⇒ `Stage.unknown` |
| Workouts | Band workout summaries + auto-detect | `HKWorkout` with type, start, end | `ExerciseSessionRecord` | New workout source `health`; auto-detect still runs on HR |
| Live HR | BLE HR service | Not streamable from the phone | Not available | Live workout becomes "start/stop timer", scored after the next Health read |
| Battery, firmware, band settings, alarms, vibration cues | Yes | — | — | Hidden for Health sources |

All plugin capabilities above (HRV type names, interval vs sample data, background read, change tokens) are **TODO(verify)** against the `health` plugin version we pin, the same way BLE layouts are verified against packet logs. The plugin source wasn't in the pub cache in the dev container.

## Architecture

The source sits where the BLE layers sit now. Everything from the local database up is unchanged, apart from feature gating.

```
Mi Band 6 ─ BLE ─ Huami protocol ─┐
                                  ├─► Sync service ─► Local DB ◄─► Scoring
Apple Health / Health Connect ────┘   (per source)     raw tables     (unchanged API)
   read via `health` plugin
```

### New package: `packages/health_source` (pure Dart)

No Flutter, no plugin imports, so it can be unit-tested and shared with `tools/backtest`.

- `HealthRecord`: `{uuid, type, start, end, value, unit, sourceApp, sourceDevice}`. One shape for both platforms.
- `MinuteGrid` moves here from `tools/backtest/lib/health_export.dart` and grows: steps spread over intervals, SpO₂, source-stage precedence (deep/REM/core beat awake, already the rule), HR forward-fill window as a parameter.
- `minutesFromRecords(records, from, to) → (minutes, coverage)`: the same `List<Minute>` scoring already takes, plus HR coverage per day.
- `hrvFromRecords(records, night) → HrvReading?`: mean ln(value) of readings inside the night, with kind `rmssd | sdnn`.
- Backtest's `readExport` then just parses XML into `HealthRecord`s and calls the same functions, so **the backtest and the live connector share one mapping**. Golden tests come from slices of the real export.xml (and later a Health Connect dump), with ids redacted, kept in `docs/health/` the way packet logs live in `docs/packets/`.

### Store (schema v10)

Raw stays append-only.

- `health_records` (append-only): `uuid` PK, `type`, `start`, `end`, `value`, `unit`, `source_app`, `source_device`, `fetched_at`. Raw, as read.
- `health_deletions` (append-only tombstones): `uuid`, `seen_at`. A record the user deleted in Health is never removed from `health_records`; the resampler skips tombstoned uuids. This keeps the append-only rule and still respects edits.
- `daily_scores`: add `source` (`band | apple_health | health_connect`), `hrv` (real HRV, nullable) and `hrv_kind`; `hrvProxy` keeps meaning "band stress".
- `baselines`: metric names gain a source suffix (`rhr@apple_health`), so z-scores never mix sources.
- `sync_state`: reuse with `device = 'apple_health' | 'health_connect'`, one cursor per data type.
- `minute_samples` stays band-only. Health minutes are derived on the fly from `health_records`, like naps are now (no derived per-minute table, so nothing to keep in step).

### App: `DataSource` seam

- `Keys.dataSource = band | apple_health | health_connect`, set in onboarding, changeable in Profile → Data source.
- `HealthSyncService` beside `SyncService`, same `SyncReport` and `sync_log` lines so Sync health works unchanged. Each run reads every type from `cursor − 48 h` to now (Health writers backfill late, e.g. a watch syncing in the morning), insert-or-ignore by uuid, then calls `ScoreService.recomputeFrom` for the touched days.
- `ScoreService._scoreOne` picks minutes from `decodeMinutes(db.minutesBetween)` (band) or `minutesFromRecords(db.healthRecordsBetween)` (Health). That is the only branch in scoring code.
- **Echo guard.** Tempo already *writes* nights and workouts to Health (`HealthExport`). With a Health source, filter out records whose source is Tempo's own bundle id, and turn off writing sleeps (we'd write back the night we just read). Exporting live workouts recorded in Tempo stays allowed.
- Feature gating by a `capabilities` provider derived from the source: `stress`, `liveHr`, `bandSettings`, `battery`, `alarm`, `motion`. Screens hide or swap cards from it rather than checking the source directly.

## Scoring changes

| Area | Change | Algo |
| --- | --- | --- |
| Strain | Unchanged formula. Gaps filled up to N min (start 10; Apple Watch's idle cadence). A day with HR coverage under 600 min is shown as "Partial data" and, as in cardio load now, drops out of means | 8 |
| Sleep | When the source supplies stages, use them; `detectSessions` only joins pieces (30-min rule, naps). If a source writes only in-bed/asleep with no stages, show the night unstaged, as for sparse band HR now | 8 |
| Recovery | Inputs become HRV (when present, sign +, weight 0.4), RHR (0.3), sleep performance (0.3). No HRV and no stress ⇒ RHR 0.5 + sleep 0.5. Same logistic, same 14-night calibrating | 8 |
| Resting HR | Ours if ≥ 60 % of night minutes have HR; else the source's daily resting HR | 8 |
| Longevity / Coach / Goals | No change; they read `daily_scores` and workouts | — |

Every formula change gets unit tests in `packages/scoring` (CLAUDE.md non-negotiable). The calibration constants (k, fill window, coverage threshold) are re-checked with `dart run backtest export.xml --calibrate` against the Apple Watch part of the export, not just the Mi Fit part.

## Platform work

| Concern | iOS (HealthKit) | Android (Health Connect) |
| --- | --- | --- |
| Setup | HealthKit capability, `NSHealthShareUsageDescription` (read) next to the existing update description | Read permissions in manifest, permissions-rationale activity, install prompt on Android < 14 (already in `HealthExport.enable`) |
| History | Everything the user has | Only 30 days before first grant unless `READ_HEALTH_DATA_HISTORY` is granted (TODO(verify)) — ask for it, so baselines don't start from zero |
| Background | **Health data is unreadable while the phone is locked.** Read on app open, on `BGAppRefresh`, and on HKObserverQuery background delivery if the plugin exposes it (else a small native channel) | WorkManager job (already exists); needs `READ_HEALTH_DATA_IN_BACKGROUND` on newer Health Connect (TODO(verify)) |
| Deletions | Anchored queries report deletes; plugin support TODO(verify), else re-read window and tombstone missing uuids | Changes API (`getChanges` with a token) reports deletes; same fallback |
| Rate limits | — | Health Connect rate-limits reads, more tightly in background: batch by type, one window per run |
| Gotcha | Read permission status is hidden by Apple (a "denied" looks like "no data"), so Sync health says "No HR in the last 24 h — check Health permissions" rather than "denied" | User can revoke per type in Health Connect settings; re-check on each run |

## UX

- **Onboarding**, first screen after backups: "How will Tempo get your data?" → Mi Band 6 (current pairing flow) · Apple Health / Health Connect (only the one for this OS). The Health path asks permissions, reads 90 days, shows "Found 82 nights, HR from Apple Watch, HRV yes", then the profile step. If 14+ nights come back with HR, Recovery is ready on day one instead of calibrating.
- **Source line** under the Today dials: "From Apple Health · Apple Watch · updated 07:42". A "Partial data" chip when HR coverage is low, with a tap-through explaining which signals were missing.
- **Hidden for Health sources:** Stress screen and stress cards, band explorer, pairing, battery, alarms, band settings, live HR. Live workout becomes a timer and a sport pick; strain arrives with the next read.
- **Profile → Data source:** shows the source, permissions per type, last read, "Switch source". Switching keeps all old data and scores (tagged with their source); new baselines start, and Recovery says "Calibrating on Apple Health (3 of 14 nights)".
- **Learn / Help:** one page on what each source gives and why scores can differ from the watch's own app.

## Phases

| Phase | Scope | Gate to move on |
| --- | --- | --- |
| H0 · Decisions + seam | D1–D4 logged in `decisions.md`; CLAUDE.md/PLAN.md updated; `packages/health_source` with `HealthRecord`, `MinuteGrid` moved from backtest; backtest uses it | Backtest output identical before and after the move; package tests pass |
| H1 · Store + scoring | Schema v10 (`health_records`, `health_deletions`, `daily_scores.source/hrv/hrv_kind`, source-suffixed baselines); algo 8 (stage pass-through, HRV recovery, coverage, RHR fallback); golden tests from export.xml slices | Backtest over the Apple Watch years: scores sane, recovery vs HRV-free variant compared, k re-checked |
| H2 · Apple Health read | Read permissions, `HealthSyncService` on iOS, echo guard, onboarding choice, capability gating, source line | 7 days on an iPhone + Apple Watch with no band: scores ready on opening the app each morning, nights match the Health app's sleep chart |
| H3 · Health Connect read | Same on Android, history + background permissions, changes/deletions, rate-limit handling | 7 days on an Android phone with a Health-Connect-writing watch (Pixel/Fitbit or Galaxy Watch): background job keeps scores current without opening the app |
| H4 · Polish | Switch source flow, Partial data explainer, Learn page, export/restore covers new tables | Switch band → Health → band on one install with no lost data and correct calibrating messages |
| H5 · Later (optional) | Merge mode: band primary, Health for workouts/HRV/other sensors | Only if D2 is revisited |

H0–H1 need no phone and can run now. H2/H3 need real devices; the dev container has no Xcode or Android SDK (see the backups entry in `decisions.md`), so the native sides are TODO(verify) until run on a phone. The current gates (C1, C4, P1/P2) are unaffected and keep running alongside, since band users see no change.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Sparse HR from some writers (e.g. every 10–30 min) | Strain under-counts, sleep staging impossible | Coverage per day, "Partial data", source stages; strain from workouts' HR where denser |
| Writers backfill late or rewrite records | Scores change after the morning | 48 h re-read window, rescoring touched days; show "updated 07:42" |
| HealthKit locked-device rule | No background scores on iOS until unlock | Read on open + refresh; set expectations in onboarding |
| HRV kinds differ (SDNN vs RMSSD) and by writer | Baselines not comparable | Baseline per source and kind; never mix |
| Our numbers differ from the watch's own app | Trust | Source line, Learn page, wellness wording; we compare against our own baseline, not the vendor's score |
| Echo loop with `HealthExport` | Double-counted nights/workouts | Filter own bundle id; no sleep export when Health is the source |
| Health Connect 30-day history default | Calibrating for 2 weeks | Request history permission at onboarding |
| Scope creep into a general multi-device app | Dilutes the band path | One source per install; band stays first-class; H5 only on request |
