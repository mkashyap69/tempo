import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 1, 8);
DateTime m(int minutes, [int seconds = 0]) =>
    t0.add(Duration(minutes: minutes, seconds: seconds));

HealthRecord rec(
  HealthKind k,
  DateTime a,
  DateTime b,
  double v, {
  String src = 'com.apple.health',
  String uuid = 'u',
}) => HealthRecord(
  uuid: uuid,
  kind: k,
  start: a,
  end: b,
  value: v,
  sourceApp: src,
);

HealthRecord hr(int minute, double bpm, {int s = 0, String src = 'w'}) =>
    rec(HealthKind.heartRate, m(minute, s), m(minute, s), bpm, src: src);

void main() {
  group('heart rate', () {
    test('averages a minute and interpolates gaps up to 15 min', () {
      final g = HealthGrid()
        ..addAll([hr(0, 60), hr(0, 70, s: 30), hr(5, 75), hr(30, 90)]);
      final xs = g.minutes(m(0), m(33));
      expect(xs[0].hr, 65);
      expect(xs[0].hrMeasured, isTrue);
      // 65 → 75 over 5 minutes.
      expect([for (final x in xs.take(6)) x.hr], [65, 67, 69, 71, 73, 75]);
      expect(xs[1].hrMeasured, isFalse);
      // 5 → 30 is a 25-min gap: held 2 min, then empty (watch off).
      expect(xs[6].hr, 75);
      expect(xs[7].hr, 75);
      expect(xs[8].hr, isNull);
      expect(xs[29].hr, isNull);
      expect(xs[30].hr, 90);
      expect(xs[32].hr, 90);
    });

    test('interpolates across the edge of the asked range', () {
      final g = HealthGrid()..addAll([hr(0, 60), hr(10, 80)]);
      final xs = g.minutes(m(5), m(6));
      expect(xs.single.hr, 70);
    });

    test('drops glitches', () {
      final g = HealthGrid()..addAll([hr(0, 0), hr(1, 250), hr(2, 20)]);
      expect(g.minutes(m(0), m(3)).every((x) => x.hr == null), isTrue);
      expect(g.first, isNull);
    });

    test("ignores Tempo's own records", () {
      final g = HealthGrid()..add(hr(0, 70, src: tempoAppId));
      expect(g.minutes(m(0), m(1)).single.hr, isNull);
    });
  });

  group('steps', () {
    test('spreads an interval over its minutes', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.steps, m(0), m(4), 400, src: 'phone'));
      expect(
        [for (final x in g.minutes(m(0), m(5))) x.steps],
        [100, 100, 100, 100, 0],
      );
    });

    test('takes the busier app per minute instead of summing', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.steps, m(0), m(2), 200, src: 'phone'))
        ..add(rec(HealthKind.steps, m(0), m(2), 240, src: 'watch'));
      expect([for (final x in g.minutes(m(0), m(2))) x.steps], [120, 120]);
    });

    test('sums one app across its own records', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.steps, m(0, 0), m(0, 30), 40, src: 'w'))
        ..add(rec(HealthKind.steps, m(0, 30), m(0, 50), 30, src: 'w'));
      expect(g.minutes(m(0), m(1)).single.steps, 70);
    });

    test('caps an impossible minute', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.steps, m(0), m(0), 5000, src: 'w'));
      expect(g.minutes(m(0), m(1)).single.steps, 300);
    });
  });

  group('sleep', () {
    test('stages beat asleep, asleep beats awake', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.sleepAwake, m(0), m(4), 4, src: 'a'))
        ..add(rec(HealthKind.sleepAsleep, m(1), m(4), 3, src: 'b'))
        ..add(rec(HealthKind.sleepDeep, m(2), m(3), 1, src: 'c'))
        ..add(rec(HealthKind.sleepRem, m(2), m(4), 2, src: 'd'));
      expect(
        [for (final x in g.minutes(m(0), m(5))) x.sleep],
        [
          SleepMark.awake,
          SleepMark.asleep,
          SleepMark.deep,
          SleepMark.rem,
          null,
        ],
      );
    });

    test('in bed counts as asleep only with no stages inside it', () {
      final phoneOnly = HealthGrid()
        ..add(rec(HealthKind.sleepInBed, m(0), m(3), 3, src: 'phone'));
      expect(
        phoneOnly.minutes(m(0), m(3)).map((x) => x.sleep),
        everyElement(SleepMark.asleep),
      );

      // A watch's stages make the rest of in-bed time awake in bed.
      final withWatch = HealthGrid()
        ..add(rec(HealthKind.sleepInBed, m(0), m(6), 6, src: 'phone'))
        ..add(rec(HealthKind.sleepLight, m(2), m(4), 2, src: 'watch'));
      expect(
        [for (final x in withWatch.minutes(m(0), m(6))) x.sleep],
        [null, null, SleepMark.light, SleepMark.light, null, null],
      );
    });

    test('a Health Connect session with stages uses the stages', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.sleepSession, m(0), m(4), 4, src: 'fitbit'))
        ..add(rec(HealthKind.sleepAwake, m(0), m(1), 1, src: 'fitbit'))
        ..add(rec(HealthKind.sleepDeep, m(1), m(4), 3, src: 'fitbit'));
      expect(
        [for (final x in g.minutes(m(0), m(4))) x.sleep],
        [SleepMark.awake, SleepMark.deep, SleepMark.deep, SleepMark.deep],
      );
    });

    test('a stage shorter than a minute marks only its own minute', () {
      final g = HealthGrid()
        ..add(rec(HealthKind.sleepAwake, m(1, 10), m(1, 50), 1, src: 'w'));
      expect(
        [for (final x in g.minutes(m(0), m(3))) x.sleep],
        [null, SleepMark.awake, null],
      );
    });
  });

  group('spo2', () {
    test('fractions and percents both read as percent', () {
      expect(normalizeSpo2(.97), 97);
      expect(normalizeSpo2(96), 96);
      expect(normalizeSpo2(.3), isNull);
      expect(normalizeSpo2(140), isNull);
      final g = HealthGrid()
        ..add(rec(HealthKind.spo2, m(0), m(0), .95))
        ..add(rec(HealthKind.spo2, m(0, 20), m(0, 20), 97));
      expect(g.minutes(m(0), m(1)).single.spo2, 96);
    });
  });

  group('scoring minutes', () {
    test('worn, awake and not-worn minutes', () {
      final xs = scoringMinutes([
        HealthMinute(m(0), hr: 60),
        HealthMinute(m(1), steps: 10),
        HealthMinute(m(2)),
        HealthMinute(m(3), sleep: SleepMark.rem),
      ]).minutes;
      expect(
        [for (final x in xs) x.stage],
        [Stage.wake, Stage.wake, Stage.unknown, Stage.rem],
      );
      expect([for (final x in xs) x.offWrist], [false, false, true, false]);
    });

    test('unstaged only when no minute has a real stage', () {
      expect(
        scoringMinutes([HealthMinute(m(0), sleep: SleepMark.asleep)]).unstaged,
        isTrue,
      );
      expect(
        scoringMinutes([
          HealthMinute(m(0), sleep: SleepMark.asleep),
          HealthMinute(m(1), sleep: SleepMark.deep),
        ]).unstaged,
        isFalse,
      );
    });

    test('a staged Health night scores as one sleep', () {
      // 23:00–07:00 with light, deep, REM and a short wake, HR every 5 min.
      final start = DateTime(2026, 10, 1, 23);
      DateTime at(int min) => start.add(Duration(minutes: min));
      final g = HealthGrid();
      for (var i = 0; i < 480; i += 5) {
        g.add(
          rec(
            HealthKind.heartRate,
            at(i),
            at(i),
            52.0 + (i % 20) / 5,
            src: 'w',
          ),
        );
      }
      g
        ..add(rec(HealthKind.sleepLight, at(0), at(120), 0, src: 'w'))
        ..add(rec(HealthKind.sleepDeep, at(120), at(200), 0, src: 'w'))
        ..add(rec(HealthKind.sleepAwake, at(200), at(210), 0, src: 'w'))
        ..add(rec(HealthKind.sleepRem, at(210), at(300), 0, src: 'w'))
        ..add(rec(HealthKind.sleepLight, at(300), at(480), 0, src: 'w'));
      final mins = scoringMinutes(
        g.minutes(start.subtract(const Duration(hours: 12)), at(480 + 600)),
      ).minutes;
      final s = scoreDay(date: DateTime(2026, 10, 2), minutes: mins);
      expect(s.sleepStart, start);
      expect(s.sleepEnd, at(480));
      expect(s.sleptHours, closeTo(470 / 60, 1e-9));
      expect(s.rhr, isNotNull);
    });
  });
}
