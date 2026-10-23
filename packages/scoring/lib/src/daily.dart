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
    this.sleepScore,
    this.vitalsPenalty = 0,
    this.rhrKind,
    this.bedEfficiency,
    this.latencyMinutes,
    this.debtHours,
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

  /// Sleep score (0–100; v3 from algo 10, see [sleepScoreV3]); null without
  /// a night.
  final double? sleepScore;

  /// Recovery points taken off for night vitals (algo 9).
  final double vitalsPenalty;

  /// Where [rhr] came from: [rhrFromSleep] or [rhrFromSource]. Baselines
  /// only compare one kind (algo 10). Null on rows before algo 10.
  final String? rhrKind;

  /// Asleep ÷ time in bed, when the source gave time in bed (algo 10).
  final double? bedEfficiency;

  /// Minutes from getting into bed to falling asleep, same condition.
  final int? latencyMinutes;

  /// Sleep debt going into the night that ended this morning, hours.
  final double? debtHours;
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
    this.female = false,
  });
  final StrainParams strain;
  final SleepParams sleep;
  final RecoveryParams recovery;
  final int defaultHrMax;
  final double defaultHrRest;
  final int baselineDays;

  /// Days of history the base sleep need is learned from.
  final int needDays;

  /// Banister's female TRIMP weighting (see [minuteTrimp]).
  final bool female;
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

/// Each day's autonomic recovery: the mean of its HRV and resting-HR
/// z-scores (HRV up, resting HR down = better) against the median and MAD
/// of [days] themselves, one kind of each at a time. Sleep length never
/// enters, so it can rank nights for [learnedBaseNeed] without picking the
/// longest ones (algo 10, loop L2). Days with no signal are left out.
List<NeedSample> needSamples(List<DailyScore> days) {
  String rk(DailyScore d) => d.rhrKind ?? rhrFromSleep;
  final rhrBase = Baseline.robust([
    for (final d in days)
      if (rk(d) == rhrFromSleep) d.rhr,
  ]);
  final hrvBase = <String, Baseline?>{
    for (final k in {for (final d in days) ?d.hrvKind})
      k: Baseline.robust([
        for (final d in days)
          if (d.hrvKind == k && d.hrv != null && d.hrv! > 0) log(d.hrv!),
      ]),
  };
  final proxyBase = Baseline.robust(days.map((d) => d.hrvProxy));
  double? z(double? v, Baseline? b, {bool up = true}) {
    if (v == null || b == null || b.sd <= 0) return null;
    final raw = (v - b.mean) / b.sd;
    return up ? raw : -raw;
  }

  return [
    for (final d in days)
      if (d.sleptHours != null)
        if ([
              z(rk(d) == rhrFromSleep ? d.rhr : null, rhrBase, up: false),
              z(
                d.hrv != null && d.hrv! > 0 ? log(d.hrv!) : null,
                hrvBase[d.hrvKind],
              ),
              z(d.hrvProxy, proxyBase, up: false),
            ].whereType<double>().toList()
            case final zs when zs.isNotEmpty)
          NeedSample(
            sleptHours: d.sleptHours!,
            autonomic: zs.reduce((a, b) => a + b) / zs.length,
          ),
  ];
}

/// Tonight's need from [history] (newest first, the night just scored
/// included when known): the learned base from [needDays] same-source
/// days, the debt from the last nights against each night's base, and
/// yesterday's strain. Shared by [scoreDay] and the app's Tonight card so
/// they can't disagree.
({double base, double debt, double need}) sleepNeedFrom({
  required List<DailyScore> history,
  required String source,
  ScoringParams p = const ScoringParams(),
  double? strainYesterday,
}) {
  final same = [
    for (final d in history)
      if (d.source == source) d,
  ];
  final base = learnedBaseNeed(
    needSamples(same.take(p.needDays).toList()),
    p.sleep,
  );
  final debt = sleepDebtHours([
    for (final d in history.take(p.sleep.debtNights))
      if (d.sleptHours != null)
        NightRecord(
          baseHours: (d.baseNeedHours ?? base)
              .clamp(p.sleep.minNeedHours, p.sleep.maxNeedHours)
              .toDouble(),
          sleptHours: d.sleptHours! + d.napHours,
        ),
  ], p.sleep);
  final need = sleepNeedHours(
    debtHours: debt,
    strainYesterday:
        strainYesterday ?? (history.isEmpty ? 0 : history.first.strain),
    p: p.sleep,
    baseHours: base,
  );
  return (base: base, debt: debt, need: need);
}

/// Scores [date]. [minutes] should cover at least noon the day before to
/// noon the day after. [history] holds earlier days, newest first.
/// [extraTrimp] adds load HR misses (strength sessions, see
/// [strengthCorrection]).
///
/// [source] tags the day; baselines, calibration and the learned sleep
/// need use only earlier days of the same source, because a watch's resting
/// HR or HRV sits on a different level from the band's. [hrv] (ms) and
/// [hrvKind] are the night's real HRV from a Health source, from
/// [hrvCount] readings. [sourceRhr] is the source's own resting HR, used
/// only when the night has no HR (and then never in one baseline with the
/// night's own, see [DailyScore.rhrKind]).
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
  int? hrvCount,
  double? sourceRhr,
  List<double?> vitalsZ = const [],
}) {
  final day = DateTime(date.year, date.month, date.day);
  final sl = daySleep(date: day, minutes: minutes, p: p.sleep);
  final night = sl.night, wake = sl.wake, nextSleep = sl.nextSleep;
  final napHours = sl.naps.fold<int>(0, (a, s) => a + s.asleep.inMinutes) / 60;
  final dayMinutes = minutes.where(
    (m) =>
        !m.ts.isBefore(wake) && (nextSleep == null || m.ts.isBefore(nextSleep)),
  );

  // defaultHrMax doubles as a user-set floor (Settings → HR max; the app
  // passes the age-predicted max when none is set).
  final prevMax = history.isEmpty
      ? p.defaultHrMax
      : max(history.first.hrMax, p.defaultHrMax);
  final hrMax = updatedHrMax(prevMax, minutes.map((m) => m.hr));

  final nightRhr = night == null ? null : restingHr(night.minutes);
  final rhr = night == null ? null : nightRhr ?? sourceRhr;
  final rhrKind = rhr == null
      ? null
      : nightRhr != null
      ? rhrFromSleep
      : rhrFromSource;
  final same = [
    for (final d in history)
      if (d.source == source) d,
  ];
  final recent = same.take(p.baselineDays).toList();
  // Days whose night vitals were off don't shape the normal (algo 10).
  final normal = [
    for (final d in recent)
      if (d.vitalsPenalty <= 0) d,
  ];
  String rk(DailyScore d) => d.rhrKind ?? rhrFromSleep;
  final rhrBase = rhrKind == null
      ? null
      : Baseline.robust([
          for (final d in normal)
            if (rk(d) == rhrKind) d.rhr,
        ]);
  final hrRest =
      rhr ??
      Baseline.robust([for (final d in recent) d.rhr])?.mean ??
      p.defaultHrRest;

  final t =
      trimp(
        dayMinutes.map((m) => m.hr),
        hrRest: hrRest,
        hrMax: hrMax.toDouble(),
        floor: p.strain.floor,
        female: p.female,
      ) +
      max(0, extraTrimp);
  final strain = strainFromTrimp(t, p.strain);

  double? slept, need, perf, suff, base, debt;
  if (night != null) {
    slept = night.asleep.inMinutes / 60;
    final n = sleepNeedFrom(history: history, source: source, p: p);
    base = n.base;
    debt = n.debt;
    need = n.need;
    perf = sleepPerformance(slept, need);
    suff = sleepSufficiency(slept, base);
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

  // HRV: tonight blended with the week's ln HRV, since one night's reading
  // swings 7–10 % on its own (Plews 2012); a night with few readings counts
  // for less (algo 10).
  final pastLn = [
    for (final d in normal)
      if (d.hrv != null && d.hrv! > 0 && d.hrvKind == hrvKind) log(d.hrv!),
  ];
  double? hrvValue;
  if (realHrv != null) {
    final week = [log(realHrv), ...pastLn.take(6)];
    hrvValue =
        .5 * log(realHrv) + .5 * week.reduce((a, b) => a + b) / week.length;
  }
  final hrvWeight =
      p.recovery.wHrv * (hrvCount == null ? 1 : min(1, hrvCount / 3));

  double? suffOf(DailyScore d) => d.sleptHours == null
      ? null
      : sleepSufficiency(
          d.sleptHours!,
          d.baseNeedHours ?? base ?? p.sleep.baseNeedHours,
        );
  final rec = recoveryScore([
    RecoveryInput(
      value: stressHrv,
      baseline: Baseline.robust(normal.map((d) => d.hrvProxy)),
      higherIsBetter: false,
      weight: p.recovery.wHrv,
    ),
    // HRV is log-normal: compare ln(ms) against ln(ms) of the same kind.
    RecoveryInput(
      value: hrvValue,
      baseline: Baseline.robust(pastLn),
      higherIsBetter: true,
      weight: hrvWeight,
    ),
    RecoveryInput(
      value: rhr,
      baseline: rhrBase,
      higherIsBetter: false,
      weight: p.recovery.wRhr,
    ),
    // Sleep against the base need, free of debt (algo 10, loop L3).
    RecoveryInput(
      value: suff,
      baseline: Baseline.robust(normal.map(suffOf)),
      higherIsBetter: true,
      weight: p.recovery.wSleep,
    ),
  ], p.recovery);
  final penalty = rec == null ? 0.0 : recoveryPenalty(vitalsZ);

  // Sleep score v3: base-need sufficiency, bedtime against the 14-night
  // median, continuity, and efficiency and latency from time in bed.
  double? score, bedEff;
  int? latency;
  if (night != null && suff != null) {
    int toNoon(DateTime t) => ((t.hour - 12) % 24) * 60 + t.minute;
    final beds = [
      for (final d in same.take(14))
        if (d.sleepStart != null) toNoon(d.sleepStart!),
    ]..sort();
    final span = bedSpan(night, minutes);
    if (span != null) {
      final inBed = span.end.difference(span.start).inMinutes;
      bedEff = inBed <= 0 ? null : night.asleep.inMinutes / inBed;
      latency = night.start.difference(span.start).inMinutes;
    }
    score = sleepScoreV3(
      sufficiency: suff,
      bedDeviationMinutes: beds.length < 5
          ? null
          : toNoon(night.start) - beds[beds.length ~/ 2],
      efficiency: bedEff,
      wasoMin: wasoMinutes(night),
      wakeBoutCount: wakeBouts(night),
      latencyMinutes: latency,
    ).score;
  }

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
    baseNeedHours: base,
    sleepPerf: perf,
    rhr: rhr,
    rhrKind: rhrKind,
    hrvProxy: stressHrv,
    recovery: rec == null ? null : max(0, rec - penalty).toDouble(),
    vitalsPenalty: penalty,
    sleepScore: score,
    bedEfficiency: bedEff,
    latencyMinutes: latency,
    debtHours: debt,
    calibrating: calibrating,
    source: source,
    hrv: realHrv,
    hrvKind: realHrv == null ? null : hrvKind,
  );
}
