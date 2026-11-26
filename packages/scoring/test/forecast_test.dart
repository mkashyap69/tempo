import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// P4: tomorrow's recovery from tonight's plan.
void main() {
  // 24 simulated nights: sleep and sleeping HR wobble, scored in order.
  final d0 = DateTime(2026, 1, 1);
  final minutes = <Minute>[];
  final rng = Random(11);
  final nights = [
    for (var i = 0; i < 40; i++)
      (hours: 6.5 + rng.nextInt(9) / 4, hr: 46 + rng.nextInt(8)),
  ];
  for (var i = 0; i < nights.length; i++) {
    final bed = d0.add(Duration(days: i - 1, hours: 23));
    final asleep = (nights[i].hours * 60).round();
    for (var m = 0; m < 24 * 60; m++) {
      minutes.add(
        Minute(
          bed.add(Duration(minutes: m)),
          hr: m < asleep ? nights[i].hr + m % 3 : 70,
          stage: m < asleep ? Stage.light : Stage.wake,
        ),
      );
    }
  }
  final history = <DailyScore>[];
  for (var i = 0; i < nights.length - 1; i++) {
    final day = d0.add(Duration(days: i));
    history.insert(
      0,
      scoreDay(
        date: day,
        minutes: [
          for (final m in minutes)
            if (!m.ts.isBefore(day.subtract(const Duration(hours: 12))) &&
                m.ts.isBefore(day.add(const Duration(hours: 36))))
              m,
        ],
        history: [...history],
      ),
    );
  }

  final today = history.first;
  final past = history.sublist(1);

  test('a band around a middle, more sleep is better', () {
    final f = recoveryForecast(today: today, history: past, sleepHours: 8)!;
    expect(f.low, lessThanOrEqualTo(f.mid));
    expect(f.mid, lessThanOrEqualTo(f.high));
    expect(f.mid, inInclusiveRange(1, 99));
    expect(f.mornings, greaterThanOrEqualTo(forecastMinMornings));
    final short = recoveryForecast(today: today, history: past, sleepHours: 5)!;
    expect(short.mid, lessThan(f.mid));
    expect(f.hourLessCost, greaterThan(0));
  });

  test('nothing while recovery is calibrating or history is short', () {
    expect(
      recoveryForecast(today: history.last, history: const [], sleepHours: 8),
      isNull,
    );
    expect(
      recoveryForecast(
        today: today,
        history: past.take(3).toList(),
        sleepHours: 8,
      ),
      isNull,
    );
  });
}
