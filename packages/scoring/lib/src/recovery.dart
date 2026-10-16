import 'dart:math';

import 'baseline.dart';

enum RecoveryColor { red, yellow, green }

final class RecoveryInput {
  const RecoveryInput({
    required this.value,
    required this.baseline,
    required this.higherIsBetter,
    required this.weight,
  });
  final double? value;
  final Baseline? baseline;
  final bool higherIsBetter;
  final double weight;

  /// Signed z (higher = better), or null when not computable.
  double? get z {
    final v = value, b = baseline;
    if (v == null || b == null || b.sd == 0) return null;
    final raw = (v - b.mean) / b.sd;
    return higherIsBetter ? raw : -raw;
  }
}

final class RecoveryParams {
  const RecoveryParams({
    this.slope = 1.5,
    this.calibrationNights = 14,
    this.wHrv = 0.4,
    this.wRhr = 0.3,
    this.wSleep = 0.3,
  });
  final double slope;
  final int calibrationNights;
  final double wHrv, wRhr, wSleep;
}

/// 0–100, or null if no input is computable. Missing inputs drop out and
/// the remaining weights are renormalised to sum to 1.
double? recoveryScore(
  List<RecoveryInput> inputs, [
  RecoveryParams p = const RecoveryParams(),
]) {
  var wsum = 0.0, acc = 0.0;
  for (final i in inputs) {
    final z = i.z;
    if (z == null) continue;
    wsum += i.weight;
    acc += i.weight * z;
  }
  if (wsum == 0) return null;
  return 100 / (1 + exp(-p.slope * acc / wsum));
}

RecoveryColor recoveryColor(double score) => score >= 67
    ? RecoveryColor.green
    : score >= 34
    ? RecoveryColor.yellow
    : RecoveryColor.red;

/// v1 coaching: target strain range from today's recovery colour.
({double low, double high}) targetStrain(RecoveryColor c) => switch (c) {
  RecoveryColor.green => (low: 14, high: 18),
  RecoveryColor.yellow => (low: 10, high: 14),
  RecoveryColor.red => (low: 0, high: 10),
};

/// Points taken off recovery for night vitals moving the wrong way
/// (breathing rate, SpO₂, temperature; z positive = worse than your
/// normal): 4 per SD beyond 1.5, at most 8 a signal and 15 in all. Never
/// adds: a better-than-usual night is already in HRV and resting HR.
double recoveryPenalty(Iterable<double?> worseZ) {
  var p = 0.0;
  for (final z in worseZ) {
    if (z == null || z <= 1.5) continue;
    p += min(8, 4 * (z - 1.5));
  }
  return min(15, p);
}
