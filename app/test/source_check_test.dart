import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:tempo/src/core/source_check.dart';

void main() {
  final d0 = DateTime(2026, 11, 1, 7);
  DateTime day(int i) => d0.subtract(Duration(days: i));

  test('a watch with everything: all good, counted in days and nights', () {
    final c = summarise([
      for (var i = 0; i < 20; i++) ...[
        (HealthKind.heartRate, day(i), 'com.apple.health.ABC'),
        (HealthKind.sleepDeep, day(i), 'com.apple.health.ABC'),
        (HealthKind.hrvSdnn, day(i), 'com.apple.health.ABC'),
        (HealthKind.steps, day(i), 'com.apple.health.ABC'),
      ],
      (HealthKind.workout, day(2), 'com.apple.health.ABC'),
      (HealthKind.spo2, day(1), 'com.apple.health.ABC'),
    ]);
    expect(c.lines.every((l) => l.state == CheckState.good), isTrue);
    expect(c.lines[1].title, 'Sleep with stages');
    expect(c.lines[1].amount, '20 nights');
    expect(c.lines[3].amount, '1 workout');
    expect(c.sleepApps, isEmpty);
  });

  test('sleep without stages is partial; two sleep apps are named', () {
    final c = summarise([
      for (var i = 0; i < 10; i++)
        (
          HealthKind.sleepAsleep,
          day(i),
          i.isEven ? 'com.xiaomi.wearable' : 'com.northcube.sleepcycle',
        ),
    ]);
    final sleep = c.lines[1];
    expect(sleep.title, 'Sleep');
    expect(sleep.state, CheckState.partial);
    expect(c.sleepApps.toSet(), {'Mi Fitness', 'Sleep Cycle'});
    expect(c.lines.first.state, CheckState.missing);
  });

  test('nothing read: missing lines and nothing found', () {
    final c = summarise(const []);
    expect(c.anything, isFalse);
    expect(c.lines.first.amount, 'Nothing yet');
  });
}
