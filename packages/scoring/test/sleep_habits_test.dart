import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  NightSpan night(int day, int bedH, int bedM, double hours) {
    final start = DateTime(2026, 10, day, bedH, bedM);
    return (
      start: start,
      end: start.add(Duration(minutes: (hours * 60).round())),
    );
  }

  group('sleep type', () {
    test('mid-sleep wraps midnight', () {
      expect(midSleepMinute(night(1, 23, 0, 8)), 180); // 03:00
      expect(midSleepMinute(night(1, 21, 0, 2)), -120); // 22:00
    });

    test('birds by mid-sleep', () {
      expect(birdFor(180), Bird.lark);
      expect(birdFor(240), Bird.dove);
      expect(birdFor(300), Bird.owl);
    });

    test('a late, wandering, long sleeper is a restless owl', () {
      // Bedtimes spread from 23:00 to 02:00, ~9 h: mid-sleep about 05:10.
      const beds = [
        (23, 0),
        (23, 40),
        (0, 20),
        (1, 0),
        (1, 40),
        (23, 10),
        (0, 50),
        (1, 30),
        (23, 30),
        (0, 10),
        (1, 20),
        (2, 0),
        (23, 50),
        (0, 40),
      ];
      final ns = [
        for (final (i, (h, m)) in beds.indexed) night(i + 1, h, m, 9),
      ];
      final t = sleepType(ns)!;
      expect(t.bird, Bird.owl);
      expect(t.steadiness, Steadiness.restless);
      expect(t.name, 'Restless owl');
      expect(t.longSleeper, isTrue);
      expect(sleepTypeLine(t), 'A night person whose bedtime wanders.');
      expect(sleepTypeTip(t), contains('fixed wake time'));
    });

    test('SRI decides steadiness when there is one', () {
      final ns = [for (var d = 1; d <= 7; d++) night(d, 22, 0, 7.5)];
      expect(sleepType(ns, sri: 85)!.name, 'Steady lark');
      expect(sleepType(ns, sri: 70)!.steadiness, Steadiness.wandering);
      expect(sleepType(ns, sri: 50)!.steadiness, Steadiness.restless);
      // Without SRI, the same bedtime every night is steady.
      expect(sleepType(ns)!.steadiness, Steadiness.steady);
    });

    test('needs a week of nights', () {
      expect(
        sleepType([for (var d = 1; d <= 6; d++) night(d, 23, 0, 8)]),
        isNull,
      );
    });
  });

  group('weakest area', () {
    test('picks the biggest gap; ties and no gap go to regularity', () {
      expect(
        weakestSleepArea(sri: 43, hours: 8.8, needHours: 7),
        SleepFocus.regularity,
      );
      expect(
        weakestSleepArea(sri: 82, hours: 5.8, needHours: 7.5),
        SleepFocus.duration,
      );
      expect(
        weakestSleepArea(sri: 78, hours: 7.5, needHours: 7.5, latencyMin: 45),
        SleepFocus.fallingAsleep,
      );
      expect(weakestSleepArea(), SleepFocus.regularity);
      expect(
        weakestSleepArea(bedtimeConsistency: .3, hours: 7, needHours: 7),
        SleepFocus.regularity,
      );
    });
  });

  group('plan', () {
    final weeks = sleepWeeks(
      SleepFocus.regularity,
      wakeMinute: 8 * 60,
      bedMinute: 23 * 60 + 15,
    );

    test('three weeks, one habit each, with the times filled in', () {
      expect(weeks.length, 3);
      expect(weeks[0].habit.title, 'Up by 8:00');
      expect(weeks[0].habit.auto, isTrue);
      expect(weeks[2].habit.title, 'Wind down from 22:45');
      expect(
        sleepWeeks(
          SleepFocus.duration,
          wakeMinute: 420,
          bedMinute: 1380,
        ).first.habit.title,
        'Lights out by 23:00',
      );
    });

    test('each week adds a habit and keeps the earlier ones', () {
      expect(habitsOn(weeks, 0).map((h) => h.id), ['wake']);
      expect(habitsOn(weeks, 7).map((h) => h.id), ['wake', 'light']);
      expect(habitsOn(weeks, 20).map((h) => h.id), ['wake', 'light', 'wind']);
    });

    test('plan days', () {
      final s = DateTime(2026, 10, 26);
      expect(sleepPlanDay(s, DateTime(2026, 10, 26, 23)), 0);
      expect(sleepPlanDay(s, DateTime(2026, 11, 15)), 20);
      expect(sleepPlanDay(s, DateTime(2026, 11, 16)), isNull);
      expect(sleepPlanDay(s, DateTime(2026, 10, 25)), isNull);
    });

    test('times kept within 30 minutes, earlier always counts', () {
      expect(keptTime(8 * 60 + 25, 8 * 60), isTrue);
      expect(keptTime(9 * 60 + 9, 8 * 60), isFalse);
      expect(keptTime(7 * 60, 8 * 60), isTrue);
      // Across midnight: asleep at 00:20 for a 23:45 target is 35 late.
      expect(keptTime(20, 23 * 60 + 45), isFalse);
      expect(keptTime(23 * 60 + 30, 23 * 60 + 45), isTrue);
    });

    test('a day is kept at two thirds', () {
      expect(dayKept(1, 1), isTrue);
      expect(dayKept(1, 2), isFalse);
      expect(dayKept(2, 3), isTrue);
      expect(dayKept(0, 0), isFalse);
    });
  });

  group('vs normal', () {
    final past = <double>[60, 62, 58, 61, 59, 60, 60];
    test('flat within half an SD or the minimum', () {
      expect(vsNormal(60.5, past)!.trend, Trend.flat);
      expect(vsNormal(63, past, minDelta: 5)!.trend, Trend.flat);
    });
    test('direction and whether it is good', () {
      final up = vsNormal(70, past)!;
      expect(up.trend, Trend.up);
      expect(up.good, isTrue);
      expect(up.delta, closeTo(10, .01));
      final rhr = vsNormal(55, past, better: Better.lower)!;
      expect(rhr.trend, Trend.down);
      expect(rhr.good, isTrue);
      expect(vsNormal(70, past, better: Better.neither)!.good, isNull);
    });
    test('needs five past values', () {
      expect(vsNormal(60, <double?>[60, null, 61, 59]), isNull);
      expect(vsNormal(null, past), isNull);
    });
  });
}
