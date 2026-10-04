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
}

/// Linear-interpolated quantile of [values] (q in 0..1); null if empty.
double? quantile(Iterable<double?> values, double q) {
  final xs = values.whereType<double>().toList()..sort();
  if (xs.isEmpty) return null;
  final pos = (xs.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo);
}
