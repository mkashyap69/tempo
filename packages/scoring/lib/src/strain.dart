import 'dart:math';

/// Strain constants. Starting values; calibrate k so the hardest known
/// training days land around 18–19.
final class StrainParams {
  const StrainParams({this.k = 120});
  final double k;
}

/// Banister TRIMP for one minute at [hr].
double minuteTrimp(int hr, {required double hrRest, required double hrMax}) {
  if (hrMax <= hrRest) return 0;
  final r = ((hr - hrRest) / (hrMax - hrRest)).clamp(0.0, 1.0);
  return r * 0.64 * exp(1.92 * r);
}

/// Sum of per-minute TRIMP over [hrs] (one reading per minute, nulls skipped).
double trimp(
  Iterable<int?> hrs, {
  required double hrRest,
  required double hrMax,
}) {
  var sum = 0.0;
  for (final hr in hrs) {
    if (hr != null) sum += minuteTrimp(hr, hrRest: hrRest, hrMax: hrMax);
  }
  return sum;
}

/// TRIMP compressed to 0–21.
double strainFromTrimp(double trimp, [StrainParams p = const StrainParams()]) =>
    21 * (1 - exp(-trimp / p.k));

/// HR max starts at 190 and only goes up when the band records higher.
int updatedHrMax(int current, Iterable<int?> hrs) {
  var m = current;
  for (final hr in hrs) {
    if (hr != null && hr > m) m = hr;
  }
  return m;
}
