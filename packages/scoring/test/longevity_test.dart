import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('conversion', () {
    test('HR 2 is 8 years (mortality doubles every 8 years)', () {
      expect(yearsFromHazard(2), closeTo(8, 1e-9));
      expect(yearsFromHazard(1), 0);
      expect(yearsFromHazard(.5), closeTo(-8, 1e-9));
    });
    test('Uth VO₂ max: 15.3 × max / rest', () {
      expect(vo2maxFromHr(190, 60), closeTo(48.45, 1e-9));
    });
    test('VO₂ norm falls with age, lower for women', () {
      expect(vo2Norm(25, true), 46);
      expect(vo2Norm(45, true), closeTo(39.6, 1e-9));
      expect(vo2Norm(45, false), lessThan(vo2Norm(45, true)));
    });
  });

  group('hazards (typical adult = 1)', () {
    test('fitness: −13 % per MET above the norm', () {
      expect(hazard(Lever.fitness, vo2Norm(35, true), age: 35), 1);
      expect(
        hazard(Lever.fitness, vo2Norm(35, true) + 3.5, age: 35),
        closeTo(.87, 1e-9),
      );
    });
    test('resting HR: 1.09 per 10 bpm from 65', () {
      expect(hazard(Lever.restingHr, 65), 1);
      expect(hazard(Lever.restingHr, 75), closeTo(1.09, 1e-9));
    });
    test('steps: typical 7,000 = 1, plateau at 12k (8k past 60)', () {
      expect(hazard(Lever.steps, 7000), 1);
      expect(hazard(Lever.steps, 10000), closeTo(exp(-.225), 1e-9));
      expect(hazard(Lever.steps, 20000), hazard(Lever.steps, 12000));
      expect(
        hazard(Lever.steps, 12000, age: 65),
        hazard(Lever.steps, 8000, age: 65),
      );
    });
    test('active minutes: Arem curve, typical 75 min/week', () {
      expect(hazard(Lever.activeMinutes, 75), 1);
      expect(hazard(Lever.activeMinutes, 0), closeTo(1 / .8, 1e-9));
      expect(hazard(Lever.activeMinutes, 300), closeTo(.63 / .8, 1e-9));
      expect(
        hazard(Lever.activeMinutes, 900),
        hazard(Lever.activeMinutes, 450),
      );
    });
    test('strength: 2 a week is the plateau', () {
      expect(hazard(Lever.strength, .5), 1);
      expect(hazard(Lever.strength, 2), lessThan(1));
      expect(hazard(Lever.strength, 4), hazard(Lever.strength, 2));
    });
    test('sleep: U-shaped, neutral 7–8.5 h', () {
      expect(hazard(Lever.sleepDuration, 7.5), 1);
      expect(hazard(Lever.sleepDuration, 6), closeTo(1.12, 1e-9));
      // Long sleep counts half (1.15 an hour) and at most a year.
      expect(hazard(Lever.sleepDuration, 9.5), closeTo(1.09, .01));
      expect(
        yearsFromHazard(hazard(Lever.sleepDuration, 12)),
        closeTo(1, 1e-9),
      );
    });
    test('regularity, breathing, alcohol, BP, waist, smoking', () {
      // SRI: 75 typical, 1 % a point, within .88–1.25.
      expect(hazard(Lever.sleepRegularity, 75), 1);
      expect(hazard(Lever.sleepRegularity, 65), closeTo(1.1, 1e-9));
      expect(hazard(Lever.sleepRegularity, 0), 1.25);
      expect(hazard(Lever.sleepRegularity, 100), .88);
      expect(hazard(Lever.breathing, 95), 1);
      expect(hazard(Lever.breathing, 60), closeTo(1.18, 1e-9));
      expect(hazard(Lever.alcohol, 10), 1);
      expect(hazard(Lever.alcohol, 24), closeTo(1.1, 1e-9));
      expect(hazard(Lever.bloodPressure, 140), closeTo(1.25, 1e-9));
      expect(hazard(Lever.waist, 104), closeTo(1.1, 1e-9));
      expect(hazard(Lever.waist, 84, male: false), closeTo(pow(1.1, .4), 1e-9));
      expect(hazard(Lever.smoking, Smoking.current.index.toDouble()), 2.8);
    });
  });

  group('Tempo Age', () {
    const typical = LongevityInputs(
      age: 35,
      male: true,
      daysOfData: 40,
      vo2max: 42.8, // norm at 35
      restingHr: 65,
      steps: 7000,
      activeMinutes: 75,
      strengthPerWeek: .5,
      sleepHours: 7.5,
      sleepRegularityIndex: 75,
    );
    test('a typical person is their age', () {
      final t = tempoAge(typical);
      expect(t.age, closeTo(35, .05));
      expect(t.calibrating, isFalse);
    });
    test('a fit, active, regular sleeper is younger; levers ranked', () {
      final t = tempoAge(
        const LongevityInputs(
          age: 35,
          male: true,
          daysOfData: 40,
          vo2max: 52,
          restingHr: 52,
          steps: 11000,
          activeMinutes: 320,
          strengthPerWeek: 2,
          sleepHours: 7.6,
          sleepRegularityIndex: 85,
        ),
      );
      expect(t.delta, lessThan(-5));
      expect(t.levers, isEmpty); // already at every target
    });
    test('sedentary, short sleep, smoking: older; biggest lever first', () {
      final t = tempoAge(
        const LongevityInputs(
          age: 35,
          male: true,
          daysOfData: 40,
          vo2max: 34,
          restingHr: 78,
          steps: 3500,
          activeMinutes: 20,
          strengthPerWeek: 0,
          sleepHours: 5.8,
          sleepRegularityIndex: 55,
          smoking: Smoking.current,
        ),
      );
      expect(t.delta, greaterThan(10));
      expect(t.levers.first.lever, Lever.smoking);
      expect(t.levers.first.gain, closeTo(10, .01)); // capped
      final gains = [for (final l in t.levers) l.gain];
      expect(gains, orderedEquals([...gains]..sort((a, b) => b.compareTo(a))));
    });
    test('each lever is capped; total within ±15', () {
      final t = tempoAge(
        const LongevityInputs(
          age: 40,
          male: true,
          daysOfData: 40,
          vo2max: 10,
          restingHr: 120,
          steps: 0,
          activeMinutes: 0,
          sleepHours: 3,
          sleepRegularityIndex: 0,
          smoking: Smoking.current,
          systolic: 200,
        ),
      );
      for (final c in t.contributors) {
        expect(c.years.abs(), lessThanOrEqualTo(leverCap(c.lever)));
      }
      expect(t.age, 55);
    });
    test('calibrating under 30 days or 4 band contributors', () {
      expect(
        tempoAge(const LongevityInputs(age: 30, male: true, daysOfData: 10))
            .calibrating,
        isTrue,
      );
      expect(
        tempoAge(
          const LongevityInputs(
            age: 30,
            male: true,
            daysOfData: 60,
            steps: 8000,
            smoking: Smoking.never,
          ),
        ).calibrating,
        isTrue,
      );
    });
    test('stress is weak and small', () {
      final t = tempoAge(
        const LongevityInputs(age: 30, male: true, stressIndex: 90),
      );
      final s = t.contributors.single;
      expect(s.weak, isTrue);
      expect(s.years, lessThanOrEqualTo(.5));
    });
  });

  group('pace of aging', () {
    final d = DateTime(2026, 1, 1);
    test('needs 60 days', () {
      expect(
        paceOfAging([(d, 30), (d.add(const Duration(days: 30)), 30)]),
        isNull,
      );
    });
    test('slope in Tempo-Age years per calendar year', () {
      final pts = [
        for (var m = 0; m <= 6; m++)
          (d.add(Duration(days: 30 * m)), 30 + .5 * m * 30 / 365.25),
      ];
      expect(paceOfAging(pts), closeTo(.5, 1e-6));
    });
  });

  group('coach focus', () {
    const prefs = CoachPrefs(
      goal: Goal.fitness,
      likes: {Sport.running, Sport.strength, Sport.yoga},
      days: {1, 2, 3, 4, 5, 6, 7},
      maxMinutes: 90,
    );
    int z2Minutes(List<Session> w) => w.fold(
      0,
      (a, s) =>
          a +
          s.segments.where((g) => g.zone >= 2).fold(0, (b, g) => b + g.minutes),
    );
    test('active minutes adds Zone 2 time without new hard days', () {
      final base = weekPlan(prefs);
      final focus = weekPlan(prefs, focus: Lever.activeMinutes);
      expect(z2Minutes(focus), greaterThan(z2Minutes(base)));
      expect(
        focus.where((s) => s.isHard).length,
        base.where((s) => s.isHard).length,
      );
    });
    test('strength makes two strength days, never back to back', () {
      const p = CoachPrefs(
        goal: Goal.fitness,
        likes: {Sport.running},
        days: {1, 2, 3, 4, 5, 6, 7},
        maxMinutes: 60,
      );
      final w = weekPlan(p, focus: Lever.strength);
      final idx = [
        for (var i = 0; i < 7; i++)
          if (w[i].sport == Sport.strength) i,
      ];
      expect(idx.length, 2);
      expect(idx[1] - idx[0], greaterThan(1));
    });
  });

  test('weekly cap on Tempo Age', () {
    expect(capChange(30, null, 7), 30);
    expect(capChange(30, 33, 7), 32);
    expect(capChange(30, 33, 1), closeTo(33 - 1 / 7, 1e-9));
    expect(capChange(30, 33, 30), 30); // a month allows 4.3 years
    expect(capChange(34, 33, 7), 34);
  });

  test('contributor changes since last week', () {
    Contributor c(Lever l, double y) =>
        Contributor(lever: l, value: 0, years: y, target: 0, gain: 0);
    final ch = contributorChanges(
      [c(Lever.steps, 1), c(Lever.restingHr, -.5), c(Lever.sleepDuration, .3)],
      [c(Lever.steps, .2), c(Lever.restingHr, -.55), c(Lever.breathing, .4)],
    );
    expect(ch.map((e) => e.$1), [
      Lever.steps,
      Lever.breathing,
      Lever.sleepDuration,
    ]);
    expect(ch.first.$2, closeTo(-.8, 1e-9));
  });

  group('Tempo Age v2', () {
    const base = LongevityInputs(
      age: 35,
      male: true,
      daysOfData: 40,
      steps: 7000,
      activeMinutes: 75,
      sleepHours: 7.5,
      sleepRegularityIndex: 75,
    );
    LongevityInputs withRhr(double rhr, {bool measured = false}) =>
        LongevityInputs(
          age: 35,
          male: true,
          daysOfData: 40,
          vo2max: measured ? 42.8 : vo2maxFromHr(185, rhr),
          vo2maxMeasured: measured,
          restingHr: rhr,
          steps: 7000,
          activeMinutes: 75,
          sleepHours: 7.5,
          sleepRegularityIndex: 75,
        );

    test('resting HR is not counted twice when VO₂ max comes from it', () {
      double drop(bool measured) =>
          tempoAge(withRhr(65, measured: measured)).age -
          tempoAge(withRhr(55, measured: measured)).age;
      // Before v2 the same 10 bpm counted ~1 year directly and ~3.7 more
      // through the estimated VO₂ max.
      final derived = drop(false);
      expect(derived, lessThan(3.6));
      final rhr = tempoAge(withRhr(55)).contributors
          .singleWhere((c) => c.lever == Lever.restingHr);
      expect(rhr.weak, isTrue);
      expect(rhr.weight, lessThan(derivedRhrWeight + 1e-9));
      // A measured VO₂ max leaves resting HR its full (group) weight.
      final m = tempoAge(withRhr(55, measured: true)).contributors
          .singleWhere((c) => c.lever == Lever.restingHr);
      expect(m.weight, greaterThan(derivedRhrWeight));
    });

    test('overlapping levers in a group are shrunk', () {
      expect(groupScale(AgeGroup.activity, 1), 1);
      expect(groupScale(AgeGroup.activity, 3), closeTo(1 / 1.6, 1e-9));
      final t = tempoAge(
        const LongevityInputs(
          age: 35,
          male: true,
          daysOfData: 40,
          steps: 12000,
          activeMinutes: 300,
          strengthPerWeek: 2,
        ),
      );
      final g = t.groups.single;
      expect(g.group, AgeGroup.activity);
      final raw = [
        for (final c in g.levers)
          yearsFromHazard(hazard(c.lever, c.value, age: 35))
              .clamp(-leverCap(c.lever), leverCap(c.lever)),
      ].reduce((a, b) => a + b);
      expect(g.years, closeTo(raw / 1.6, 1e-9));
      expect(t.age - 35, closeTo(g.years, 1e-9));
    });

    test('groups add up to the total', () {
      final t = tempoAge(withRhr(52).copyLabs(phenoAge: 30, labDaysOld: 10));
      final sum = t.groups.fold<double>(0, (a, g) => a + g.years);
      expect(t.age - 35, closeTo(sum, 1e-9));
      expect(t.groups.map((g) => g.group), [
        AgeGroup.sleep,
        AgeGroup.activity,
        AgeGroup.fitness,
        AgeGroup.blood,
      ]);
    });

    test('confidence grows with coverage and inputs; range narrows', () {
      final thin = tempoAge(
        const LongevityInputs(age: 35, male: true, daysOfData: 5, steps: 7000),
      );
      final full = tempoAge(withRhr(60).copyLabs(phenoAge: 33, labDaysOld: 30));
      expect(thin.confidence, lessThan(.2));
      expect(full.confidence, greaterThan(thin.confidence));
      expect(full.halfRange, lessThan(thin.halfRange));
      expect(full.low, lessThan(full.age));
      expect(full.high, greaterThan(full.age));
      expect(thin.missing.first, Lever.fitness);
      expect(full.missing, isNot(contains(Lever.blood)));
    });

    test('blood test weight falls with age', () {
      expect(labRecency(0), 1);
      expect(labRecency(182), 1);
      expect(labRecency(456), closeTo(.5, 1e-9));
      expect(labRecency(730), 0);
      double bloodYears(int days) =>
          tempoAge(base.copyLabs(phenoAge: 45, labDaysOld: days)).contributors
              .singleWhere((c) => c.lever == Lever.blood)
              .years;
      expect(bloodYears(30), closeTo(10, 1e-9)); // capped at 10
      expect(bloodYears(456), closeTo(5, 1e-9));
      expect(
        tempoAge(base.copyLabs(phenoAge: 45, labDaysOld: 800)).contributors
            .any((c) => c.lever == Lever.blood),
        isFalse,
      );
    });

    test('resting HR reference by age and sex', () {
      expect(rhrNorm(35, true), 65);
      expect(rhrNorm(35, false), 68);
      expect(hazard(Lever.restingHr, 68, male: false), 1);
    });
  });

  group('PhenoAge (Levine 2018)', () {
    const healthy = Labs(
      albumin: 45,
      creatinine: 80,
      glucose: 5,
      crp: 1,
      lymphocytePct: 30,
      mcv: 90,
      rdw: 13,
      alp: 70,
      wbc: 6,
    );
    test('a healthy profile reads younger, a poor one older', () {
      // Values from the published coefficients, computed independently.
      expect(phenoAge(healthy, 40), closeTo(32.97, .01));
      expect(phenoAge(healthy, 60), closeTo(50.81, .01));
      const poor = Labs(
        albumin: 38,
        creatinine: 110,
        glucose: 7,
        crp: 10,
        lymphocytePct: 20,
        mcv: 98,
        rdw: 16,
        alp: 120,
        wbc: 10,
      );
      expect(phenoAge(poor, 40), closeTo(63.72, .01));
    });
    test('higher RDW or CRP raises it', () {
      const rdw = Labs(
        albumin: 45,
        creatinine: 80,
        glucose: 5,
        crp: 1,
        lymphocytePct: 30,
        mcv: 90,
        rdw: 15,
        alp: 70,
        wbc: 6,
      );
      expect(phenoAge(rdw, 40)!, greaterThan(phenoAge(healthy, 40)!));
    });
    test('CRP of 0 is outside the formula', () {
      const zero = Labs(
        albumin: 45,
        creatinine: 80,
        glucose: 5,
        crp: 0,
        lymphocytePct: 30,
        mcv: 90,
        rdw: 13,
        alp: 70,
        wbc: 6,
      );
      expect(phenoAge(zero, 40), isNull);
    });
  });
}

extension on LongevityInputs {
  LongevityInputs copyLabs({double? phenoAge, int? labDaysOld}) =>
      LongevityInputs(
        age: this.age,
        male: this.male,
        daysOfData: this.daysOfData,
        vo2max: this.vo2max,
        vo2maxMeasured: this.vo2maxMeasured,
        restingHr: this.restingHr,
        steps: this.steps,
        activeMinutes: this.activeMinutes,
        strengthPerWeek: this.strengthPerWeek,
        sleepHours: this.sleepHours,
        sleepRegularityIndex: this.sleepRegularityIndex,
        phenoAge: phenoAge,
        labDaysOld: labDaysOld,
      );
}
