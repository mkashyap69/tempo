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

  group('sleep score v2', () {
    test('all parts perfect is 100; sufficiency alone is itself', () {
      final s = sleepScoreV2(
        sleepPerf: 100,
        bedDeviationMinutes: 0,
        efficiency: .95,
        wakeBoutCount: 0,
        hrDipPct: 20,
      );
      expect(s.score, closeTo(100, 1e-9));
      expect(sleepScoreV2(sleepPerf: 72).score, closeTo(72, 1e-9));
    });

    test('a late, broken night scores below its sufficiency', () {
      final s = sleepScoreV2(
        sleepPerf: 90,
        bedDeviationMinutes: 120,
        efficiency: .70,
        wakeBoutCount: 5,
        hrDipPct: 3,
      );
      expect(s.regularity, 0);
      expect(s.efficiency, closeTo(20, 1e-9));
      expect(s.continuity, closeTo(25, 1e-9));
      expect(s.hrDip, closeTo(20, 1e-9));
      expect(s.score, lessThan(70));
    });

    test('wake bouts count runs of 5+ minutes', () {
      final t0 = DateTime(2026, 1, 1, 23);
      Minute m(int i, Stage st) => Minute(t0.add(Duration(minutes: i)), stage: st);
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

  test('algo 9', () => expect(algoVersion, 9));
}
