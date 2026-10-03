import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> run(DateTime from, int n, {int? hr, Stage stage = Stage.wake}) => [
  for (var i = 0; i < n; i++)
    Minute(
      from.add(Duration(minutes: i)),
      hr: hr,
      stage: stage,
    ),
];

void main() {
  group('strain', () {
    test('minute TRIMP formula', () {
      // r = 0.5 → 0.5 · 0.64 · e^0.96
      expect(
        minuteTrimp(125, hrRest: 60, hrMax: 190),
        closeTo(0.5 * 0.64 * exp(0.96), 1e-9),
      );
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
      expect(strainFromTrimp(120), closeTo(21 * (1 - exp(-1)), 1e-9));
      expect(strainFromTrimp(10000), lessThanOrEqualTo(21));
      expect(strainFromTrimp(50), lessThan(strainFromTrimp(60)));
    });
    test('trimp skips nulls', () {
      expect(
        trimp([null, 125, null], hrRest: 60, hrMax: 190),
        closeTo(minuteTrimp(125, hrRest: 60, hrMax: 190), 1e-9),
      );
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
    test('merges short wake gaps, splits long ones', () {
      final m = [
        ...run(t, 120, stage: Stage.light),
        ...run(t.add(const Duration(minutes: 120)), 20),
        ...run(t.add(const Duration(minutes: 140)), 120, stage: Stage.deep),
        ...run(t.add(const Duration(minutes: 260)), 60),
        ...run(t.add(const Duration(minutes: 320)), 90, stage: Stage.rem),
      ];
      final s = detectSessions(m);
      expect(s.length, 2);
      expect(s[0].asleep.inMinutes, 240);
      expect(s[0].inBed.inMinutes, 260);
      expect(s[0].efficiency, closeTo(240 / 260, 1e-9));
      expect(s[1].stage(Stage.rem).inMinutes, 90);
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

    test('no sleep data → no sleep scores', () {
      final s = scoreDay(
        date: day,
        minutes: run(day.add(const Duration(hours: 8)), 60, hr: 80),
      );
      expect(s.sleepPerf, isNull);
      expect(s.recovery, isNull);
    });
  });
}
