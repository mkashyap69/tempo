import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  /// 120 days: alcohol costs 8 recovery points; late meals ride along with
  /// alcohol 70 % of the time but do nothing; strength days come with
  /// higher strain, and strain (not strength) costs recovery.
  List<ImpactDay> planted({int n = 120, int seed = 3}) {
    final r = Random(seed);
    final d0 = DateTime(2026, 1, 1);
    return [
      for (var i = 0; i < n; i++)
        () {
          final alcohol = r.nextDouble() < .3;
          final lateMeal = alcohol ? r.nextDouble() < .7 : r.nextDouble() < .15;
          final strength = r.nextDouble() < .35;
          final strain = 8 + (strength ? 6 : 0) + r.nextDouble() * 4;
          final rec =
              70 -
              (alcohol ? 8 : 0) -
              1.2 * (strain - 10) +
              (r.nextDouble() - .5) * 12;
          final date = d0.add(Duration(days: i));
          return ImpactDay(
            date: date,
            x: {
              'alcohol': alcohol ? 1 : 0,
              'late_meal': lateMeal ? 1 : 0,
              'auto_strength': strength ? 1 : 0,
            },
            y: {Outcome.recovery: rec},
            strain: strain,
            weekend: date.add(const Duration(days: 1)).weekday >= 6,
          );
        }(),
    ];
  }

  const bs = [
    Behaviour('alcohol'),
    Behaviour('late_meal'),
    Behaviour('auto_strength'),
  ];

  test('finds the planted effect, not the confounded one', () {
    final r = {
      for (final i in impacts(planted(), bs, Outcome.recovery)) i.key: i,
    };
    final a = r['alcohol']!;
    expect(a.shown, isTrue);
    expect(a.effect, inInclusiveRange(-10, -5));
    expect(a.low, lessThan(a.effect));
    expect(a.high, greaterThan(a.effect));
    expect(a.helps, isFalse);
    expect(r['late_meal']!.shown, isFalse);
    // Strain is a covariate, so strength days aren't blamed for it.
    expect(r['auto_strength']!.shown, isFalse);
  });

  test('a plain mean difference would have blamed late meals', () {
    final days = planted();
    double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final yes = mean([
      for (final d in days)
        if (d.x['late_meal'] == 1) d.y[Outcome.recovery]!,
    ]);
    final no = mean([
      for (final d in days)
        if (d.x['late_meal'] == 0) d.y[Outcome.recovery]!,
    ]);
    expect(yes - no, lessThan(-3));
  });

  test('too few days of each kind is notEnough', () {
    final r = impacts(planted(n: 8), bs, Outcome.recovery);
    expect(r.every((i) => i.confidence == ImpactConfidence.notEnough), isTrue);
  });

  test('deterministic for a seed', () {
    final a = impacts(planted(), bs, Outcome.recovery, seed: 9);
    final b = impacts(planted(), bs, Outcome.recovery, seed: 9);
    expect([for (final i in a) i.low], [for (final i in b) i.low]);
  });

  test('amounts are reported per dose', () {
    final r = Random(5);
    final d0 = DateTime(2026, 1, 1);
    final days = [
      for (var i = 0; i < 90; i++)
        () {
          final mg = [0, 0, 100, 200, 300, 400][r.nextInt(6)].toDouble();
          return ImpactDay(
            date: d0.add(Duration(days: i)),
            x: {'caffeine_mg': mg},
            y: {
              Outcome.sleptHours:
                  7.5 - .25 * mg / 100 + (r.nextDouble() - .5) * .4,
            },
          );
        }(),
    ];
    final i = impacts(days, const [
      Behaviour('caffeine_mg', binary: false, dose: 100),
    ], Outcome.sleptHours).single;
    expect(i.effect, closeTo(-.25, .06));
    expect(i.shown, isTrue);
  });

  test('unknown days are not counted as no', () {
    final days = [
      for (var i = 0; i < 20; i++)
        ImpactDay(
          date: DateTime(2026, 1, 1 + i),
          x: i < 3 ? {'travel': 1} : const {},
          y: {Outcome.recovery: 60},
        ),
    ];
    final i = impacts(days, const [
      Behaviour('travel'),
    ], Outcome.recovery).single;
    expect(i.nYes, 3);
    expect(i.nNo, 0);
    expect(i.confidence, ImpactConfidence.notEnough);
  });

  group('experiments', () {
    final start = DateTime(2026, 3, 1);
    List<ImpactDay> run({required double change, bool keep = true}) {
      final r = Random(2);
      return [
        for (var i = -14; i < 14; i++)
          () {
            final date = start.add(Duration(days: i));
            final during = i >= 0;
            return ImpactDay(
              date: date,
              x: {'caffeine_late': during && keep ? 0 : 1},
              y: {
                Outcome.sleepPerf:
                    80 + (during ? change : 0) + (r.nextDouble() - .5) * 6,
              },
              strain: 10,
            );
          }(),
      ];
    }

    final e = Experiment(key: 'caffeine_late', doIt: false, start: start);

    test('a real change shows with its range and adherence', () {
      final res = experimentResult(e, run(change: 6), Outcome.sleepPerf);
      expect(res.daysBefore, 14);
      expect(res.daysDuring, 14);
      expect(res.adherence, 1);
      expect(res.effect, inInclusiveRange(3, 8));
      expect(
        res.confidence.index,
        greaterThanOrEqualTo(ImpactConfidence.low.index),
      );
    });

    test('no change: no effect; not kept: adherence 0', () {
      final none = experimentResult(e, run(change: 0), Outcome.sleepPerf);
      expect(none.confidence, ImpactConfidence.none);
      final broken = experimentResult(
        e,
        run(change: 0, keep: false),
        Outcome.sleepPerf,
      );
      expect(broken.adherence, 0);
    });

    test('days and running', () {
      expect(e.runningOn(start), isTrue);
      expect(e.runningOn(start.add(const Duration(days: 14))), isFalse);
      expect(e.dayOn(start.add(const Duration(days: 4))), 5);
    });
  });
}
