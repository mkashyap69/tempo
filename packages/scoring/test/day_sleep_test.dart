import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> run(DateTime from, int n, Stage stage, {int steps = 0}) => [
  for (var i = 0; i < n; i++)
    Minute(
      from.add(Duration(minutes: i)),
      stage: stage,
      steps: steps,
    ),
];

void main() {
  final day = DateTime(2026, 10, 6);
  DateTime at(int h, int m) => day.add(Duration(hours: h, minutes: m));

  // Night 00:07–08:18, up and about, a 46-min nap at 15:40, a 10-min doze.
  final minutes = [
    ...run(at(0, 7), 491, Stage.light),
    ...run(at(8, 18), 442, Stage.wake, steps: 20),
    ...run(at(15, 40), 46, Stage.light),
    ...run(at(16, 26), 60, Stage.wake, steps: 20),
    ...run(at(17, 26), 10, Stage.light),
    ...run(at(17, 36), 60, Stage.wake, steps: 20),
  ];

  group('daySleep', () {
    test('finds the night and lists each nap', () {
      final s = daySleep(date: day, minutes: minutes);
      expect(s.night!.start, at(0, 7));
      expect(s.wake, at(8, 18));
      expect(s.naps.length, 1);
      expect(s.naps.single.start, at(15, 40));
      expect(s.naps.single.asleep.inMinutes, 46);
    });
    test('scoreDay napHours is the sum of the naps', () {
      final d = scoreDay(date: day, minutes: minutes);
      expect(d.napHours, closeTo(46 / 60, 1e-9));
      expect(d.sleepEnd, at(8, 18));
    });
  });

  group('splitStress', () {
    final sleeps = [
      SleepSession(run(at(0, 7), 491, Stage.light)),
      SleepSession(run(at(15, 40), 46, Stage.light)),
    ];
    final readings = [
      StressReading(at(3, 0), 4), // asleep: sleep scale
      StressReading(at(9, 0), 0), // no reading
      StressReading(at(9, 5), 255), // no reading
      StressReading(at(11, 14), 21),
      StressReading(at(11, 19), 29),
      StressReading(at(14, 9), 58),
      StressReading(at(14, 19), 62),
      StressReading(at(15, 44), 16), // nap: sleep scale
    ];
    final s = splitStress(readings, sleeps);
    test('keeps sleep readings out of the awake average', () {
      expect(s.asleep.map((r) => r.value), [4, 16]);
      expect(s.awakeAvg, closeTo((21 + 29 + 58 + 62) / 4, 1e-9));
    });
    test('levels count 5 measured minutes per reading', () {
      expect(s.calmMinutes, 10);
      expect(s.mediumMinutes, 5);
      expect(s.highMinutes, 5);
    });
    test('busiest hour needs two readings', () {
      expect(s.busiestHour, 14);
    });
  });
}
