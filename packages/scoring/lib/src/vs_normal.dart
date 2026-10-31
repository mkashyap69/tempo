/// Today against your normal, for Today's number tiles.
library;

import 'dart:math';

/// Which way is better for a metric.
enum Better { higher, lower, neither }

enum Trend { up, down, flat }

final class VsNormal {
  const VsNormal(this.normal, this.delta, this.trend, this.good);

  /// The mean of the past values.
  final double normal;

  /// Today minus normal.
  final double delta;
  final Trend trend;

  /// True when the move is the better way, false when worse, null when flat
  /// or neither way is better.
  final bool? good;
}

/// [today] against the mean of [past] (nulls skipped; at least 5 values).
/// A change under half a standard deviation, or under [minDelta], is flat.
VsNormal? vsNormal(
  double? today,
  Iterable<double?> past, {
  Better better = Better.higher,
  double minDelta = 0,
}) {
  final xs = [for (final x in past) ?x];
  if (today == null || xs.length < 5) return null;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final sd = sqrt(
    xs.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) / xs.length,
  );
  final d = today - mean;
  if (d.abs() < max(sd / 2, minDelta)) {
    return VsNormal(mean, d, Trend.flat, null);
  }
  final trend = d > 0 ? Trend.up : Trend.down;
  final good = switch (better) {
    Better.higher => d > 0,
    Better.lower => d < 0,
    Better.neither => null,
  };
  return VsNormal(mean, d, trend, good);
}
