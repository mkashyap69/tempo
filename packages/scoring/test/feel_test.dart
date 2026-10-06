import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('feel bands map to recovery colours', () {
    expect(
      [for (var f = 1; f <= 5; f++) feelColor(f)],
      [
        RecoveryColor.red,
        RecoveryColor.red,
        RecoveryColor.yellow,
        RecoveryColor.green,
        RecoveryColor.green,
      ],
    );
  });

  group('spearman', () {
    test('perfect, reversed and too short', () {
      expect(spearman([1, 2, 3, 4], [10, 20, 30, 40]), closeTo(1, 1e-9));
      expect(spearman([1, 2, 3, 4], [4, 3, 2, 1]), closeTo(-1, 1e-9));
      expect(spearman([1, 2], [1, 2]), isNull);
    });
    test('ties take their average rank', () {
      // Ranks x: 1, 2.5, 2.5, 4; y: 1, 2, 3, 4.
      expect(spearman([1, 5, 5, 9], [1, 2, 3, 4]), closeTo(.9487, 1e-4));
    });
    test('a constant side has no correlation', () {
      expect(spearman([1, 2, 3], [3, 3, 3]), isNull);
    });
  });

  group('compareFeel', () {
    List<(double, int)> days(int n, (double, int) Function(int) f) => [
      for (var i = 0; i < n; i++) f(i),
    ];

    test('learning under 14 rated mornings', () {
      final c = compareFeel(days(13, (i) => (20.0 + i * 5, 1 + i % 5)));
      expect(c.fit, FeelFit.learning);
      expect(c.n, 13);
    });

    test('recovery that follows feel tracks', () {
      // Feel 1..5 cycling; recovery sits in the matching colour.
      const rec = [20.0, 30.0, 50.0, 75.0, 90.0];
      final c = compareFeel(days(15, (i) => (rec[i % 5] + i * .1, 1 + i % 5)));
      expect(c.fit, FeelFit.tracks);
      expect(c.agree, 15);
      expect(c.rho, greaterThan(.9));
      expect((c.recoveryHigh, c.recoveryLow), (0, 0));
    });

    test('recovery that runs against feel is off and counts the misses', () {
      const rec = [90.0, 80.0, 50.0, 30.0, 20.0];
      final c = compareFeel(days(15, (i) => (rec[i % 5] + i * .1, 1 + i % 5)));
      expect(c.fit, FeelFit.off);
      expect(c.recoveryHigh, 6); // green on feel 1–2
      expect(c.recoveryLow, 6); // red on feel 4–5
    });

    test('you always feel the same: still learning', () {
      final c = compareFeel(days(20, (i) => (30.0 + i * 3, 3)));
      expect(c.rho, isNull);
      expect(c.fit, FeelFit.learning);
    });
  });
}
