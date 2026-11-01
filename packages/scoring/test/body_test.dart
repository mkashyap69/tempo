import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 11, 1);
  DateTime ago(int d, [int h = 7]) =>
      DateTime(today.year, today.month, today.day - d, h);

  group('weight', () {
    test('the day keeps its last reading', () {
      final d = dailyWeights([
        (ago(1, 7), 80.0),
        (ago(1, 21), 81.0),
        (ago(0), 79.5),
      ]);
      expect([for (final x in d) x.kg], [81.0, 79.5]);
    });

    test('weekly mean against four weeks ago', () {
      final d = dailyWeights([
        for (var i = 28; i <= 34; i++) (ago(i), 82.0),
        for (var i = 0; i <= 6; i += 2) (ago(i), 80.0),
      ]);
      final w = weightTrend(d, today)!;
      expect(w.weekMean, 80);
      expect(w.readings, 4);
      expect(w.change4w, -2);
      expect(w.word, 'Going down');
    });

    test('steady inside 0.3 kg, no history, nothing this week', () {
      final steady = weightTrend(
        dailyWeights([(ago(30), 80.0), (ago(1), 80.2)]),
        today,
      )!;
      expect(steady.word, 'Steady');
      expect(
        weightTrend(dailyWeights([(ago(1), 80.0)]), today)!.word,
        'Not enough history yet',
      );
      expect(weightTrend(dailyWeights([(ago(10), 80.0)]), today), isNull);
    });
  });

  group('cycle', () {
    FlowDay f(int d, double flow, {bool start = false}) =>
        (day: ago(d, 0), flow: flow, start: start);

    test('day 1 is the first flow day after a gap; typical length', () {
      final flow = [
        for (final s in [84, 56, 28, 3])
          for (var i = 0; i < 4; i++) f(s - i, 2),
      ];
      final c = cycleAt(flow, today)!;
      expect(c.start, ago(3, 0));
      expect(c.day, 4);
      expect(c.typicalLength, 28);
      expect(c.late, isFalse);
    });

    test('late in a typical cycle', () {
      final flow = [
        for (final s in [80, 52, 24])
          for (var i = 0; i < 3; i++) f(s - i, 1),
      ];
      final c = cycleAt(flow, today)!;
      expect(c.day, 25);
      expect(c.typicalLength, 28);
      expect(c.late, isTrue);
    });

    test('spotting alone starts nothing; old or no data is null', () {
      expect(cycleAt([f(2, .5)], today), isNull);
      expect(cycleAt([f(70, 2)], today), isNull);
      expect(cycleAt(const [], today), isNull);
      expect(cycleAt([f(5, .5, start: true)], today)!.day, 6);
    });
  });
}
