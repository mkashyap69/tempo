import 'package:backtest/calibrate.dart';
import 'package:test/test.dart';

void main() {
  final d0 = DateTime(2024, 1, 1);
  Map<DateTime, double> days(List<double> ts) => {
    for (final (i, t) in ts.indexed) d0.add(Duration(days: i)): t,
  };

  test('needs 30 days', () {
    expect(calibrate(days(List.filled(29, 50))), isNull);
  });

  test('puts the 99th-percentile day at 18.5', () {
    // 100 days: TRIMP 1..100.
    final c = calibrate(days([for (var i = 1; i <= 100; i++) i * 1.0]))!;
    expect(c.days, 100);
    expect(c.strainAt(99.01), closeTo(calibrationStrain, 1e-6));
    expect(c.p50, closeTo(50.5, 1e-9));
    expect(c.top.first.$2, 100);
    expect(c.top.first.$1, d0.add(const Duration(days: 99)));
    expect(c.top.length, 10);
  });

  test('no load at the top gives nothing to calibrate', () {
    expect(calibrate(days(List.filled(40, 0))), isNull);
  });
}
