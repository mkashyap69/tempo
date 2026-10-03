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
    this.sleepPerf,
    this.rhr,
    this.hrvProxy,
    this.recovery,
    this.calibrating = true,
    this.algoVersion = types.algoVersion,
  });

  final DateTime date; // local midnight
  final double strain;
  final double trimp;
  final int hrMax;
  final DateTime? sleepStart, sleepEnd;
  final double? sleptHours, needHours, sleepPerf;
  final double? rhr, hrvProxy;
  final double? recovery;
  final bool calibrating;
  final int algoVersion;
}

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
  });
  final StrainParams strain;
  final SleepParams sleep;
  final RecoveryParams recovery;
  final int defaultHrMax;
  final double defaultHrRest;
  final int baselineDays;
}

/// Scores [date]. [minutes] should cover at least noon the day before to
/// noon the day after. [history] holds earlier days, newest first.
DailyScore scoreDay({
  required DateTime date,
  required List<Minute> minutes,
  List<StressReading> stress = const [],
  List<DailyScore> history = const [],
  ScoringParams p = const ScoringParams(),
}) {
  final day = DateTime(date.year, date.month, date.day);
  final sessions = detectSessions(minutes, p.sleep);

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
  final dayMinutes = minutes.where(
    (m) =>
        !m.ts.isBefore(wake) && (nextSleep == null || m.ts.isBefore(nextSleep)),
  );

  final prevMax = history.isEmpty ? p.defaultHrMax : history.first.hrMax;
  final hrMax = updatedHrMax(prevMax, minutes.map((m) => m.hr));

  final rhr = night == null ? null : restingHr(night.minutes);
  final recent = history.take(p.baselineDays).toList();
  final rhrBase = Baseline.of(recent.map((d) => d.rhr));
  final hrRest = rhr ?? rhrBase?.mean ?? p.defaultHrRest;

  final t = trimp(
    dayMinutes.map((m) => m.hr),
    hrRest: hrRest,
    hrMax: hrMax.toDouble(),
  );
  final strain = strainFromTrimp(t, p.strain);

  double? slept, need, perf;
  if (night != null) {
    slept = night.asleep.inMinutes / 60;
    final debt = sleepDebtHours([
      for (final d in history.take(7))
        if (d.needHours != null && d.sleptHours != null)
          NightRecord(needHours: d.needHours!, sleptHours: d.sleptHours!),
    ], p.sleep);
    need = sleepNeedHours(
      debtHours: debt,
      strainYesterday: history.isEmpty ? 0 : history.first.strain,
      p: p.sleep,
    );
    perf = sleepPerformance(slept, need);
  }

  double? hrv;
  if (night != null) {
    final inSleep = stress
        .where((s) => !s.ts.isBefore(night!.start) && s.ts.isBefore(night.end))
        .map((s) => s.value)
        .toList();
    if (inSleep.isNotEmpty) {
      hrv = inSleep.reduce((a, b) => a + b) / inSleep.length;
    }
  }

  final nights = recent.where((d) => d.sleptHours != null).length;
  final calibrating = nights < p.recovery.calibrationNights;
  final rec = recoveryScore([
    RecoveryInput(
      value: hrv,
      baseline: Baseline.of(recent.map((d) => d.hrvProxy)),
      higherIsBetter: false,
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
    sleepPerf: perf,
    rhr: rhr,
    hrvProxy: hrv,
    recovery: rec,
    calibrating: calibrating,
  );
}
