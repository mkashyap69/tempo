import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('Benjamini–Hochberg', () {
    test('textbook example', () {
      // m = 5, q = .05: thresholds .01 .02 .03 .04 .05.
      expect(benjaminiHochberg([.001, .008, .039, .041, .042], .05), [
        true,
        true,
        true,
        true,
        true,
      ]);
      expect(benjaminiHochberg([.001, .03, .2, .5, .9], .05), [
        true,
        false,
        false,
        false,
        false,
      ]);
      expect(benjaminiHochberg([], .05), isEmpty);
    });
  });

  test('block sample keeps runs of consecutive days', () {
    final rows = [for (var i = 0; i < 30; i++) i];
    final s = blockSample(rows, Random(1));
    expect(s.length, 30);
    // Within each block of 7, days follow on (circularly).
    for (var b = 0; b + 7 <= 28; b += 7) {
      for (var k = 1; k < 7; k++) {
        expect(s[b + k], (s[b + k - 1] + 1) % 30);
      }
    }
  });

  test('pure noise: under 5 % of behaviours shown (shuffled-label gate)', () {
    // Ten behaviours with no effect on an autocorrelated outcome, 20 users.
    var shown = 0, judged = 0;
    for (var seed = 0; seed < 20; seed++) {
      final r = Random(100 + seed);
      final d0 = DateTime(2026, 1, 1);
      var level = 60.0;
      final days = <ImpactDay>[];
      for (var i = 0; i < 90; i++) {
        // A slow wander plus noise: recovery is autocorrelated.
        level = 60 + .8 * (level - 60) + (r.nextDouble() - .5) * 16;
        days.add(
          ImpactDay(
            date: d0.add(Duration(days: i)),
            x: {
              for (var b = 0; b < 10; b++) 'b$b': r.nextDouble() < .3 ? 1 : 0,
            },
            y: {Outcome.recovery: level},
            strain: 8 + r.nextDouble() * 6,
          ),
        );
      }
      final res = impacts(days, [
        for (var b = 0; b < 10; b++) Behaviour('b$b'),
      ], Outcome.recovery);
      for (final i in res) {
        if (i.confidence == ImpactConfidence.notEnough) continue;
        judged++;
        if (i.shown) shown++;
      }
    }
    expect(judged, greaterThan(150));
    expect(shown / judged, lessThan(.05));
  });
}
