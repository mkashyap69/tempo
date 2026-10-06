import 'dart:math';

import 'baseline.dart';
import 'recovery.dart';
import 'resting_hr.dart';
import 'sleep.dart';
import 'strain.dart';
import 'types.dart' as types;
import 'types.dart' hide algoVersion;

/// One derived row of `daily_scores`. A "day" runs from waking on [date]
/// to the next main sleep.
final class DailyScore {
  const DailyScore({
    required this.date,
    required this.strain,
    required this.trimp,
    required this.hrMax,
    this.sleepStart,
    this.sleepEnd,
    this.sleptHours,
    this.needHours,
    this.napHours = 0,
    this.baseNeedHours,
    this.sleepPerf,
    this.rhr,
    this.hrvProxy,
    this.recovery,
    this.calibrating = true,
    this.algoVersion = types.algoVersion,
    this.source = bandSource,
    this.hrv,
    this.hrvKind,
  });

  final DateTime date; // local midnight
  final double strain;
  final double trimp;
  final int hrMax;
  final DateTime? sleepStart, sleepEnd;
  final double? sleptHours, needHours, sleepPerf;

  /// Daytime sleep after waking on [date], counted against tomorrow's debt.
  final double napHours;

  /// The base need used tonight, learned once there is enough history.
  final double? baseNeedHours;
  final double? rhr, hrvProxy;
  final double? recovery;
  final bool calibrating;
  final int algoVersion;

  /// Where the data came from: [bandSource], `apple_health` or
  /// `health_connect`. Baselines only ever compare days of one source.
  final String source;

  /// Real HRV for the night (ms, geometric mean), from a Health source.
  /// [hrvProxy] stays the band's stress index.
  final double? hrv;

  /// `sdnn` or `rmssd`: different scales, never one baseline.
  final String? hrvKind;
}

/// [DailyScore.source] of days scored from the Mi Band.
const bandSource = 'band';

final class StressReading {
  const StressReading(this.ts, this.value);
  final DateTime ts;
  final int value;
}

final class ScoringParams {
  const ScoringParams({
    this.strain = const StrainParams(),
    this.sleep = const SleepParams(),
    this.recovery = const RecoveryParams(),
    this.defaultHrMax = 190,
    this.defaultHrRest = 60,
    this.baselineDays = 30,
    this.needDays = 60,
  });
  final StrainParams strain;
  final SleepParams sleep;
  final RecoveryParams recovery;
  final int defaultHrMax;
  final double defaultHrRest;
  final int baselineDays;

  /// Days of history the base sleep need is learned from.
  final int needDays;
}

/// The main sleep ending on the morning of a day, the naps after it, and
/// where that day's waking hours start and end.
final class DaySleep {
  const DaySleep({
    required this.night,
    required this.naps,
    required this.wake,
    required this.nextSleep,
  });

  /// Longest session ending in (day-1 14:00, day 14:00], if any.
  final SleepSession? night;

  /// Shorter sleeps (≥ [SleepParams.minNapMinutes], < 3 h asleep) that start
  /// after [wake] and before the next main sleep, oldest first.
  final List<SleepSession> naps;

  /// End of [night], else 07:00.
  final DateTime wake;

  /// Start of the next main sleep (≥ 3 h asleep) after [wake], if seen.
  final DateTime? nextSleep;
}

/// Splits [minutes] around [date] into its night and naps (see [DaySleep]).
DaySleep daySleep({
  required DateTime date,
  required List<Minute> minutes,
  SleepParams p = const SleepParams(),
}) {
  final day = DateTime(date.year, date.month, date.day);
  // Find naps too; only sessions past minSessionMinutes can be the night.
  final all = detectSessions(
    minutes,
    SleepParams(
      maxWakeGapMinutes: p.maxWakeGapMinutes,
      maxQuietGapMinutes: p.maxQuietGapMinutes,
      quietGapMaxSteps: p.quietGapMaxSteps,
      minSessionMinutes: p.minNapMinutes,
    ),
  );
  final sessions = [
    for (final s in all)
      if (s.asleep.inMinutes >= p.minSessionMinutes) s,
  ];

  // Main sleep: longest session ending in (day-1 14:00, day 14:00].
  final windowEnd = day.add(const Duration(hours: 14));
  final windowStart = windowEnd.subtract(const Duration(days: 1));
  SleepSession? night;
  for (final s in sessions) {
    if (s.end.isAfter(windowStart) && !s.end.isAfter(windowEnd)) {
      if (night == null || s.asleep > night.asleep) night = s;
    }
  }

  // Day = wake → start of the next session that begins after waking.
  final wake = night?.end ?? day.add(const Duration(hours: 7));
  DateTime? nextSleep;
  for (final s in sessions) {
    if (s.start.isAfter(wake) &&
        s.asleep.inMinutes >= 180 &&
        (nextSleep == null || s.start.isBefore(nextSleep))) {
      nextSleep = s.start;
    }
  }
  // Naps: shorter daytime sleep between waking and the next main sleep.
  final napEnd = nextSleep ?? day.add(const Duration(hours: 22));
  final naps = [
    for (final s in all)
      if (s != night &&
          s.start.isAfter(wake) &&
          s.start.isBefore(napEnd) &&
          s.asleep.inMinutes < 180)
        s,
  ];
  return DaySleep(night: night, naps: naps, wake: wake, nextSleep: nextSleep);
}

/// Scores [date]. [minutes] should cover at least noon the day before to
/// noon the day after. [history] holds earlier days, newest first.
/// [extraTrimp] adds load HR misses (strength sessions, see
/// [strengthCorrection]).
///
/// [source] tags the day; baselines, calibration and the learned sleep
/// need use only earlier days of the same source, because a watch's resting
/// HR or HRV sits on a different level from the band's. [hrv] (ms) and
/// [hrvKind] are the night's real HRV from a Health source. [sourceRhr] is
/// the source's own resting HR, used only when the night has no HR.
DailyScore scoreDay({
  required DateTime date,
  required List<Minute> minutes,
  List<StressReading> stress = const [],
  List<DailyScore> history = const [],
  ScoringParams p = const ScoringParams(),
  double extraTrimp = 0,
  String source = bandSource,
  double? hrv,
  String? hrvKind,
  double? sourceRhr,
}) {
  final day = DateTime(date.year, date.month, date.day);
  final sl = daySleep(date: day, minutes: minutes, p: p.sleep);
  final night = sl.night, wake = sl.wake, nextSleep = sl.nextSleep;
  final napHours = sl.naps.fold<int>(0, (a, s) => a + s.asleep.inMinutes) / 60;
  final dayMinutes = minutes.where(
    (m) =>
        !m.ts.isBefore(wake) && (nextSleep == null || m.ts.isBefore(nextSleep)),
  );

  // defaultHrMax doubles as a user-set floor (Settings → HR max).
  final prevMax = history.isEmpty
      ? p.defaultHrMax
      : max(history.first.hrMax, p.defaultHrMax);
  final hrMax = updatedHrMax(prevMax, minutes.map((m) => m.hr));

  final rhr = night == null ? null : restingHr(night.minutes) ?? sourceRhr;
  final same = [
    for (final d in history)
      if (d.source == source) d,
  ];
  final recent = same.take(p.baselineDays).toList();
  final rhrBase = Baseline.of(recent.map((d) => d.rhr));
  final hrRest = rhr ?? rhrBase?.mean ?? p.defaultHrRest;

  final t =
      trimp(
        dayMinutes.map((m) => m.hr),
        hrRest: hrRest,
        hrMax: hrMax.toDouble(),
        floor: p.strain.floor,
      ) +
      max(0, extraTrimp);
  final strain = strainFromTrimp(t, p.strain);

  final baseNeed = learnedBaseNeed([
    for (final d in same.take(p.needDays))
      if (d.sleptHours != null && d.recovery != null && !d.calibrating)
        NeedSample(sleptHours: d.sleptHours!, recovery: d.recovery!),
  ], p.sleep);
  double? slept, need, perf;
  if (night != null) {
    slept = night.asleep.inMinutes / 60;
    final debt = sleepDebtHours([
      for (final d in history.take(7))
        if (d.needHours != null && d.sleptHours != null)
          NightRecord(
            needHours: d.needHours!,
            sleptHours: d.sleptHours! + d.napHours,
          ),
    ], p.sleep);
    need = sleepNeedHours(
      debtHours: debt,
      strainYesterday: history.isEmpty ? 0 : history.first.strain,
      p: p.sleep,
      baseHours: baseNeed,
    );
    perf = sleepPerformance(slept, need);
  }

  double? stressHrv;
  if (night != null) {
    final inSleep = stress
        .where((s) => !s.ts.isBefore(night.start) && s.ts.isBefore(night.end))
        .map((s) => s.value)
        .toList();
    if (inSleep.isNotEmpty) {
      stressHrv = inSleep.reduce((a, b) => a + b) / inSleep.length;
    }
  }
  final realHrv = night == null || hrv == null || hrv <= 0 ? null : hrv;

  final nights = recent.where((d) => d.sleptHours != null).length;
  final calibrating = nights < p.recovery.calibrationNights;
  final rec = recoveryScore([
    RecoveryInput(
      value: stressHrv,
      baseline: Baseline.of(recent.map((d) => d.hrvProxy)),
      higherIsBetter: false,
      weight: p.recovery.wHrv,
    ),
    // HRV is log-normal: compare ln(ms) against ln(ms) of the same kind.
    RecoveryInput(
      value: realHrv == null ? null : log(realHrv),
      baseline: Baseline.of([
        for (final d in recent)
          if (d.hrv != null && d.hrv! > 0 && d.hrvKind == hrvKind) log(d.hrv!),
      ]),
      higherIsBetter: true,
      weight: p.recovery.wHrv,
    ),
    RecoveryInput(
      value: rhr,
      baseline: rhrBase,
      higherIsBetter: false,
      weight: p.recovery.wRhr,
    ),
    RecoveryInput(
      value: perf,
      baseline: Baseline.of(recent.map((d) => d.sleepPerf)),
      higherIsBetter: true,
      weight: p.recovery.wSleep,
    ),
  ], p.recovery);

  return DailyScore(
    date: day,
    strain: strain,
    trimp: t,
    hrMax: hrMax,
    sleepStart: night?.start,
    sleepEnd: night?.end,
    sleptHours: slept,
    needHours: need,
    napHours: napHours,
    baseNeedHours: baseNeed,
    sleepPerf: perf,
    rhr: rhr,
    hrvProxy: stressHrv,
    recovery: rec,
    calibrating: calibrating,
    source: source,
    hrv: realHrv,
    hrvKind: realHrv == null ? null : hrvKind,
  );
}
