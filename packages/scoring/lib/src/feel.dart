/// Morning feel (1–5, asked before the day's call is read) against
/// Recovery: does the score track how you actually feel?
///
/// Agreement compares bands: feel 1–2 ↔ red, 3 ↔ yellow, 4–5 ↔ green.
/// Rank correlation (Spearman) says whether higher recovery goes with
/// feeling better at all, whatever the bands.
library;

import 'dart:math';

import 'recovery.dart';

/// Version stamped on comparisons made by these rules.
const feelAlgo = 'feel-1';

/// Rated mornings with a recovery score needed before comparing.
const feelMinPairs = 14;

/// Rank correlation at or above which Recovery "tracks" feel, and below
/// which it doesn't track yet.
const feelTracks = .5, feelLoose = .2;

const feelWords = ['Drained', 'Low', 'OK', 'Good', 'Great'];

/// The recovery colour a feel rating corresponds to.
RecoveryColor feelColor(int feel) => feel <= 2
    ? RecoveryColor.red
    : feel == 3
    ? RecoveryColor.yellow
    : RecoveryColor.green;

enum FeelFit { learning, tracks, loose, off }

final class FeelComparison {
  const FeelComparison({
    required this.n,
    required this.agree,
    required this.rho,
    required this.fit,
    this.recoveryHigh = 0,
    this.recoveryLow = 0,
  });

  /// Mornings with both a rating and a recovery score.
  final int n;

  /// Of [n], mornings where the recovery colour matched the feel band.
  final int agree;

  /// Spearman rank correlation, or null when either side never varies.
  final double? rho;
  final FeelFit fit;

  /// Mornings Recovery read better (green on a 1–2) or worse (red on a
  /// 4–5) than you felt, by two bands.
  final int recoveryHigh, recoveryLow;
}

/// [pairs] are (recovery 0–100, feel 1–5), one per morning.
FeelComparison compareFeel(List<(double, int)> pairs) {
  final n = pairs.length;
  var agree = 0, high = 0, low = 0;
  for (final (r, f) in pairs) {
    final rc = recoveryColor(r), fc = feelColor(f);
    if (rc == fc) agree++;
    if (rc == RecoveryColor.green && fc == RecoveryColor.red) high++;
    if (rc == RecoveryColor.red && fc == RecoveryColor.green) low++;
  }
  final rho = spearman(
    [for (final p in pairs) p.$1],
    [for (final p in pairs) p.$2.toDouble()],
  );
  final fit = n < feelMinPairs || rho == null
      ? FeelFit.learning
      : rho >= feelTracks
      ? FeelFit.tracks
      : rho >= feelLoose
      ? FeelFit.loose
      : FeelFit.off;
  return FeelComparison(
    n: n,
    agree: agree,
    rho: rho,
    fit: fit,
    recoveryHigh: high,
    recoveryLow: low,
  );
}

/// Spearman rank correlation (ties get their average rank). Null with
/// fewer than 3 points or when either list is constant.
double? spearman(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 3) return null;
  final rx = _ranks(x), ry = _ranks(y);
  final n = x.length;
  final mx = rx.reduce((a, b) => a + b) / n;
  final my = ry.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (rx[i] - mx) * (ry[i] - my);
    sxx += (rx[i] - mx) * (rx[i] - mx);
    syy += (ry[i] - my) * (ry[i] - my);
  }
  if (sxx == 0 || syy == 0) return null;
  return sxy / sqrt(sxx * syy);
}

List<double> _ranks(List<double> v) {
  final idx = List.generate(v.length, (i) => i)
    ..sort((a, b) => v[a].compareTo(v[b]));
  final r = List<double>.filled(v.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
      j++;
    }
    final avg = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      r[idx[k]] = avg;
    }
    i = j + 1;
  }
  return r;
}
