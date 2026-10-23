/// Validation statistics for scores (docs/research/Algorithm review.md
/// §11): how they spread, how noisy they are day to day, how a new algo
/// moves them, and how they agree with a reference. Shared by the
/// backtest and the app's Developer → Score check.
library;

import 'dart:math';

import 'baseline.dart';
import 'recovery.dart';

/// One score, one value per date (nulls are days without it).
typedef Series = Map<String, double?>;

final class Spread {
  const Spread(this.n, this.p10, this.p50, this.p90);
  final int n;
  final double p10, p50, p90;
}

/// Percentiles of the non-null values; null when empty.
Spread? spread(Iterable<double?> values) {
  final xs = values.whereType<double>().toList();
  if (xs.isEmpty) return null;
  return Spread(
    xs.length,
    quantile(xs, .1)!,
    quantile(xs, .5)!,
    quantile(xs, .9)!,
  );
}

final class Noise {
  const Noise(this.pairs, this.typicalError, this.mdc95);
  final int pairs;

  /// SD of day-to-day differences ÷ √2: the typical error of one day.
  final double typicalError;

  /// Smallest change that is real with 95 % confidence: 1.96 · √2 · TE.
  final double mdc95;
}

/// Day-to-day noise from consecutive days (by [dates] order) that both
/// have a value. Real change is in there too, so this is an upper bound
/// on measurement noise. Null with fewer than 10 pairs.
Noise? noise(List<String> dates, Series s) {
  final diffs = <double>[];
  for (var i = 1; i < dates.length; i++) {
    final a = s[dates[i - 1]], b = s[dates[i]];
    if (a != null && b != null) diffs.add(b - a);
  }
  if (diffs.length < 10) return null;
  final m = diffs.reduce((a, b) => a + b) / diffs.length;
  final sd = sqrt(
    diffs.fold<double>(0, (a, d) => a + (d - m) * (d - m)) / (diffs.length - 1),
  );
  final te = sd / sqrt2;
  return Noise(diffs.length, te, 1.96 * sqrt2 * te);
}

/// Share of days per recovery colour.
Map<RecoveryColor, double> colours(Iterable<double?> recovery) {
  final xs = recovery.whereType<double>().toList();
  return {
    for (final c in RecoveryColor.values)
      c: xs.isEmpty
          ? 0
          : xs.where((x) => recoveryColor(x) == c).length / xs.length,
  };
}

final class Shift {
  const Shift(this.n, this.meanDelta, this.meanAbsDelta);
  final int n;
  final double meanDelta, meanAbsDelta;
}

/// How [now] moved against [before] on the dates both have.
Shift? shift(Series before, Series now) {
  final d = [
    for (final e in now.entries)
      if (e.value != null && before[e.key] != null) e.value! - before[e.key]!,
  ];
  if (d.isEmpty) return null;
  return Shift(
    d.length,
    d.reduce((a, b) => a + b) / d.length,
    d.map((x) => x.abs()).reduce((a, b) => a + b) / d.length,
  );
}

/// Days whose recovery colour differs between [before] and [now].
int colourChanges(Series before, Series now) => [
  for (final e in now.entries)
    if (e.value != null &&
        before[e.key] != null &&
        recoveryColor(e.value!) != recoveryColor(before[e.key]!))
      e.key,
].length;

final class Agreement {
  const Agreement(this.n, this.bias, this.loaLow, this.loaHigh);
  final int n;

  /// Mean of ours − reference.
  final double bias;

  /// 95 % limits of agreement (Bland & Altman 1986).
  final double loaLow, loaHigh;
}

/// Bland–Altman agreement of [ours] with [reference]; null under 3 pairs.
Agreement? agreement(Series reference, Series ours) {
  final d = [
    for (final e in ours.entries)
      if (e.value != null && reference[e.key] != null)
        e.value! - reference[e.key]!,
  ];
  if (d.length < 3) return null;
  final m = d.reduce((a, b) => a + b) / d.length;
  final sd = sqrt(
    d.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / (d.length - 1),
  );
  return Agreement(d.length, m, m - 1.96 * sd, m + 1.96 * sd);
}

/// Known-group check: on days whose night vitals were off ([penalty] > 0),
/// how often recovery before the penalty (`recovery + penalty`) still sat
/// below the median of the other days. HRV, resting HR and sleep should
/// agree with breathing, SpO₂ and temperature most of the time; null with
/// fewer than 3 such days or 10 others.
double? offDaysBelowMedian(List<({double recovery, double penalty})> days) {
  final off = [
    for (final d in days)
      if (d.penalty > 0) d.recovery + d.penalty,
  ];
  final rest = [
    for (final d in days)
      if (d.penalty <= 0) d.recovery,
  ];
  if (off.length < 3 || rest.length < 10) return null;
  final med = quantile(rest, .5)!;
  return off.where((r) => r < med).length / off.length;
}
