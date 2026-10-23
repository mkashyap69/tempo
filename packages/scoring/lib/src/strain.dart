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

/// Banister TRIMP for one minute at [hr], above [floor] of HR reserve
/// (the reserve above the floor is rescaled to 0–1). Banister's weighting
/// is sex-specific (Morton, Fitz-Clarke & Banister 1990): 0.64·e^(1.92x)
/// for men, 0.86·e^(1.67x) for women ([female], algo 10).
///
/// The rescale is kept on purpose: without it a 45-minute walk day reads
/// strain ~10 instead of ~3 and no k keeps the calibration days in range
/// (checked for algo 10, see docs/decisions.md).
double minuteTrimp(
  int hr, {
  required double hrRest,
  required double hrMax,
  double floor = trimpFloor,
  bool female = false,
}) {
  if (hrMax <= hrRest) return 0;
  var r = ((hr - hrRest) / (hrMax - hrRest)).clamp(0.0, 1.0);
  if (r <= floor) return 0;
  r = (r - floor) / (1 - floor);
  return female ? r * 0.86 * exp(1.67 * r) : r * 0.64 * exp(1.92 * r);
}

/// Sum of per-minute TRIMP over [hrs] (one reading per minute, nulls skipped).
double trimp(
  Iterable<int?> hrs, {
  required double hrRest,
  required double hrMax,
  double floor = trimpFloor,
  bool female = false,
}) {
  var sum = 0.0;
  for (final hr in hrs) {
    if (hr != null) {
      sum += minuteTrimp(
        hr,
        hrRest: hrRest,
        hrMax: hrMax,
        floor: floor,
        female: female,
      );
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
/// undercounts lifting, so the session counts as at least its sRPE load,
/// or the load of its logged sets ([setsTrimp], see strength.dart),
/// whichever is higher.
double strengthCorrection({
  required double hrTrimp,
  int? rpe,
  int minutes = 0,
  double setsTrimp = 0,
  StrainParams p = const StrainParams(),
}) => max(
  0,
  max(rpe == null ? 0.0 : trimpFromRpe(rpe, minutes, p), setsTrimp) - hrTrimp,
);

/// HR max after a day of [hrs] (one reading per minute, in order),
/// starting from [current] (your age-predicted or set max, then the last
/// day's). It goes up only when at least [sustain] consecutive minutes sit
/// above it, to the lowest of them, and by at most [maxStep] bpm a day.
///
/// Algo 10: was the highest single minute ever, so one optical artefact
/// (cadence lock at 200+ during intervals) raised it for good and
/// lowered every later day's strain and zones. TODO(verify) against a
/// chest strap.
int updatedHrMax(
  int current,
  Iterable<int?> hrs, {
  int sustain = 2,
  int maxStep = 5,
}) {
  var best = current;
  final run = <int>[];
  for (final hr in hrs) {
    if (hr != null && hr > current) {
      run.add(hr);
      if (run.length >= sustain) {
        final low = run.sublist(run.length - sustain).reduce(min);
        if (low > best) best = low;
      }
    } else {
      run.clear();
    }
  }
  return min(best, current + maxStep);
}
