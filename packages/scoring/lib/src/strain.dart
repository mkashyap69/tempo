import 'dart:math';

/// Default TRIMP floor: share of heart-rate reserve below which a minute
/// adds no load.
const trimpFloor = 0.3;

/// Strain constants, calibrated so a rest day lands near 0, an easy run day
/// around 5–7, a threshold session around 13 and two hard hours past 19
/// (see test/scoring_test.dart → calibration).
final class StrainParams {
  const StrainParams({
    this.k = 40,
    this.floor = trimpFloor,
    this.rpeScale = 0.11,
  });
  final double k;

  /// Fraction of heart-rate reserve below which a minute adds nothing, so
  /// sitting and pottering about do not build strain on their own.
  final double floor;

  /// sRPE (RPE × minutes) to TRIMP units, for sessions HR undercounts.
  final double rpeScale;
}

/// Banister TRIMP for one minute at [hr], above [floor] of HR reserve.
double minuteTrimp(
  int hr, {
  required double hrRest,
  required double hrMax,
  double floor = trimpFloor,
}) {
  if (hrMax <= hrRest) return 0;
  var r = ((hr - hrRest) / (hrMax - hrRest)).clamp(0.0, 1.0);
  if (r <= floor) return 0;
  r = (r - floor) / (1 - floor);
  return r * 0.64 * exp(1.92 * r);
}

/// Sum of per-minute TRIMP over [hrs] (one reading per minute, nulls skipped).
double trimp(
  Iterable<int?> hrs, {
  required double hrRest,
  required double hrMax,
  double floor = trimpFloor,
}) {
  var sum = 0.0;
  for (final hr in hrs) {
    if (hr != null) {
      sum += minuteTrimp(hr, hrRest: hrRest, hrMax: hrMax, floor: floor);
    }
  }
  return sum;
}

/// TRIMP compressed to 0–21.
double strainFromTrimp(double trimp, [StrainParams p = const StrainParams()]) =>
    21 * (1 - exp(-trimp / p.k));

/// The k that puts a day of [trimp] at [strain] (0–21): the inverse of
/// [strainFromTrimp], for calibrating k on real days.
double kForStrain(double trimp, double strain) {
  if (trimp <= 0 || strain <= 0 || strain >= 21) {
    throw ArgumentError('needs trimp > 0 and 0 < strain < 21');
  }
  return -trimp / log(1 - strain / 21);
}

/// Session-RPE load (Foster) in TRIMP units.
double trimpFromRpe(
  int rpe,
  int minutes, [
  StrainParams p = const StrainParams(),
]) => p.rpeScale * rpe.clamp(0, 10) * max(0, minutes);

/// What to add on top of the HR-based TRIMP of a strength session: HR
/// undercounts lifting, so the session counts as at least its sRPE load.
double strengthCorrection({
  required double hrTrimp,
  required int rpe,
  required int minutes,
  StrainParams p = const StrainParams(),
}) => max(0, trimpFromRpe(rpe, minutes, p) - hrTrimp);

/// HR max starts at 190 and only goes up when the band records higher.
int updatedHrMax(int current, Iterable<int?> hrs) {
  var m = current;
  for (final hr in hrs) {
    if (hr != null && hr > m) m = hr;
  }
  return m;
}
