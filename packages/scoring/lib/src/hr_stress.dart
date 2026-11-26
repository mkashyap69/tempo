import 'dart:math';

import 'baseline.dart';
import 'daily.dart';
import 'sleep.dart';
import 'stress_day.dart';
import 'types.dart';

/// Stress from heart rate alone, for sources with no stress index (Apple
/// Health, Health Connect; P1, docs/research/Pulse comparison.md §7).
///
/// The idea: while you sit still and awake, heart rate above your own quiet
/// daytime level is mostly the nervous system, not the muscles. So only
/// still, awake minutes outside workouts are scored, each against your
/// quiet daytime heart rate from earlier days. This is a wellness estimate
/// from heart rate, not a measure of how you feel. It is our own model;
/// every constant is a starting value to calibrate.
///
/// Readings come out on the band's 1–100 scale, one per 5-minute block, so
/// [StressDay] and the Stress screen treat both sources alike: calm under
/// [stressMedium] (40), high from [stressHigh] (60).
final class HrStressParams {
  const HrStressParams({
    this.stillWindow = 2,
    this.minHourStill = 15,
    this.wakingFrom = 6,
    this.wakingTo = 22,
    this.quietQuantile = .1,
    this.minDays = 4,
    this.minSd = 3.0,
    this.fallbackSd = 7.0,
    this.slope = .81,
    this.mid = 1.5,
    this.minBlockStill = 3,
    this.minHrMinutesPerHour = 20,
  });

  /// A minute is still when it and this many minutes either side have no
  /// steps.
  final int stillWindow;

  /// Still minutes with heart rate an hour needs to count towards the
  /// day's quiet heart rate: a mostly moving hour says nothing about rest.
  final int minHourStill;

  /// Waking hours used for the quiet heart rate (local, [from, to)).
  final int wakingFrom, wakingTo;

  /// The day's quiet heart rate is this quantile of its hourly still means.
  final double quietQuantile;

  /// Earlier days with a quiet heart rate before the reference is your own;
  /// until then the score is provisional and uses [fallbackSd].
  final int minDays;

  /// Smallest spread of the quiet-HR baseline, bpm: day-to-day quiet HR is
  /// steady, and a tiny spread would turn a few beats into "high".
  final double minSd;

  /// Spread used while the baseline is still learning, bpm.
  final double fallbackSd;

  /// Logistic from z (bpm above quiet ÷ spread) to 0–100: [mid] is 50,
  /// z = 1 reads 40 (medium starts), z = 2 reads 60 (high starts), z = 0
  /// reads about 23.
  final double slope, mid;

  /// Still minutes a 5-minute block needs to give a reading.
  final int minBlockStill;

  /// Below this many minutes with heart rate per waking hour the watch
  /// samples too rarely for a stress view ([HrStressCoverage.enough]).
  final int minHrMinutesPerHour;
}

/// How much heart rate the waking day had.
final class HrStressCoverage {
  const HrStressCoverage(this.wakingHours, this.hrMinutes, this.minPerHour);
  final int wakingHours, hrMinutes;
  final int minPerHour;

  double get perHour => wakingHours == 0 ? 0 : hrMinutes / wakingHours;
  bool get enough => wakingHours > 0 && perHour >= minPerHour;
}

/// One day of heart-rate stress.
final class HrStressDay {
  const HrStressDay({
    required this.readings,
    required this.quietHr,
    required this.reference,
    required this.provisional,
    required this.coverage,
  });

  /// Awake readings, one per scored 5-minute block, 1–100.
  final List<StressReading> readings;

  /// Today's own quiet heart rate (feeds later days' baseline), or null.
  final double? quietHr;

  /// The quiet heart rate readings were judged against, or null when
  /// nothing could be scored.
  final double? reference;

  /// The baseline had fewer than [HrStressParams.minDays] earlier days.
  final bool provisional;
  final HrStressCoverage coverage;
}

bool _inAny(DateTime t, List<(DateTime, DateTime)> spans) =>
    spans.any((s) => !t.isBefore(s.$1) && t.isBefore(s.$2));

/// Indexes of [minutes] that are still and awake: no steps within
/// [HrStressParams.stillWindow] minutes, not asleep or in bed, outside every
/// sleep in [sleeps] and every span in [workouts]. [minutes] must be one per
/// minute, oldest first.
List<int> stillAwakeMinutes(
  List<Minute> minutes, {
  List<SleepSession> sleeps = const [],
  List<(DateTime, DateTime)> workouts = const [],
  HrStressParams p = const HrStressParams(),
}) {
  final sleepSpans = [for (final s in sleeps) (s.start, s.end)];
  final out = <int>[];
  for (var i = 0; i < minutes.length; i++) {
    final m = minutes[i];
    if (m.hr == null || m.stage.asleep || m.inBed || m.offWrist) continue;
    var still = true;
    for (
      var j = max(0, i - p.stillWindow);
      j <= min(minutes.length - 1, i + p.stillWindow);
      j++
    ) {
      if (minutes[j].steps > 0) {
        still = false;
        break;
      }
    }
    if (!still) continue;
    if (_inAny(m.ts, sleepSpans) || _inAny(m.ts, workouts)) continue;
    out.add(i);
  }
  return out;
}

/// The day's quiet heart rate: the [HrStressParams.quietQuantile] of the
/// mean heart rate of its still minutes in each waking hour that has at
/// least [HrStressParams.minHourStill] of them. Null with no such hour.
double? quietDaytimeHr(
  List<Minute> minutes,
  List<int> still, [
  HrStressParams p = const HrStressParams(),
]) {
  final byHour = <DateTime, List<int>>{};
  for (final i in still) {
    final t = minutes[i].ts;
    if (t.hour < p.wakingFrom || t.hour >= p.wakingTo) continue;
    final h = DateTime(t.year, t.month, t.day, t.hour);
    byHour.putIfAbsent(h, () => []).add(minutes[i].hr!);
  }
  final means = [
    for (final xs in byHour.values)
      if (xs.length >= p.minHourStill) xs.reduce((a, b) => a + b) / xs.length,
  ];
  return quantile(means, p.quietQuantile);
}

/// Waking-hour heart-rate coverage of [minutes].
HrStressCoverage hrStressCoverage(
  List<Minute> minutes, [
  HrStressParams p = const HrStressParams(),
]) {
  final hours = <DateTime>{};
  var hr = 0;
  for (final m in minutes) {
    final t = m.ts;
    if (t.hour < p.wakingFrom || t.hour >= p.wakingTo) continue;
    if (m.stage.asleep || m.inBed) continue;
    hours.add(DateTime(t.year, t.month, t.day, t.hour));
    if (m.hr != null) hr++;
  }
  return HrStressCoverage(hours.length, hr, p.minHrMinutesPerHour);
}

/// 0–100 from z (bpm above the quiet reference ÷ spread).
double hrStressLevel(double z, [HrStressParams p = const HrStressParams()]) =>
    100 / (1 + exp(-p.slope * (z - p.mid)));

/// Heart-rate stress for one day of [minutes] (one per minute, oldest
/// first). [priorQuiet] are earlier days' [HrStressDay.quietHr], any order;
/// nulls are skipped.
HrStressDay hrStressDay(
  List<Minute> minutes, {
  List<SleepSession> sleeps = const [],
  List<(DateTime, DateTime)> workouts = const [],
  Iterable<double?> priorQuiet = const [],
  HrStressParams p = const HrStressParams(),
}) {
  final still = stillAwakeMinutes(
    minutes,
    sleeps: sleeps,
    workouts: workouts,
    p: p,
  );
  final quiet = quietDaytimeHr(minutes, still, p);
  final prior = priorQuiet.whereType<double>().toList();
  final base = prior.length >= 2 ? Baseline.robust(prior) : null;
  final provisional = prior.length < p.minDays || base == null;
  final reference = provisional ? (base?.mean ?? quiet) : base.mean;
  final sd = provisional ? p.fallbackSd : max(base.sd, p.minSd);
  final coverage = hrStressCoverage(minutes, p);
  if (reference == null) {
    return HrStressDay(
      readings: const [],
      quietHr: quiet,
      reference: null,
      provisional: provisional,
      coverage: coverage,
    );
  }
  // One reading per 5-minute block of the clock, from its still minutes.
  final blocks = <DateTime, List<int>>{};
  for (final i in still) {
    final t = minutes[i].ts;
    final b = DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute - t.minute % bandStressStepMinutes,
    );
    blocks.putIfAbsent(b, () => []).add(minutes[i].hr!);
  }
  final keys = blocks.keys.toList()..sort();
  final readings = <StressReading>[];
  for (final k in keys) {
    final xs = blocks[k]!;
    if (xs.length < p.minBlockStill) continue;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    final level = hrStressLevel((mean - reference) / sd, p);
    readings.add(StressReading(k, level.round().clamp(1, 100)));
  }
  return HrStressDay(
    readings: readings,
    quietHr: quiet,
    reference: reference,
    provisional: provisional,
    coverage: coverage,
  );
}
