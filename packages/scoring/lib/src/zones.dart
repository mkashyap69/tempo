/// Heart-rate zones as a share of max HR (design: Z1 50–60% … Z5 90–100%),
/// or of heart-rate reserve (Karvonen) when a resting HR is given.
///
/// Reserve zones (rest + share × (max − rest)) track lactate and
/// ventilatory thresholds better across fitness levels than % of max
/// (Karvonen 1957; ACSM). Off unless chosen in Profile (algo 10).
library;

import 'dart:math';

/// Lower bound of Z1..Z5 as a fraction of max HR (or of reserve).
const zoneLowerPct = [0.5, 0.6, 0.7, 0.8, 0.9];

const zoneNames = ['Easy', 'Aerobic', 'Tempo', 'Threshold', 'Max'];

/// Age-predicted max HR (Tanaka: 208 − 0.7 · age), rounded.
int maxHrFromAge(int age) => (208 - 0.7 * age).round();

/// Lower bound of zone [z] (1..5) in bpm, before rounding.
double _lower(int z, int hrMax, double? hrRest) {
  final pct = zoneLowerPct[z - 1];
  if (hrRest == null || hrRest >= hrMax) return pct * hrMax;
  return hrRest + pct * (hrMax - hrRest);
}

/// 0 = below Z1, 1..5 = zone. With [hrRest], reserve-based zones.
int zoneFor(int hr, int hrMax, {double? hrRest}) {
  if (hrMax <= 0) return 0;
  var z = 0;
  for (var i = 1; i <= 5; i++) {
    if (hr >= _lower(i, hrMax, hrRest) - 1e-9) z++;
  }
  return z;
}

/// Inclusive bpm range of zone [z] (1..5) for [hrMax]. Z5 tops out at max.
({int lo, int hi}) zoneRange(int z, int hrMax, {double? hrRest}) {
  final lo = (_lower(z, hrMax, hrRest) - 1e-9).ceil();
  final hi = z == 5 ? hrMax : (_lower(z + 1, hrMax, hrRest) - 1e-9).ceil() - 1;
  return (lo: lo, hi: max(lo, hi));
}

/// Seconds (or minutes) spent in each zone, index 0 = Z1. With
/// [includeBelow], readings below Z1 count toward Z1 (a workout's total then
/// equals its length); without, they are left out (a whole day).
List<int> timeInZones(
  Iterable<int?> hrs,
  int hrMax, {
  int unit = 1,
  bool includeBelow = true,
  double? hrRest,
}) {
  final out = List<int>.filled(5, 0);
  for (final hr in hrs) {
    if (hr == null) continue;
    final z = zoneFor(hr, hrMax, hrRest: hrRest);
    if (z == 0 && !includeBelow) continue;
    out[max(z, 1) - 1] += unit;
  }
  return out;
}

/// Seconds in Z1..Z5 from timestamped readings ([ts] in seconds, bpm),
/// sorted by time. Each reading holds until the next one or [end], but
/// for no more than [maxGap] seconds: a longer gap counts as no signal.
/// Below Z1 counts as Z1, as in a live session.
List<int> zoneSecondsFromSamples(
  List<(int, int)> samples,
  int hrMax, {
  required int end,
  int maxGap = 10,
  double? hrRest,
}) {
  final out = List<int>.filled(5, 0);
  for (var i = 0; i < samples.length; i++) {
    final (ts, hr) = samples[i];
    final next = i + 1 < samples.length ? samples[i + 1].$1 : end;
    final held = min(next - ts, maxGap);
    if (held <= 0) continue;
    out[max(zoneFor(hr, hrMax, hrRest: hrRest), 1) - 1] += held;
  }
  return out;
}
