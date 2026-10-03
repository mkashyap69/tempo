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
