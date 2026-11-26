import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

RecoveryShare _part(String key, double push) =>
    RecoveryShare(key: key, value: 0, normal: 0, z: push, push: push);

double _curve(double s) => 100 / (1 + exp(-1.5 * s));

void main() {
  test('one part: its points are the whole distance from 50', () {
    final pts = recoveryPoints([_part('hrv', -.4)]);
    expect(pts['hrv'], closeTo(_curve(-.4) - 50, 1e-9));
    expect(pts['hrv'], lessThan(0));
  });

  test('a part at normal moves nothing', () {
    final pts = recoveryPoints([_part('hrv', .3), _part('rhr', 0)]);
    expect(pts['rhr'], 0);
  });

  test('signs follow the push; points are marginal, not additive', () {
    final parts = [_part('hrv', .6), _part('rhr', -.2), _part('sleep', .3)];
    final pts = recoveryPoints(parts);
    expect(pts['hrv'], greaterThan(0));
    expect(pts['rhr'], lessThan(0));
    final score = _curve(.7);
    expect(pts['hrv'], closeTo(score - _curve(.1), 1e-9));
    // Near the middle of the curve the sum is close to score − 50.
    final sum = pts.values.reduce((a, b) => a + b);
    expect(sum, closeTo(score - 50, 3));
  });

  test('no parts: no points', () {
    expect(recoveryPoints(const []), isEmpty);
  });
}
