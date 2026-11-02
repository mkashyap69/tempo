import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// V5: Today's "why" rebuilds the score's own inputs.
void main() {
  // 24 simulated nights: sleep and sleeping HR wobble, scored in order.
  final d0 = DateTime(2026, 1, 1);
  final minutes = <Minute>[];
  final rng = Random(7);
  final nights = [
    for (var i = 0; i < 25; i++)
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

  test('the parts add up to the stored recovery', () {
    var checked = 0;
    for (var i = 0; i < history.length - 1; i++) {
      final today = history[i];
      if (today.recovery == null) continue;
      final parts = recoveryBreakdown(today, history.sublist(i + 1));
      final push = parts.fold<double>(0, (a, x) => a + x.push);
      expect(
        100 / (1 + exp(-1.5 * push)),
        closeTo(today.recovery!, 1e-6),
        reason: today.date.toString(),
      );
      checked++;
    }
    expect(checked, greaterThan(5));
  });

  test('each part says its value, your normal and which way it pushed', () {
    final today = history.first;
    final parts = recoveryBreakdown(today, history.sublist(1));
    final rhr = parts.firstWhere((x) => x.key == 'rhr');
    expect(rhr.value, today.rhr);
    expect(rhr.push.sign, -(rhr.value - rhr.normal).sign);
    expect(parts.map((x) => x.key), containsAll(['rhr', 'sleep']));
  });

  test('recoveryWhyLine names what helped and what held it back', () {
    RecoveryShare x(String k, double push) =>
        RecoveryShare(key: k, value: 0, normal: 0, z: push * 3, push: push);
    // 2 Nov: sleep long, resting HR +1, stress a little up.
    expect(
      recoveryWhyLine([x('stress', -.13), x('rhr', -.16), x('sleep', .2)]),
      'Sleep helped · resting HR and overnight stress held it back',
    );
    expect(
      recoveryWhyLine([x('rhr', -.9), x('sleep', .3)]),
      'Resting HR held it back · sleep helped',
    );
    expect(recoveryWhyLine([x('rhr', .05)]), isNull);
    expect(recoveryWhyLine(const []), isNull);
  });
}
