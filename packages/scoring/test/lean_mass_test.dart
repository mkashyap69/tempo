import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('fat-free mass index', () {
    // 80 kg at 20 % fat, 1.80 m: 64 / 3.24.
    expect(fatFreeMassIndex(80, 20, 180), closeTo(19.75, .01));
    expect(fatFreeMassIndex(80, 0.2, 180), isNull); // a fraction, not %
    expect(fatFreeMassIndex(80, 20, 0), isNull);
  });

  test('lean mass hazard: Sedlmeier 2021 end points', () {
    final lo = hazard(Lever.leanMass, 16.1, male: true);
    final hi = hazard(Lever.leanMass, 21.9, male: true);
    expect(hi / lo, closeTo(.70, 1e-9));
    expect(hazard(Lever.leanMass, ffmiNorm(true), male: true), 1);
    // Flat past the ends.
    expect(
      hazard(Lever.leanMass, 30, male: true),
      hazard(Lever.leanMass, 24, male: true),
    );
  });

  test('lean mass joins Body and moves Tempo Age', () {
    const base = LongevityInputs(age: 35, male: true, daysOfData: 30);
    final lean = tempoAge(
      const LongevityInputs(age: 35, male: true, daysOfData: 30, ffmi: 21),
    );
    final c = lean.contributors.single;
    expect(c.lever, Lever.leanMass);
    expect(c.group, AgeGroup.body);
    expect(c.years, lessThan(0));
    expect(tempoAge(base).missing, contains(Lever.leanMass));
  });

  test('FRIEND percentile and category', () {
    // Man of 35, 45 ml/kg/min: 50 + 25 × (45 − 42.4) / (49.2 − 42.4).
    expect(fitnessPercentile(45, 35, true), closeTo(59.56, .01));
    expect(fitnessCategory(59.56), FitnessCategory.good);
    // Woman of 52, 30: 75 + 15 × 2.4 / 4.4.
    expect(fitnessPercentile(30, 52, false), closeTo(83.18, .01));
    expect(fitnessCategory(83.18), FitnessCategory.superior);
    // Below the table: 5. Ages outside 20–79 use the end rows.
    expect(fitnessPercentile(16, 45, false), 5);
    expect(fitnessPercentile(48, 18, true), 50);
    expect(fitnessPercentile(24.4, 85, true), 50);
    expect(fitnessCategory(19.9), FitnessCategory.poor);
    expect(fitnessCategory(40), FitnessCategory.good);
  });

  test('body fat from the waist (Relative Fat Mass)', () {
    // 178 cm, 105 cm waist, a man: 64 − 20 × 178 / 105.
    expect(relativeFatMass(178, 105, true), closeTo(30.10, .01));
    expect(relativeFatMass(165, 80, false), closeTo(34.75, .01));
    expect(relativeFatMass(178, 10, true), isNull);
  });

  test('an estimated lean mass counts at half', () {
    const i = LongevityInputs(age: 35, male: true, daysOfData: 30, ffmi: 21);
    const e = LongevityInputs(
      age: 35,
      male: true,
      daysOfData: 30,
      ffmi: 21,
      ffmiEstimated: true,
    );
    final full = tempoAge(i).contributors.single;
    final half = tempoAge(e).contributors.single;
    expect(half.years, closeTo(full.years * estimatedLeanWeight, 1e-9));
    expect(half.weak, isTrue);
  });
}
