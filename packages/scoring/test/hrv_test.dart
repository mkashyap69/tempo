import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('alternating ±20 ms around 1000 ms → RMSSD 40', () {
    final rr = [for (var i = 0; i < 60; i++) i.isEven ? 1000 : 1040];
    expect(rmssd(rr), closeTo(40, 1e-9));
  });
  test('steady rhythm → 0', () {
    expect(rmssd(List.filled(40, 900)), 0);
  });
  test('artifacts are dropped: out of range and >20 % jumps', () {
    final rr = [for (var i = 0; i < 60; i++) i.isEven ? 1000 : 1040]
      ..insertAll(10, [200, 2500, 1600]);
    expect(rmssd(rr), closeTo(40, 1e-9));
  });
  test('too few beats → null', () {
    expect(rmssd(List.filled(10, 1000)), isNull);
  });
  test('matches the textbook formula on a random series', () {
    final r = Random(3);
    final rr = [for (var i = 0; i < 100; i++) 950 + r.nextInt(60)];
    var s = 0.0;
    for (var i = 1; i < rr.length; i++) {
      s += pow(rr[i] - rr[i - 1], 2);
    }
    expect(rmssd(rr), closeTo(sqrt(s / (rr.length - 1)), 1e-9));
  });
}
