import 'daily.dart';
import 'sleep.dart';

/// The band measures stress about once every 5 minutes, and only while
/// still: 43 of 480 minutes had a value in the 6 Oct debug log.
const bandStressStepMinutes = 5;

/// Readings further apart than this are drawn as a break in the line.
const stressGapMinutes = 30;

/// Awake stress levels (band scale 1–100).
const stressMedium = 40, stressHigh = 60;

/// One day's stress readings, split by whether you were asleep.
///
/// Asleep, the band stores a separate, lower "sleep stress": its debug log
/// gives (stress − 10) × 0.625 for every reading in a nap and a doze on
/// 6 Oct. So sleep readings are kept out of the awake average and levels.
final class StressDay {
  StressDay(this.awake, this.asleep);
  final List<StressReading> awake, asleep;

  double? get awakeAvg => _avg(awake);
  double? get asleepAvg => _avg(asleep);

  int _count(bool Function(int) f) => awake.where((r) => f(r.value)).length;

  /// Measured awake minutes per level: each reading stands for one band
  /// measuring step.
  int get calmMinutes =>
      _count((v) => v < stressMedium) * bandStressStepMinutes;
  int get mediumMinutes =>
      _count((v) => v >= stressMedium && v < stressHigh) *
      bandStressStepMinutes;
  int get highMinutes => _count((v) => v >= stressHigh) * bandStressStepMinutes;

  /// The awake hour with the highest mean, with at least 2 readings.
  int? get busiestHour {
    final byHour = <int, List<int>>{};
    for (final r in awake) {
      byHour.putIfAbsent(r.ts.hour, () => []).add(r.value);
    }
    int? best;
    double top = -1;
    for (final e in byHour.entries) {
      if (e.value.length < 2) continue;
      final m = e.value.reduce((a, b) => a + b) / e.value.length;
      if (m > top) {
        top = m;
        best = e.key;
      }
    }
    return best;
  }

  static double? _avg(List<StressReading> r) => r.isEmpty
      ? null
      : r.map((x) => x.value).reduce((a, b) => a + b) / r.length;
}

/// Splits [readings] by [sleeps] (the night and naps). Readings with no
/// value (0 or over 100) are dropped.
StressDay splitStress(List<StressReading> readings, List<SleepSession> sleeps) {
  bool asleep(DateTime t) =>
      sleeps.any((s) => !t.isBefore(s.start) && t.isBefore(s.end));
  final awake = <StressReading>[], slept = <StressReading>[];
  for (final r in readings) {
    if (r.value <= 0 || r.value > 100) continue;
    (asleep(r.ts) ? slept : awake).add(r);
  }
  return StressDay(awake, slept);
}
