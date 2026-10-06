import 'types.dart';

final class SleepSession {
  SleepSession(this.minutes);

  /// Every minute from first asleep to last asleep, wake gaps included.
  final List<Minute> minutes;

  DateTime get start => minutes.first.ts;
  DateTime get end => minutes.last.ts.add(const Duration(minutes: 1));
  Duration get inBed => end.difference(start);

  int _count(bool Function(Stage) f) => minutes.where((m) => f(m.stage)).length;
  Duration get asleep => Duration(minutes: _count((s) => s.asleep));
  Duration stage(Stage s) => Duration(minutes: _count((x) => x == s));
  double get efficiency =>
      inBed.inMinutes == 0 ? 0 : asleep.inMinutes / inBed.inMinutes;
}

final class SleepParams {
  const SleepParams({
    this.baseNeedHours = 7.5,
    this.debtFactor = 0.5,
    this.strainFactor = 0.03,
    this.debtCapHours = 2,
    this.maxWakeGapMinutes = 30,
    this.maxQuietGapMinutes = 90,
    this.quietGapMaxSteps = 30,
    this.minSessionMinutes = 60,
    this.minNapMinutes = 20,
    this.learnNights = 14,
    this.minNeedHours = 6.5,
    this.maxNeedHours = 9.5,
  });
  final double baseNeedHours;
  final double debtFactor;
  final double strainFactor;
  final double debtCapHours;
  final int maxWakeGapMinutes;

  /// A longer wake still belongs to the same sleep when it's quiet: up to
  /// [maxQuietGapMinutes] with at most [quietGapMaxSteps] steps (lying
  /// awake). Seen 6 Oct: 31 min awake at 05:28 with 0 steps split a
  /// 7 h 22 m night into 5 h + a "nap".
  final int maxQuietGapMinutes, quietGapMaxSteps;
  final int minSessionMinutes;

  /// Daytime sleep at least this long counts as a nap.
  final int minNapMinutes;

  /// Nights with recovery needed before the base need is learned.
  final int learnNights;
  final double minNeedHours, maxNeedHours;
}

/// Splits minutes (sorted, one per minute) into sleep sessions. Runs of
/// sleep separated by wake/unknown gaps up to `maxWakeGapMinutes` merge.
List<SleepSession> detectSessions(
  List<Minute> minutes, [
  SleepParams p = const SleepParams(),
]) {
  // Runs of asleep minutes: [first, last] indices.
  final runs = <(int, int)>[];
  for (var i = 0; i < minutes.length; i++) {
    if (!minutes[i].stage.asleep) continue;
    if (runs.isNotEmpty) {
      final (a, b) = runs.last;
      if (minutes[i].ts.difference(minutes[b].ts).inMinutes <= 1) {
        runs[runs.length - 1] = (a, i);
        continue;
      }
    }
    runs.add((i, i));
  }
  // Merge across short wakes, or longer quiet ones.
  final merged = <(int, int)>[];
  for (final r in runs) {
    if (merged.isNotEmpty) {
      final (a, b) = merged.last;
      final gap = minutes[r.$1].ts.difference(minutes[b].ts).inMinutes;
      var steps = 0;
      for (var k = b + 1; k < r.$1; k++) {
        steps += minutes[k].steps;
      }
      if (gap <= p.maxWakeGapMinutes ||
          (gap <= p.maxQuietGapMinutes && steps <= p.quietGapMaxSteps)) {
        merged[merged.length - 1] = (a, r.$2);
        continue;
      }
    }
    merged.add(r);
  }
  return [
    for (final (a, b) in merged)
      if (SleepSession(minutes.sublist(a, b + 1)).asleep.inMinutes >=
          p.minSessionMinutes)
        SleepSession(minutes.sublist(a, b + 1)),
  ];
}

/// One past night for the debt calculation.
final class NightRecord {
  const NightRecord({required this.needHours, required this.sleptHours});
  final double needHours;
  final double sleptHours;
}

/// Shortfall over up to the last 7 nights, capped.
double sleepDebtHours(
  List<NightRecord> last7, [
  SleepParams p = const SleepParams(),
]) {
  final debt = last7
      .take(7)
      .fold<double>(0, (a, n) => a + (n.needHours - n.sleptHours).clamp(0, 24));
  return debt.clamp(0, p.debtCapHours);
}

/// One night for learning the base need.
final class NeedSample {
  const NeedSample({required this.sleptHours, required this.recovery});
  final double sleptHours;
  final double recovery;
}

/// Your base need: the median sleep on the best-recovered third of nights,
/// clamped to [SleepParams.minNeedHours]–[SleepParams.maxNeedHours]. Falls
/// back to [SleepParams.baseNeedHours] with fewer than
/// [SleepParams.learnNights] nights.
double learnedBaseNeed(
  List<NeedSample> nights, [
  SleepParams p = const SleepParams(),
]) {
  if (nights.length < p.learnNights) return p.baseNeedHours;
  final byRecovery = [...nights]
    ..sort((a, b) => b.recovery.compareTo(a.recovery));
  final top = [
    for (final n in byRecovery.take((nights.length / 3).ceil())) n.sleptHours,
  ]..sort();
  final mid = top.length ~/ 2;
  final median = top.length.isOdd ? top[mid] : (top[mid - 1] + top[mid]) / 2;
  return median.clamp(p.minNeedHours, p.maxNeedHours);
}

double sleepNeedHours({
  required double debtHours,
  required double strainYesterday,
  SleepParams p = const SleepParams(),
  double? baseHours,
}) =>
    (baseHours ?? p.baseNeedHours) +
    p.debtFactor * debtHours +
    p.strainFactor * strainYesterday;

/// 0–100, capped.
double sleepPerformance(double sleptHours, double needHours) =>
    needHours <= 0 ? 100 : (100 * sleptHours / needHours).clamp(0, 100);
