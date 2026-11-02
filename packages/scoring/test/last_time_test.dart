import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// V4: what the night after a behaviour looked like, from the first time.
void main() {
  ImpactDay day(
    int i, {
    bool alcohol = false,
    double rhr = 48,
    double rec = 55,
    double slept = 8,
  }) => ImpactDay(
    date: DateTime(2026, 10, 1).add(Duration(days: i)),
    x: {'alcohol': alcohol ? 1 : 0},
    y: {Outcome.rhr: rhr, Outcome.recovery: rec, Outcome.sleptHours: slept},
  );

  // Owner-like: three alcohol nights, RHR 62/63/58.6 against ~48.
  final days = [
    for (var i = 0; i < 20; i++) day(i, rhr: 47 + i % 3),
    day(20, alcohol: true, rhr: 62, rec: 19, slept: 8.1),
    day(21, alcohol: true, rhr: 63, rec: 2, slept: 4.8),
    day(22, alcohol: true, rhr: 58.6, rec: 7, slept: 7.3),
  ];

  test('one before-and-after per behaviour, against other days', () {
    final l = lastTime(days, 'alcohol')!;
    expect(l.n, 3);
    expect(l.rhr, closeTo((62 + 63 + 58.6) / 3 - 48, 1e-9));
    expect(l.recovery, closeTo((19 + 2 + 7) / 3 - 55, 1e-9));
    expect(l.notable, isTrue);
    expect(
      lastTimeLine(l, 'Alcohol'),
      'The 3 nights after alcohol: resting HR 13 bpm higher, recovery 46 '
      'points lower and sleep 1 h 16 m less than your other days.',
    );
  });

  test('works from the first time', () {
    final l = lastTime(days.sublist(0, 21), 'alcohol')!;
    expect(l.n, 1);
    expect(lastTimeLine(l, 'Alcohol'), startsWith('The night after alcohol:'));
  });

  test('needs a normal to compare with, and a tagged day', () {
    expect(lastTime(days.sublist(18), 'alcohol'), isNull);
    expect(lastTime(days.sublist(0, 20), 'alcohol'), isNull);
  });

  test('small changes are not notable', () {
    final calm = [
      for (var i = 0; i < 10; i++) day(i),
      day(10, alcohol: true, rhr: 49, rec: 50),
    ];
    expect(lastTime(calm, 'alcohol')!.notable, isFalse);
  });
}
