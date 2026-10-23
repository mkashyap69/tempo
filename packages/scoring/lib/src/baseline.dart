import 'dart:math';

final class Baseline {
  const Baseline(this.mean, this.sd, this.n);
  final double mean;
  final double sd;
  final int n;

  /// Mean and sample SD of the non-null [values]; null if fewer than 2.
  static Baseline? of(Iterable<double?> values) {
    final xs = values.whereType<double>().toList();
    if (xs.length < 2) return null;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    final v =
        xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        (xs.length - 1);
    return Baseline(mean, sqrt(v), xs.length);
  }

  /// Median and MAD × 1.4826 (the SD a normal distribution with that MAD
  /// would have) of the non-null [values]; null if fewer than 2. A week of
  /// illness or travel barely moves either, where it widens a sample SD
  /// and makes every later day look normal (algo 10). A MAD of 0 (half the
  /// values equal) falls back to the sample SD.
  static Baseline? robust(Iterable<double?> values) {
    final xs = values.whereType<double>().toList();
    if (xs.length < 2) return null;
    final med = quantile(xs, .5)!;
    final mad = quantile([for (final x in xs) (x - med).abs()], .5)! * 1.4826;
    return Baseline(med, mad > 0 ? mad : of(xs)!.sd, xs.length);
  }
}

/// Linear-interpolated quantile of [values] (q in 0..1); null if empty.
double? quantile(Iterable<double?> values, double q) {
  final xs = values.whereType<double>().toList()..sort();
  if (xs.isEmpty) return null;
  final pos = (xs.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo);
}
