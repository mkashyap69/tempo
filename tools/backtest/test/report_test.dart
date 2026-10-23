import 'dart:math';

import 'package:backtest/report.dart';
import 'package:scoring/scoring.dart' show RecoveryColor;
import 'package:test/test.dart';

void main() {
  final dates = [
    for (var i = 1; i <= 20; i++) '2026-01-${'$i'.padLeft(2, '0')}',
  ];

  test('spread percentiles', () {
    final s = spread([for (var i = 0; i <= 100; i++) i.toDouble(), null])!;
    expect((s.n, s.p10, s.p50, s.p90), (101, 10, 50, 90));
    expect(spread([null]), isNull);
  });

  test('noise: typical error = SD of diffs / √2, MDC95 = 1.96 · SD', () {
    final s = {for (var i = 0; i < 20; i++) dates[i]: i.isEven ? 50.0 : 54.0};
    final n = noise(dates, s)!;
    expect(n.pairs, 19);
    // Diffs alternate +4 / −4 (ten up, nine down): sample SD of those.
    final d = [for (var i = 1; i < 20; i++) i.isOdd ? 4.0 : -4.0];
    final m = d.reduce((a, b) => a + b) / d.length;
    final sd = sqrt(
      d.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / (d.length - 1),
    );
    expect(n.typicalError, closeTo(sd / sqrt2, 1e-9));
    expect(n.mdc95, closeTo(1.96 * sd, 1e-9));
    expect(noise(dates.take(5).toList(), s), isNull);
  });

  test('colours, shift and colour changes', () {
    final before = {'a': 70.0, 'b': 50.0, 'c': 20.0, 'd': null};
    final now = {'a': 60.0, 'b': 52.0, 'c': 40.0, 'd': 80.0};
    expect(colours(now.values)[RecoveryColor.yellow], closeTo(.75, 1e-9));
    final sh = shift(before, now)!;
    expect(sh.n, 3);
    expect(sh.meanDelta, closeTo((-10 + 2 + 20) / 3, 1e-9));
    expect(sh.meanAbsDelta, closeTo(32 / 3, 1e-9));
    expect(colourChanges(before, now), 2); // a green→yellow, c red→yellow
  });

  test('Bland–Altman agreement', () {
    final ref = {'a': 80.0, 'b': 70.0, 'c': 60.0, 'd': 90.0};
    final ours = {'a': 85.0, 'b': 74.0, 'c': 66.0, 'd': 95.0, 'e': 50.0};
    final a = agreement(ref, ours)!;
    expect(a.n, 4);
    expect(a.bias, closeTo(5, 1e-9));
    expect(a.loaLow, lessThan(5));
    expect(a.loaHigh, greaterThan(5));
  });

  test('reads a CSV by header, blanks as null', () {
    final m = readCsv([
      'date,strain,recovery',
      '2026-01-01,10.5,',
      '2026-01-02,3,67',
    ]);
    expect(m['strain'], {'2026-01-01': 10.5, '2026-01-02': 3});
    expect(m['recovery']!['2026-01-01'], isNull);
    expect(() => readCsv(['strain']), throwsFormatException);
  });

  test('report text has every part', () {
    final s = {for (var i = 0; i < 20; i++) dates[i]: 60.0 + i % 5};
    final r = report(
      dates: dates,
      now: {'recovery': s, 'sleep_score': s},
      before: {
        'recovery': {for (final d in dates) d: 70.0},
      },
      reference: {for (final d in dates) d: 58.0},
    );
    expect(r, contains('recovery'));
    expect(r, contains('Recovery colours'));
    expect(r, contains('colour changed on 20 days'));
    expect(r, contains('bias 4.0'));
  });
}
