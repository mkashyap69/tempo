import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

final _day = DateTime(2026, 11, 20);

/// A waking day 06:00–22:00 (asleep before and after): still at [rest] bpm,
/// with [hrAt] overriding the heart rate and [stepsAt] adding steps.
List<Minute> _minutes({
  int rest = 60,
  int? Function(int minuteOfDay)? hrAt,
  int Function(int minuteOfDay)? stepsAt,
}) => [
  for (var m = 0; m < 1440; m++)
    () {
      final asleep = m < 6 * 60 || m >= 22 * 60;
      return Minute(
        _day.add(Duration(minutes: m)),
        hr: asleep ? 50 : (hrAt == null ? rest : hrAt(m)),
        steps: asleep ? 0 : (stepsAt?.call(m) ?? 0),
        stage: asleep ? Stage.light : Stage.wake,
      );
    }(),
];

void main() {
  test('the level curve: calm near 23, medium from z 1, high from z 2', () {
    expect(hrStressLevel(0), closeTo(22.9, .5));
    expect(hrStressLevel(1), closeTo(40, .5));
    expect(hrStressLevel(1.5), closeTo(50, .01));
    expect(hrStressLevel(2), closeTo(60, .5));
  });

  test('moving minutes and their neighbours are never scored', () {
    final mins = _minutes(stepsAt: (m) => m == 10 * 60 ? 30 : 0);
    final still = stillAwakeMinutes(mins);
    final idx = {
      for (final i in still) mins[i].ts.hour * 60 + mins[i].ts.minute,
    };
    for (var m = 10 * 60 - 2; m <= 10 * 60 + 2; m++) {
      expect(idx.contains(m), isFalse, reason: 'minute $m');
    }
    expect(idx.contains(10 * 60 - 3), isTrue);
    // Asleep minutes are out too.
    expect(idx.contains(3 * 60), isFalse);
  });

  test('workouts are left out', () {
    final mins = _minutes();
    final w = (
      _day.add(const Duration(hours: 18)),
      _day.add(const Duration(hours: 19)),
    );
    final still = stillAwakeMinutes(mins, workouts: [w]);
    expect(still.any((i) => mins[i].ts.hour == 18), isFalse);
  });

  test('quiet heart rate is a low quantile of hourly still means', () {
    // 06–14 at 58, 14–22 at 66: P10 of 8 × 58 and 8 × 66 is 58.
    final mins = _minutes(hrAt: (m) => m < 14 * 60 ? 58 : 66);
    expect(quietDaytimeHr(mins, stillAwakeMinutes(mins)), 58);
  });

  test('a still day at your quiet heart rate reads calm', () {
    final mins = _minutes();
    final d = hrStressDay(mins, priorQuiet: [59, 60, 61, 60, 60, 62, 58]);
    expect(d.provisional, isFalse);
    expect(d.reference, 60);
    expect(d.readings, isNotEmpty);
    expect(d.readings.every((r) => r.value < stressMedium), isTrue);
    expect(d.coverage.enough, isTrue);
    // One reading per 5-minute block of the 16 waking hours.
    expect(d.readings.length, 16 * 12);
  });

  test('a still stretch well above quiet reads high', () {
    // 14:00–15:00 at +12 bpm with a 3 bpm spread floor: z 4.
    final mins = _minutes(hrAt: (m) => m >= 14 * 60 && m < 15 * 60 ? 72 : 60);
    final d = hrStressDay(mins, priorQuiet: [60, 60, 61, 59, 60, 60]);
    final split = splitStress(d.readings, const []);
    expect(split.highMinutes, 60);
    expect(split.busiestHour, 14);
  });

  test('provisional with few earlier days: uses today and a wide spread', () {
    final mins = _minutes(hrAt: (m) => m >= 14 * 60 && m < 15 * 60 ? 72 : 60);
    final d = hrStressDay(mins);
    expect(d.provisional, isTrue);
    expect(d.reference, 60);
    // +12 bpm over a 7 bpm spread: z 1.7, medium rather than high.
    final high = d.readings.where((r) => r.ts.hour == 14).first.value;
    expect(high, inInclusiveRange(stressMedium, stressHigh - 1));
  });

  test('sparse heart rate is flagged as not enough', () {
    final mins = _minutes(hrAt: (m) => m % 10 == 0 ? 60 : null);
    final d = hrStressDay(mins);
    expect(d.coverage.enough, isFalse);
    expect(d.coverage.perHour, closeTo(6, .01));
  });

  test('no heart rate: no reference, no readings', () {
    final mins = _minutes(hrAt: (_) => null);
    final d = hrStressDay(mins);
    expect(d.reference, isNull);
    expect(d.readings, isEmpty);
  });
}
