import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> run(
  DateTime from,
  int n, {
  int? hr,
  Stage stage = Stage.wake,
  int steps = 0,
}) => [
  for (var i = 0; i < n; i++)
    Minute(
      from.add(Duration(minutes: i)),
      hr: hr,
      stage: stage,
      steps: steps,
    ),
];

void main() {
  group('strain', () {
    test('minute TRIMP formula without a floor', () {
      // r = 0.5 → 0.5 · 0.64 · e^0.96
      expect(
        minuteTrimp(125, hrRest: 60, hrMax: 190, floor: 0),
        closeTo(0.5 * 0.64 * exp(0.96), 1e-9),
      );
    });
    test('floor rescales the reserve above it', () {
      // r = 0.5, floor 0.3 → r' = 0.2/0.7
      const r = 0.2 / 0.7;
      expect(
        minuteTrimp(125, hrRest: 60, hrMax: 190),
        closeTo(r * 0.64 * exp(1.92 * r), 1e-9),
      );
      // At or under 30% of reserve: nothing.
      expect(minuteTrimp(99, hrRest: 60, hrMax: 190), 0);
    });
    test('clamps below rest and above max', () {
      expect(minuteTrimp(40, hrRest: 60, hrMax: 190), 0);
      expect(
        minuteTrimp(220, hrRest: 60, hrMax: 190),
        closeTo(0.64 * exp(1.92), 1e-9),
      );
    });
    test('degenerate HR range gives 0', () {
      expect(minuteTrimp(100, hrRest: 190, hrMax: 190), 0);
    });
    test('strain curve: 0 → 0, k → 21(1-1/e), monotone, < 21', () {
      expect(strainFromTrimp(0), 0);
      expect(strainFromTrimp(40), closeTo(21 * (1 - exp(-1)), 1e-9));
      expect(strainFromTrimp(10000), lessThanOrEqualTo(21));
      expect(strainFromTrimp(50), lessThan(strainFromTrimp(60)));
    });
    test('trimp skips nulls', () {
      expect(
        trimp([null, 125, null], hrRest: 60, hrMax: 190),
        closeTo(minuteTrimp(125, hrRest: 60, hrMax: 190), 1e-9),
      );
    });
    test('kForStrain inverts strainFromTrimp', () {
      final k = kForStrain(200, 18.5);
      expect(strainFromTrimp(200, StrainParams(k: k)), closeTo(18.5, 1e-9));
      expect(kForStrain(40 * 2, strainFromTrimp(80)), closeTo(40, 1e-9));
      expect(() => kForStrain(0, 10), throwsArgumentError);
      expect(() => kForStrain(100, 21), throwsArgumentError);
    });
    group('calibration (rest 50, max 186)', () {
      double strainOf(List<(int, int)> blocks) => strainFromTrimp(
        trimp(
          [
            for (var i = 0; i < 900; i++) 70 + (i % 9),
            for (final (m, hr) in blocks) ...List.filled(m, hr),
          ],
          hrRest: 50,
          hrMax: 186,
        ),
      );
      test('a desk day with no exercise stays near 0', () {
        expect(strainOf([]), lessThan(1));
      });
      test('a 45-minute walk day is light', () {
        expect(strainOf([(45, 105)]), inInclusiveRange(1.5, 5));
      });
      test('an easy run day lands 5–8', () {
        expect(
          strainOf([(45, 105), (5, 102), (25, 121), (5, 102)]),
          inInclusiveRange(5, 8),
        );
      });
      test('a threshold session lands 12–15', () {
        expect(
          strainOf([(45, 105), (10, 121), (15, 158), (10, 102), (8, 121)]),
          inInclusiveRange(12, 15),
        );
      });
      test('two hard hours pass 18', () {
        expect(strainOf([(120, 145)]), greaterThan(18));
      });
    });
    test('sRPE: RPE × minutes × scale', () {
      expect(trimpFromRpe(7, 60), closeTo(0.11 * 420, 1e-9));
      expect(trimpFromRpe(12, 10), closeTo(0.11 * 100, 1e-9));
      expect(trimpFromRpe(5, -3), 0);
    });
    test('strength correction tops HR TRIMP up to sRPE, never down', () {
      expect(
        strengthCorrection(hrTrimp: 10, rpe: 7, minutes: 60),
        closeTo(0.11 * 420 - 10, 1e-9),
      );
      expect(strengthCorrection(hrTrimp: 80, rpe: 7, minutes: 60), 0);
    });
    test('hr max only rises', () {
      expect(updatedHrMax(190, [150, null, 185]), 190);
      expect(updatedHrMax(190, [195]), 195);
    });
  });

  group('resting HR', () {
    test('lowest 5-minute average', () {
      final t = DateTime(2026);
      final m = [
        for (final (i, hr) in [70, 60, 50, 50, 50, 50, 50, 80].indexed)
          Minute(t.add(Duration(minutes: i)), hr: hr),
      ];
      expect(restingHr(m), 50);
    });
    test('needs half the window covered', () {
      final t = DateTime(2026);
      expect(restingHr(run(t, 10)), isNull);
    });
  });

  group('baseline', () {
    test('mean and sample sd', () {
      final b = Baseline.of([2, 4, 4, 4, 5, 5, 7, 9, null])!;
      expect(b.mean, 5);
      expect(b.sd, closeTo(2.138, 1e-3));
      expect(b.n, 8);
    });
    test('needs two values', () => expect(Baseline.of([1, null]), isNull));
  });

  group('sleep', () {
    final t = DateTime(2026, 1, 1, 23);
    test('merges short wake gaps, splits long active ones', () {
      final m = [
        ...run(t, 120, stage: Stage.light),
        ...run(t.add(const Duration(minutes: 120)), 20),
        ...run(t.add(const Duration(minutes: 140)), 120, stage: Stage.deep),
        ...run(t.add(const Duration(minutes: 260)), 60, steps: 5),
        ...run(t.add(const Duration(minutes: 320)), 90, stage: Stage.rem),
      ];
      final s = detectSessions(m);
      expect(s.length, 2);
      expect(s[0].asleep.inMinutes, 240);
      expect(s[0].inBed.inMinutes, 260);
      expect(s[0].efficiency, closeTo(240 / 260, 1e-9));
      expect(s[1].stage(Stage.rem).inMinutes, 90);
    });
    test('a quiet wake up to 90 minutes stays inside the night', () {
      // 6 Oct: asleep 00:07–05:28, awake 31 min with 0 steps, asleep to 08:18.
      final a = DateTime(2026, 10, 6, 0, 7);
      final m = [
        ...run(a, 321, stage: Stage.light),
        ...run(a.add(const Duration(minutes: 321)), 31),
        ...run(a.add(const Duration(minutes: 352)), 140, stage: Stage.light),
      ];
      final s = detectSessions(m);
      expect(s.length, 1);
      expect(s.single.asleep.inMinutes, 461);
      // The same gap with walking around splits it.
      final walked = [
        ...run(a, 321, stage: Stage.light),
        ...run(a.add(const Duration(minutes: 321)), 31, steps: 3),
        ...run(a.add(const Duration(minutes: 352)), 140, stage: Stage.light),
      ];
      expect(detectSessions(walked).length, 2);
      // A quiet gap over 90 minutes splits too.
      final long = [
        ...run(a, 200, stage: Stage.light),
        ...run(a.add(const Duration(minutes: 200)), 95),
        ...run(a.add(const Duration(minutes: 295)), 120, stage: Stage.light),
      ];
      expect(detectSessions(long).length, 2);
    });
    test('drops sessions shorter than the minimum', () {
      expect(detectSessions(run(t, 30, stage: Stage.light)), isEmpty);
    });
    test('need = 7.5 + 0.5·debt + 0.03·strain', () {
      expect(
        sleepNeedHours(debtHours: 1, strainYesterday: 10),
        closeTo(8.3, 1e-9),
      );
    });
    test('need starts from a learned base when given', () {
      expect(
        sleepNeedHours(debtHours: 0, strainYesterday: 0, baseHours: 8.2),
        closeTo(8.2, 1e-9),
      );
    });
    group('learned base need', () {
      List<NeedSample> nights(int n, double Function(int) slept) => [
        for (var i = 0; i < n; i++)
          NeedSample(sleptHours: slept(i), recovery: i.toDouble()),
      ];
      test('falls back to 7.5 under 14 nights', () {
        expect(learnedBaseNeed(nights(13, (_) => 9)), 7.5);
      });
      test('median of the best-recovered third', () {
        // Recovery rises with i; the top third (i 10..14) slept 8.0–8.4.
        final n = nights(15, (i) => i >= 10 ? 8 + (i - 10) / 10 : 6.5);
        expect(learnedBaseNeed(n), closeTo(8.2, 1e-9));
      });
      test('clamped to 6.5–9.5', () {
        expect(learnedBaseNeed(nights(15, (_) => 5)), 6.5);
        expect(learnedBaseNeed(nights(15, (_) => 11)), 9.5);
      });
    });
    test('debt sums shortfall, ignores surplus, caps at 2h', () {
      expect(
        sleepDebtHours([
          const NightRecord(needHours: 8, sleptHours: 7.5),
          const NightRecord(needHours: 8, sleptHours: 9),
        ]),
        0.5,
      );
      expect(
        sleepDebtHours(
          List.filled(7, const NightRecord(needHours: 8, sleptHours: 6)),
        ),
        2,
      );
    });
    test('performance capped at 100', () {
      expect(sleepPerformance(6, 8), 75);
      expect(sleepPerformance(10, 8), 100);
    });
  });

  group('recovery', () {
    const b = Baseline(50, 10, 30);
    test('at baseline → 50', () {
      expect(
        recoveryScore([
          const RecoveryInput(
            value: 50,
            baseline: b,
            higherIsBetter: true,
            weight: 1,
          ),
        ]),
        closeTo(50, 1e-9),
      );
    });
    test('sign and logistic', () {
      final s = recoveryScore([
        const RecoveryInput(
          value: 40,
          baseline: b,
          higherIsBetter: false,
          weight: 0.4,
        ),
      ])!;
      expect(s, closeTo(100 / (1 + exp(-1.5)), 1e-9));
    });
    test('missing inputs renormalise; none → null', () {
      expect(
        recoveryScore([
          const RecoveryInput(
            value: null,
            baseline: b,
            higherIsBetter: true,
            weight: 0.4,
          ),
          const RecoveryInput(
            value: 60,
            baseline: b,
            higherIsBetter: true,
            weight: 0.3,
          ),
        ]),
        closeTo(100 / (1 + exp(-1.5)), 1e-9),
      );
      expect(
        recoveryScore([
          const RecoveryInput(
            value: null,
            baseline: b,
            higherIsBetter: true,
            weight: 1,
          ),
        ]),
        isNull,
      );
    });
    test('colours and targets', () {
      expect(recoveryColor(67), RecoveryColor.green);
      expect(recoveryColor(66.9), RecoveryColor.yellow);
      expect(recoveryColor(34), RecoveryColor.yellow);
      expect(recoveryColor(33), RecoveryColor.red);
      expect(targetStrain(RecoveryColor.red).high, 10);
    });
  });

  group('scoreDay', () {
    final day = DateTime(2026, 3, 2);
    final bed = DateTime(2026, 3, 1, 23);
    final wake = bed.add(const Duration(hours: 8));
    List<Minute> fullDay() => [
      ...run(bed, 480, hr: 52, stage: Stage.light),
      ...run(wake, 60, hr: 150), // workout
      ...run(wake.add(const Duration(hours: 1)), 600, hr: 70),
    ];

    test('finds the night and scores strain from wake', () {
      final s = scoreDay(date: day, minutes: fullDay());
      expect(s.sleepStart, bed);
      expect(s.sleepEnd, wake);
      expect(s.sleptHours, 8);
      expect(s.rhr, 52);
      expect(s.needHours, 7.5);
      expect(s.sleepPerf, 100);
      expect(s.strain, greaterThan(0));
      expect(s.calibrating, isTrue);
      expect(s.algoVersion, algoVersion);
      final expected = trimp(
        [...List.filled(60, 150), ...List.filled(600, 70)],
        hrRest: 52,
        hrMax: 190,
      );
      expect(s.trimp, closeTo(expected, 1e-9));
    });

    test('recovery once there is history', () {
      final hist = [
        for (var i = 1; i <= 20; i++)
          DailyScore(
            date: day.subtract(Duration(days: i)),
            strain: 10,
            trimp: 100,
            hrMax: 190,
            sleptHours: 7,
            needHours: 7.5,
            sleepPerf: 90 + (i % 3).toDouble(),
            rhr: 55 + (i % 3).toDouble(),
          ),
      ];
      final s = scoreDay(date: day, minutes: fullDay(), history: hist);
      expect(s.calibrating, isFalse);
      // Lower RHR and better sleep than baseline → above 50.
      expect(s.recovery, greaterThan(50));
      expect(s.needHours, closeTo(7.5 + 0.5 * 2 + 0.03 * 10, 1e-9));
    });

    test('a daytime nap is found and counted in tomorrow\'s debt', () {
      final m = [
        ...fullDay(),
        ...run(DateTime(2026, 3, 2, 18), 40, hr: 60, stage: Stage.light),
      ];
      final s = scoreDay(date: day, minutes: m);
      expect(s.napHours, closeTo(40 / 60, 1e-9));
      expect(s.sleepEnd, wake); // the nap is not the night
      final next = DailyScore(
        date: day,
        strain: 0,
        trimp: 0,
        hrMax: 190,
        sleptHours: 7,
        needHours: 7.5,
        napHours: 0.5,
      );
      final t = scoreDay(
        date: day.add(const Duration(days: 1)),
        minutes: run(DateTime(2026, 3, 2, 23), 480, hr: 52, stage: Stage.light),
        history: [next],
      );
      // 7 + 0.5 slept against 7.5 → no debt.
      expect(t.needHours, closeTo(7.5, 1e-9));
    });

    test('extra TRIMP adds to the day', () {
      final a = scoreDay(date: day, minutes: fullDay());
      final b = scoreDay(date: day, minutes: fullDay(), extraTrimp: 20);
      expect(b.trimp, closeTo(a.trimp + 20, 1e-9));
      expect(b.strain, greaterThan(a.strain));
    });

    test('base need is learned from history', () {
      final hist = [
        for (var i = 1; i <= 21; i++)
          DailyScore(
            date: day.subtract(Duration(days: i)),
            strain: 0,
            trimp: 0,
            hrMax: 190,
            sleptHours: i <= 7 ? 8.5 : 7,
            needHours: 7,
            recovery: i <= 7 ? 90 : 40,
            calibrating: false,
          ),
      ];
      final s = scoreDay(date: day, minutes: fullDay(), history: hist);
      expect(s.baseNeedHours, 8.5);
    });

    test('no sleep data → no sleep scores', () {
      final s = scoreDay(
        date: day,
        minutes: run(day.add(const Duration(hours: 8)), 60, hr: 80),
      );
      expect(s.sleepPerf, isNull);
      expect(s.recovery, isNull);
    });
  });

  test('band-marked walking names the sport despite uneven cadence', () {
    final t = DateTime(2026, 10, 5, 18, 39);
    final mins = [
      for (var i = 0; i < 30; i++)
        Minute(
          t.add(Duration(minutes: i)),
          hr: 100,
          steps: i.isEven ? 105 : 40, // stops at crossings: avg ~72/min
          stage: Stage.wake,
          bandWalking: true,
        ),
    ];
    final a = detectActivities(mins, hrMax: 175).single;
    expect(a.sport, Sport.walking);
    final unmarked = [
      for (final m in mins)
        Minute(m.ts, hr: m.hr, steps: m.steps, stage: m.stage),
    ];
    expect(
      detectActivities(unmarked, hrMax: 175).single.sport,
      isNot(Sport.walking),
    );
  });
}
