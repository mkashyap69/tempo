/// Heart-rate zones as a share of max HR (design: Z1 50–60% … Z5 90–100%).
library;

import 'dart:math';

/// Lower bound of Z1..Z5 as a fraction of max HR.
const zoneLowerPct = [0.5, 0.6, 0.7, 0.8, 0.9];

const zoneNames = ['Easy', 'Aerobic', 'Tempo', 'Threshold', 'Max'];

/// Age-predicted max HR (Tanaka: 208 − 0.7 · age), rounded.
int maxHrFromAge(int age) => (208 - 0.7 * age).round();

/// 0 = below Z1, 1..5 = zone.
int zoneFor(int hr, int hrMax) {
  if (hrMax <= 0) return 0;
  final r = hr / hrMax;
  var z = 0;
  for (final b in zoneLowerPct) {
    if (r >= b) z++;
  }
  return z;
}

/// Inclusive bpm range of zone [z] (1..5) for [hrMax]. Z5 tops out at max.
({int lo, int hi}) zoneRange(int z, int hrMax) {
  final lo = (zoneLowerPct[z - 1] * hrMax).ceil();
  final hi = z == 5 ? hrMax : (zoneLowerPct[z] * hrMax).ceil() - 1;
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
}) {
  final out = List<int>.filled(5, 0);
  for (final hr in hrs) {
    if (hr == null) continue;
    final z = zoneFor(hr, hrMax);
    if (z == 0 && !includeBelow) continue;
    out[max(z, 1) - 1] += unit;
  }
  return out;
}
