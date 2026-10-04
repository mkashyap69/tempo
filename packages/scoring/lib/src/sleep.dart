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
  final out = <SleepSession>[];
  int? start, lastAsleep;
  void close() {
    if (start != null && lastAsleep != null) {
      final s = SleepSession(minutes.sublist(start!, lastAsleep! + 1));
      if (s.asleep.inMinutes >= p.minSessionMinutes) out.add(s);
    }
    start = lastAsleep = null;
  }

  for (var i = 0; i < minutes.length; i++) {
    final m = minutes[i];
    if (lastAsleep != null &&
        m.ts.difference(minutes[lastAsleep!].ts).inMinutes >
            p.maxWakeGapMinutes) {
      close();
    }
    if (m.stage.asleep) {
      start ??= i;
      lastAsleep = i;
    }
  }
  close();
  return out;
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
