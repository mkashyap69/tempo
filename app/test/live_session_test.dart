import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/state/live_session.dart';

LiveState _live({int? bpm = 110, bool timerOnly = false}) => LiveState(
  phase: LivePhase.live,
  sport: sc.Sport.walking,
  title: 'Walking · open session',
  bpm: bpm,
  hrMax: 190,
  hrRest: 60,
  timerOnly: timerOnly,
);

void main() {
  group('LiveState.advance', () {
    test('sub-second ticks still count toward zone time', () {
      // Timer.periodic(1 s) drifts under a second about half the time; the
      // old whole-second sum dropped those ticks.
      var s = _live();
      for (var i = 0; i < 600; i++) {
        s = s.advance(
          Duration(milliseconds: i.isEven ? 999 : 1001),
          lost: false,
        );
      }
      final zoned = s.zoneSeconds.fold(0.0, (a, b) => a + b);
      expect(zoned, closeTo(s.elapsed.inMicroseconds / 1e6, 1e-6));
      expect(zoned, closeTo(600, .01));
    });

    test('zones plus no-signal time add up to elapsed', () {
      var s = _live();
      for (var i = 0; i < 120; i++) {
        s = s.advance(const Duration(milliseconds: 998), lost: i >= 90);
      }
      final zoned = s.zoneSeconds.fold(0.0, (a, b) => a + b);
      expect(s.noSignalSeconds, closeTo(30 * .998, 1e-6));
      expect(
        zoned + s.noSignalSeconds,
        closeTo(s.elapsed.inMicroseconds / 1e6, 1e-6),
      );
      expect(s.signalLost, isTrue);
      expect(s.bpm, isNull);
    });

    test('below Z1 counts as Z1', () {
      final s = _live(bpm: 80).advance(const Duration(seconds: 2), lost: false);
      expect(s.zoneSeconds.first, 2);
    });

    test('timer-only sessions log no gap', () {
      final s = _live(
        bpm: null,
        timerOnly: true,
      ).advance(const Duration(seconds: 5), lost: false);
      expect(s.noSignalSeconds, 0);
      expect(s.elapsed, const Duration(seconds: 5));
    });

    test('trace keeps only the last 15 minutes', () {
      var s = _live();
      for (var i = 0; i < LiveState.traceWindow + 120; i++) {
        s = s.advance(const Duration(seconds: 1), lost: false);
      }
      expect(s.trace.length, LiveState.traceWindow);
      expect(s.trace.last.$1, s.elapsed.inSeconds);
      expect(s.trace.first.$1, greaterThan(s.elapsed.inSeconds - 900));
    });
  });

  group('projection', () {
    LiveState run(int bpm, int minutes) {
      var s = _live(bpm: bpm);
      for (var i = 0; i < minutes * 60; i++) {
        s = s.advance(const Duration(seconds: 1), lost: false);
      }
      return s;
    }

    test('needs a minute of readings', () {
      expect(run(140, 0).minutesTo(10), isNull);
      expect(run(140, 0).strainRate, isNull);
    });

    test('minutes to a goal match the strain curve', () {
      final s = run(150, 10);
      final goal = s.dayStrain + 2;
      final m = s.minutesTo(goal)!;
      final per = sc.minuteTrimp(150, hrRest: 60, hrMax: 190);
      expect(sc.strainFromTrimp(s.trimp + per * m), greaterThanOrEqualTo(goal));
      expect(sc.strainFromTrimp(s.trimp + per * (m - 1)), lessThan(goal));
    });

    test('null when already there or out of reach', () {
      final s = run(150, 10);
      expect(s.minutesTo(s.dayStrain - .1), isNull);
      expect(run(70, 5).minutesTo(15), isNull);
    });
  });
}
