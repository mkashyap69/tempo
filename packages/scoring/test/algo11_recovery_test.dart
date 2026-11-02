import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// Algo 11 recovery: a smallest spread per input and a cap on each z.
void main() {
  // The owner's resting-HR baseline on 2 Nov 2026: median 48, MAD 1.48.
  const rhrBase = Baseline(48, 1.48, 20);

  RecoveryInput rhr(double v, {double minSd = 0}) => RecoveryInput(
    value: v,
    baseline: rhrBase,
    higherIsBetter: false,
    weight: .3,
    minSd: minSd,
  );

  test('1 bpm over normal is a small step, not a big one', () {
    expect(rhr(49).z, closeTo(-1 / 1.48, 1e-9));
    expect(rhr(49, minSd: 2.5).z, closeTo(-0.4, 1e-9));
    // A wider real spread is kept.
    expect(
      const RecoveryInput(
        value: 52,
        baseline: Baseline(48, 4, 20),
        higherIsBetter: false,
        weight: .3,
        minSd: 2.5,
      ).z,
      closeTo(-1, 1e-9),
    );
  });

  test('a zero spread no longer drops the input once floored', () {
    const flat = Baseline(120, 0, 10);
    const i = RecoveryInput(
      value: 100,
      baseline: flat,
      higherIsBetter: true,
      weight: .3,
      minSd: 10,
    );
    expect(i.z, closeTo(-2, 1e-9));
  });

  test('one input far off cannot pin recovery to 0 alone', () {
    // 10 Oct: resting HR 62 against 48 (z −18 before algo 11).
    final inputs = [
      rhr(62, minSd: recoveryMinSd.rhr),
      const RecoveryInput(
        value: 110,
        baseline: Baseline(102, 26, 20),
        higherIsBetter: true,
        weight: .3,
      ),
    ];
    final capped = recoveryScore(inputs)!;
    final uncapped = recoveryScore(
      inputs,
      const RecoveryParams(zCap: double.infinity),
    )!;
    expect(uncapped, lessThan(5));
    expect(capped, greaterThan(10));
    expect(capped, lessThan(34)); // still red
  });

  test('the cap is ±2.5 by default and symmetric', () {
    final hi = recoveryScore([rhr(30, minSd: 2.5)])!;
    final lo = recoveryScore([rhr(66, minSd: 2.5)])!;
    expect(hi + lo, closeTo(100, 1e-9));
    expect(hi, closeTo(100 / (1 + exp(-1.5 * 2.5)), 1e-9));
  });
}
