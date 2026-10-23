import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('recovery penalty', () {
    test('nothing within 1.5 SD; 4 points per SD beyond; caps', () {
      expect(recoveryPenalty([null, 1.0, 1.5, -3]), 0);
      expect(recoveryPenalty([2.5]), closeTo(4, 1e-9));
      expect(recoveryPenalty([6]), 8); // per-signal cap
      expect(recoveryPenalty([6, 6, 6]), 15); // total cap
    });
  });

  group('sleep score v3', () {
    test('all parts perfect is 100; sufficiency alone is itself', () {
      final s = sleepScoreV3(
        sufficiency: 100,
        bedDeviationMinutes: 0,
        efficiency: .95,
        wasoMin: 5,
        wakeBoutCount: 0,
        latencyMinutes: 10,
      );
      expect(s.score, closeTo(100, 1e-9));
      expect(sleepScoreV3(sufficiency: 72).score, closeTo(72, 1e-9));
      // Sufficiency over 100 doesn't lift the score past 100.
      expect(sleepScoreV3(sufficiency: 115).score, closeTo(100, 1e-9));
    });

    test('Ohayon 2017 bands: good is 100, poor is 0, linear between', () {
      final good = sleepScoreV3(
        sufficiency: 100,
        efficiency: .85,
        wasoMin: 20,
        wakeBoutCount: 1,
        latencyMinutes: 30,
      );
      expect(good.efficiency, 100);
      expect(good.continuity, 100);
      expect(good.latency, 100);
      final poor = sleepScoreV3(
        sufficiency: 100,
        efficiency: .74,
        wasoMin: 51,
        wakeBoutCount: 4,
        latencyMinutes: 46,
      );
      expect(poor.efficiency, 0);
      expect(poor.continuity, 0);
      expect(poor.latency, 0);
      expect(
        sleepScoreV3(sufficiency: 100, efficiency: .795).efficiency,
        closeTo(50, 1e-9),
      );
    });

    test('bedtime loses its points over three hours', () {
      expect(
        sleepScoreV3(sufficiency: 100, bedDeviationMinutes: 90).regularity,
        closeTo(50, 1e-9),
      );
      expect(
        sleepScoreV3(sufficiency: 100, bedDeviationMinutes: -200).regularity,
        0,
      );
    });

    test(
      '23 Oct: 7h 07m, 73 min late, 5 min awake scores near Apple\'s 82',
      () {
        // Apple Health gave this night 82 (duration 46/50, bedtime 17/30,
        // interruptions 19/20). Algo 9 gave 73 against an 8h 49m need.
        final s = sleepScoreV3(
          sufficiency: sleepSufficiency(7 + 7 / 60, 7.5),
          bedDeviationMinutes: 73,
          wasoMin: 5,
          wakeBoutCount: 0,
        );
        // Components: sufficiency 95 (Apple 92), bedtime 59 (Apple 57),
        // continuity 100 (Apple 95): ~87, against algo 9's 73.
        expect(s.score, inInclusiveRange(80, 90));
      },
    );

    test('a late, broken night scores below its sufficiency', () {
      final s = sleepScoreV3(
        sufficiency: 90,
        bedDeviationMinutes: 200,
        efficiency: .70,
        wasoMin: 60,
        wakeBoutCount: 5,
        latencyMinutes: 50,
      );
      expect(s.regularity, 0);
      expect(s.efficiency, 0);
      expect(s.continuity, 0);
      expect(s.score, closeTo(45, 1e-9));
    });

    test('wake bouts count runs of 5+ minutes', () {
      final t0 = DateTime(2026, 1, 1, 23);
      Minute m(int i, Stage st) =>
          Minute(t0.add(Duration(minutes: i)), stage: st);
      final mins = [
        for (var i = 0; i < 60; i++) m(i, Stage.light),
        for (var i = 60; i < 66; i++) m(i, Stage.wake), // bout
        for (var i = 66; i < 120; i++) m(i, Stage.deep),
        for (var i = 120; i < 123; i++) m(i, Stage.wake), // too short
        for (var i = 123; i < 200; i++) m(i, Stage.light),
      ];
      expect(wakeBouts(SleepSession(mins)), 1);
    });
  });

  group('strain target and load', () {
    test('room to build under a light, well-recovered month', () {
      final t = strainTarget(
        recovery: 75,
        load: LoadStatus.detraining,
        loadRatio: .7,
      );
      expect((t.lo, t.hi), (14, 17));
    });

    test('a hot week loses a point off the top', () {
      final t = strainTarget(
        recovery: 75,
        load: LoadStatus.building,
        loadRatio: 1.25,
      );
      expect((t.lo, t.hi), (13, 15));
    });

    test('rest caps and learning are untouched', () {
      expect(
        strainTarget(
          recovery: 30,
          load: LoadStatus.detraining,
          loadRatio: .5,
        ).cap,
        isTrue,
      );
      final l = strainTarget(recovery: 75, loadRatio: .5);
      expect((l.lo, l.hi), (13, 16));
    });
  });

  test('algo 10', () => expect(algoVersion, 10));
}
