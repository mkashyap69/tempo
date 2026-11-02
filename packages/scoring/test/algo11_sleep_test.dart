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

/// Algo 11 night selection and doze trimming, shaped on the owner's
/// 19–20 Oct and 1–2 Nov 2026 band nights.
void main() {
  final day = DateTime(2026, 11, 2);
  DateTime at(int dayOffset, int h, int m) =>
      day.add(Duration(days: dayOffset, hours: h, minutes: m));

  group('doze before the night', () {
    // 22:08–22:44 doze, 66 min awake with 23 steps, night 23:50–09:15.
    final minutes = [
      ...run(at(-1, 20, 0), 128, Stage.wake, steps: 30),
      ...run(at(-1, 22, 8), 37, Stage.light),
      ...run(at(-1, 22, 45), 65, Stage.wake),
      ...run(at(-1, 23, 50), 1, Stage.wake, steps: 23),
      ...run(at(-1, 23, 51), 564, Stage.light),
      ...run(at(0, 9, 15), 120, Stage.wake, steps: 30),
    ];

    test('splits off: the night starts after the long wake', () {
      final s = daySleep(date: day, minutes: minutes);
      expect(s.night!.start, at(-1, 23, 51));
      expect(s.night!.minutes.where((m) => m.stage == Stage.wake), isEmpty);
    });

    test('a doze in pieces (a short wake inside it) splits off whole', () {
      // As staged on 2 Nov: 22:08–22:38, 3 min awake, 22:41–22:45.
      final m = [
        ...run(at(-1, 22, 8), 30, Stage.light),
        ...run(at(-1, 22, 38), 3, Stage.wake, steps: 11),
        ...run(at(-1, 22, 41), 4, Stage.light),
        ...run(at(-1, 22, 45), 65, Stage.wake),
        ...run(at(-1, 23, 50), 500, Stage.light),
      ];
      final s = detectSessions(m, const SleepParams(minSessionMinutes: 20));
      expect(s.map((x) => (x.start, x.end)), [
        (at(-1, 22, 8), at(-1, 22, 45)),
        (at(-1, 23, 50), at(0, 8, 10)),
      ]);
    });

    test('stays its own sleep', () {
      final all = detectSessions(
        minutes,
        const SleepParams(minSessionMinutes: 20),
      );
      expect(all.map((s) => s.start), [at(-1, 22, 8), at(-1, 23, 51)]);
    });

    test('a long first stretch still joins across a quiet wake', () {
      final long = [
        ...run(at(-1, 22, 8), 60, Stage.light),
        ...run(at(-1, 23, 8), 50, Stage.wake),
        ...run(at(-1, 23, 58), 500, Stage.light),
      ];
      final s = detectSessions(long);
      expect(s.single.start, at(-1, 22, 8));
    });

    test('a doze joined by a short wake (≤ 30 min) stays in', () {
      final near = [
        ...run(at(-1, 23, 48), 21, Stage.light),
        ...run(at(0, 0, 9), 28, Stage.wake),
        ...run(at(0, 0, 37), 500, Stage.light),
      ];
      expect(detectSessions(near).single.start, at(-1, 23, 48));
    });

    test('a short lie-in after a long quiet wake splits off too', () {
      final m = [
        ...run(at(-1, 23, 51), 500, Stage.light),
        ...run(at(0, 8, 11), 60, Stage.wake),
        ...run(at(0, 9, 11), 30, Stage.light),
      ];
      final s = detectSessions(m, const SleepParams(minSessionMinutes: 20));
      expect(s.length, 2);
      expect(s.first.end, at(0, 8, 11));
    });
  });

  group('the night is a night', () {
    // Band off from 17:01 on 19 Oct to 14:30 on 20 Oct, after a nap.
    final d20 = DateTime(2026, 10, 20);
    DateTime t(int dayOffset, int h, int m) =>
        d20.add(Duration(days: dayOffset, hours: h, minutes: m));
    final minutes = [
      ...run(t(-1, 14, 0), 101, Stage.wake, steps: 20),
      ...run(t(-1, 15, 41), 80, Stage.light),
      ...run(t(-1, 17, 1), 1289, Stage.unknown),
      ...run(t(0, 14, 30), 60, Stage.wake, steps: 20),
    ];

    test('an afternoon nap the day before is not the night', () {
      expect(daySleep(date: d20, minutes: minutes).night, isNull);
    });

    test('no night: no sleep score and no recovery', () {
      final d = scoreDay(date: d20, minutes: minutes);
      expect(d.sleptHours, isNull);
      expect(d.sleepScore, isNull);
      expect(d.recovery, isNull);
    });

    test('a short sleep in the small hours still counts', () {
      final m = [
        ...run(t(-1, 23, 0), 72, Stage.wake, steps: 20),
        ...run(t(0, 0, 12), 75, Stage.light),
        ...run(t(0, 1, 27), 60, Stage.wake, steps: 20),
      ];
      expect(daySleep(date: d20, minutes: m).night!.start, t(0, 0, 12));
    });

    test('a 3 h+ daytime sleep counts (shift work)', () {
      final m = [
        ...run(t(-1, 15, 0), 200, Stage.light),
        ...run(t(-1, 18, 20), 60, Stage.wake, steps: 20),
      ];
      expect(daySleep(date: d20, minutes: m).night, isNotNull);
    });
  });
}
