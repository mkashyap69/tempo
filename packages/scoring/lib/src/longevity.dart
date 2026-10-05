import 'dart:math';

/// Tempo Age: your age, adjusted by how your habits and vitals compare
/// with a typical person's, in years.
///
/// Each contributor is turned into a hazard ratio for all-cause mortality
/// from large published studies (cited per lever below), then into years
/// with the Gompertz law: adult mortality roughly doubles every 8 years,
/// so years = 8 · log2(HR) ≈ 11.5 · ln(HR). Every number here is an
/// estimate for wellness, not a medical age. All contributors use the
/// last 30 days, so Tempo Age moves slowly and on purpose.

enum Lever {
  fitness,
  restingHr,
  steps,
  activeMinutes,
  strength,
  sleepDuration,
  sleepRegularity,
  breathing,
  stress,
  smoking,
  alcohol,
  bloodPressure,
  waist,
}

enum Smoking { never, former, current }

/// What Tempo Age is computed from. Nulls are left out (not guessed).
final class LongevityInputs {
  const LongevityInputs({
    required this.age,
    required this.male,
    this.daysOfData = 0,
    this.vo2max,
    this.restingHr,
    this.steps,
    this.activeMinutes,
    this.strengthPerWeek,
    this.sleepHours,
    this.bedtimeSdMinutes,
    this.breathingScore,
    this.stressIndex,
    this.smoking,
    this.alcoholUnits,
    this.systolic,
    this.waistCm,
  });
  final int age;
  final bool male;

  /// Days with band data in the window (Tempo Age needs 30).
  final int daysOfData;

  /// Estimated VO₂ max, ml/kg/min (see [vo2maxFromHr]).
  final double? vo2max;
  final double? restingHr;

  /// Average steps a day.
  final double? steps;

  /// Minutes a week at Zone 2 or above (≥ 60 % of max HR).
  final double? activeMinutes;
  final double? strengthPerWeek;
  final double? sleepHours;

  /// Standard deviation of bedtimes, minutes.
  final double? bedtimeSdMinutes;

  /// Breathing score 0–100 (see breathing.dart), averaged.
  final double? breathingScore;

  /// Overnight stress index, averaged. A weak stand-in for HRV.
  final double? stressIndex;

  // Optional, entered by hand.
  final Smoking? smoking;
  final double? alcoholUnits; // UK units a week
  final int? systolic; // mmHg
  final double? waistCm;
}

/// One contributor: your value, what it's worth in years (negative is
/// younger), and the target that would gain [gain] years.
final class Contributor {
  const Contributor({
    required this.lever,
    required this.value,
    required this.years,
    required this.target,
    required this.gain,
    this.weak = false,
  });
  final Lever lever;
  final double value;
  final double years;
  final double target;

  /// Years younger at [target] (0 when already there).
  final double gain;

  /// Thin evidence or a proxy measure: shown, weighted lightly.
  final bool weak;
}

final class TempoAge {
  const TempoAge({
    required this.realAge,
    required this.age,
    required this.contributors,
    required this.calibrating,
  });
  final double realAge;

  /// Tempo Age in years.
  final double age;
  final List<Contributor> contributors;

  /// Fewer than 30 days or 4 band contributors: shown as calibrating.
  final bool calibrating;

  /// Negative = younger than your calendar age.
  double get delta => age - realAge;

  /// Actionable contributors with something to gain, biggest first.
  List<Contributor> get levers {
    const actionable = {
      Lever.fitness,
      Lever.steps,
      Lever.activeMinutes,
      Lever.strength,
      Lever.sleepDuration,
      Lever.sleepRegularity,
      Lever.breathing,
      Lever.smoking,
      Lever.alcohol,
      Lever.bloodPressure,
      Lever.waist,
    };
    return [
      for (final c in contributors)
        if (actionable.contains(c.lever) && c.gain >= .1) c,
    ]..sort((a, b) => b.gain.compareTo(a.gain));
  }
}

/// years = 8 · log2(HR).
double yearsFromHazard(double hr) => 8 * log(hr) / ln2;

/// Uth et al. 2004: VO₂ max ≈ 15.3 × HRmax / HRrest (ml/kg/min). A rough
/// estimate (±10–15 %) that improves as resting HR falls with fitness.
double vo2maxFromHr(int maxHr, double restingHr) => 15.3 * maxHr / restingHr;

/// Typical (50th percentile) VO₂ max for age and sex, after the FRIEND
/// registry's treadmill norms, as a straight line through ages 25–75.
double vo2Norm(int age, bool male) =>
    male ? 46 - .32 * (age - 25) : 38 - .27 * (age - 25);

double _clampYears(double y, double cap) => y.clamp(-cap, cap).toDouble();

double _lerp(List<(double, double)> pts, double x) {
  if (x <= pts.first.$1) return pts.first.$2;
  for (var i = 1; i < pts.length; i++) {
    final (x1, y1) = pts[i];
    final (x0, y0) = pts[i - 1];
    if (x <= x1) return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
  }
  return pts.last.$2;
}

/// Hazard ratio for one lever at [v], relative to a typical adult.
double hazard(Lever l, double v, {int age = 35, bool male = true}) {
  switch (l) {
    case Lever.fitness:
      // Kodama 2009 (JAMA): 13 % lower mortality per MET (3.5 ml/kg/min).
      return pow(.87, (v - vo2Norm(age, male)) / 3.5).toDouble();
    case Lever.restingHr:
      // Zhang 2016 (CMAJ): +10 bpm → 1.09.
      return pow(1.09, (v - 65) / 10).toDouble();
    case Lever.steps:
      // Paluch 2022 (Lancet Public Health): falls log-linearly to a
      // plateau at ~10–12k steps (8k past 60). Typical: 7,000.
      final cap = age >= 60 ? 8000.0 : 12000.0;
      return exp(-.075 * (min(max(v, 2000.0), cap) - 7000) / 1000);
    case Lever.activeMinutes:
      // Arem 2015 (JAMA IM): 0 → 1, 75 → .80, 150 → .69, 300 → .63,
      // 450+ → .61 min/week. Typical: 75.
      const f = [
        (0.0, 1.0),
        (75.0, .80),
        (150.0, .69),
        (300.0, .63),
        (450.0, .61),
      ];
      return _lerp(f, v) / .80;
    case Lever.strength:
      // Momma 2022 (BJSM): 30–60 min/week of muscle strengthening → .83.
      const f = [(0.0, 1.0), (1.0, .88), (2.0, .83), (4.0, .83)];
      return _lerp(f, v) / _lerp(f, .5);
    case Lever.sleepDuration:
      // Cappuccio 2010 (Sleep): short 1.12, long 1.30; 7–8.5 h neutral.
      if (v < 7) return pow(1.12, 7 - v).toDouble();
      if (v > 8.5) return pow(1.3, v - 8.5).toDouble();
      return 1;
    case Lever.sleepRegularity:
      // Windred 2024 (Sleep): regular sleepers ~20 % lower risk than the
      // least regular. Bedtime SD 45 min typical.
      return (1 + .004 * (v - 45)).clamp(.88, 1.25).toDouble();
    case Lever.breathing:
      // Punjabi 2009 (PLoS Med): moderate–severe sleep-disordered
      // breathing ~1.4. Score 90+ is normal.
      return (1 + .006 * max(0, 90 - v)).clamp(1, 1.4).toDouble();
    case Lever.stress:
      // Proxy for HRV; small weight.
      return (1 + .003 * (v - 35)).clamp(.95, 1.1).toDouble();
    case Lever.smoking:
      // Jha 2013 (NEJM): current ~2.8 (≈ 10 years), former ~1.3.
      return switch (Smoking.values[v.round()]) {
        Smoking.never => 1,
        Smoking.former => 1.3,
        Smoking.current => 2.8,
      };
    case Lever.alcohol:
      // Wood 2018 (Lancet): risk rises above ~14 units (100 g) a week.
      return 1 + .01 * max(0, v - 14);
    case Lever.bloodPressure:
      // Lewington 2002 (Lancet), all-cause: ~1.25 per 20 mmHg above 120.
      return pow(1.25, (max(v, 110) - 120) / 20).toDouble();
    case Lever.waist:
      // Pischon 2008 (NEJM): ~1.1 per 10 cm above 94 (men) / 80 (women).
      final ref = male ? 94.0 : 80.0;
      return pow(1.1, max(0, v - ref) / 10).toDouble();
  }
}

/// Most years one lever can add or take away.
double leverCap(Lever l) => switch (l) {
  Lever.fitness => 5,
  Lever.smoking => 10,
  Lever.stress => .5,
  _ => 3,
};

/// Where each lever is good enough.
double leverTarget(Lever l, {required int age, required bool male}) =>
    switch (l) {
      Lever.fitness => vo2Norm(age, male) + 7, // ~top quarter
      Lever.restingHr => 55,
      Lever.steps => age >= 60 ? 8000 : 10000,
      Lever.activeMinutes => 300,
      Lever.strength => 2,
      Lever.sleepDuration => 7.5,
      Lever.sleepRegularity => 30,
      Lever.breathing => 90,
      Lever.stress => 30,
      Lever.smoking => Smoking.never.index.toDouble(),
      Lever.alcohol => 7,
      Lever.bloodPressure => 115,
      Lever.waist => male ? 94 : 80,
    };

/// Weeks a lever usually takes to move, for the focus plan.
int leverWeeks(Lever l) => switch (l) {
  Lever.steps || Lever.sleepDuration || Lever.sleepRegularity => 4,
  Lever.alcohol => 4,
  Lever.breathing => 6,
  Lever.activeMinutes || Lever.strength => 8,
  _ => 12,
};

TempoAge tempoAge(LongevityInputs i) {
  final values = <Lever, double?>{
    Lever.fitness: i.vo2max,
    Lever.restingHr: i.restingHr,
    Lever.steps: i.steps,
    Lever.activeMinutes: i.activeMinutes,
    Lever.strength: i.strengthPerWeek,
    Lever.sleepDuration: i.sleepHours,
    Lever.sleepRegularity: i.bedtimeSdMinutes,
    Lever.breathing: i.breathingScore,
    Lever.stress: i.stressIndex,
    Lever.smoking: i.smoking?.index.toDouble(),
    Lever.alcohol: i.alcoholUnits,
    Lever.bloodPressure: i.systolic?.toDouble(),
    Lever.waist: i.waistCm,
  };
  double yearsAt(Lever l, double v) => _clampYears(
    yearsFromHazard(hazard(l, v, age: i.age, male: i.male)),
    leverCap(l),
  );
  final out = <Contributor>[];
  for (final e in values.entries) {
    final v = e.value;
    if (v == null) continue;
    final target = leverTarget(e.key, age: i.age, male: i.male);
    final y = yearsAt(e.key, v);
    out.add(
      Contributor(
        lever: e.key,
        value: v,
        years: y,
        target: target,
        gain: max(0, y - yearsAt(e.key, target)),
        weak: e.key == Lever.stress,
      ),
    );
  }
  final sum = out.fold<double>(0, (a, c) => a + c.years);
  const device = {
    Lever.fitness,
    Lever.restingHr,
    Lever.steps,
    Lever.activeMinutes,
    Lever.strength,
    Lever.sleepDuration,
    Lever.sleepRegularity,
    Lever.breathing,
    Lever.stress,
  };
  final fromBand = out.where((c) => device.contains(c.lever)).length;
  return TempoAge(
    realAge: i.age.toDouble(),
    age: i.age + sum.clamp(-15, 15),
    contributors: out,
    calibrating: i.daysOfData < 30 || fromBand < 4,
  );
}

/// Pace of aging: how many Tempo-Age years pass per calendar year, from
/// the slope of (date, Tempo Age) points. 1.0 = ageing as the calendar
/// does; under 1 = slowing. Null with under 60 days between points.
double? paceOfAging(List<(DateTime, double)> points) {
  if (points.length < 2) return null;
  final t0 = points.first.$1;
  final xs = [for (final p in points) p.$1.difference(t0).inDays / 365.25];
  if (xs.last - xs.first < 60 / 365.25) return null;
  final ys = [for (final p in points) p.$2];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var num = 0.0, den = 0.0;
  for (var k = 0; k < xs.length; k++) {
    num += (xs[k] - mx) * (ys[k] - my);
    den += (xs[k] - mx) * (xs[k] - mx);
  }
  // Tempo Age already includes calendar time (real age rises too).
  return den == 0 ? null : num / den;
}

/// Tempo Age may move at most [perWeek] years per 7 days from the last
/// snapshot, so one odd week can't swing it; the full change arrives over
/// the following weeks. [days] since [previous]; null previous = no cap.
const tempoAgePerWeek = 1.0;

double capChange(
  double raw,
  double? previous,
  int days, {
  double perWeek = tempoAgePerWeek,
}) {
  if (previous == null || days <= 0) return raw;
  final room = perWeek * days / 7;
  return raw.clamp(previous - room, previous + room).toDouble();
}

/// Per-lever change in years between two sets of contributors, biggest
/// first; changes under 0.1 years are left out. A lever that appears or
/// disappears counts from 0.
List<(Lever, double)> contributorChanges(
  List<Contributor> before,
  List<Contributor> now,
) {
  final b = {for (final c in before) c.lever: c.years};
  final n = {for (final c in now) c.lever: c.years};
  final out = <(Lever, double)>[
    for (final l in {...b.keys, ...n.keys})
      if (((n[l] ?? 0) - (b[l] ?? 0)).abs() >= .1)
        (l, (n[l] ?? 0) - (b[l] ?? 0)),
  ]..sort((x, y) => y.$2.abs().compareTo(x.$2.abs()));
  return out;
}
