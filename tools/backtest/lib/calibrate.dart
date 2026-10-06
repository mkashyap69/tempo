/// Strain calibration: which k puts your hardest real days at ~18.5.
library;

import 'package:scoring/scoring.dart';

/// Where the hardest days should land (PLAN.md: around 18–19).
const calibrationStrain = 18.5;

/// Quantile of daily TRIMP treated as "your hardest days".
const calibrationQuantile = .99;

/// Days with less HR than this are left out (band off, sparse export).
const calibrationMinHrMinutes = 600;

final class Calibration {
  const Calibration({
    required this.days,
    required this.k,
    required this.p50,
    required this.p90,
    required this.top,
  });

  /// Days with enough HR that went into the numbers.
  final int days;

  /// Suggested k: the [calibrationQuantile] day lands at
  /// [calibrationStrain].
  final double k;
  final double p50, p90;

  /// Hardest days, highest TRIMP first.
  final List<(DateTime, double)> top;

  /// Strain a day of [trimp] gets at the suggested [k].
  double strainAt(double trimp) => strainFromTrimp(trimp, StrainParams(k: k));
}

/// [trimpByDay] holds only days with enough HR. Null with under 30 days or
/// no load at the top quantile.
Calibration? calibrate(Map<DateTime, double> trimpByDay, {int top = 10}) {
  if (trimpByDay.length < 30) return null;
  final hi = quantile(trimpByDay.values, calibrationQuantile)!;
  if (hi <= 0) return null;
  final sorted = trimpByDay.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Calibration(
    days: trimpByDay.length,
    k: kForStrain(hi, calibrationStrain),
    p50: quantile(trimpByDay.values, .5)!,
    p90: quantile(trimpByDay.values, .9)!,
    top: [for (final e in sorted.take(top)) (e.key, e.value)],
  );
}
