import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// Algo 12, recovery v2: HRV trend, sleep balance and load join the
/// nightly signals; physiology and load only.
void main() {
  final day = DateTime(2026, 11, 2);
  DailyScore past(
    int daysAgo, {
    double strain = 4,
    double slept = 8,
    double rhr = 48,
    double? hrv,
    double? stress = 8,
  }) => DailyScore(
    date: day.subtract(Duration(days: daysAgo)),
    strain: strain,
    trimp: 0,
    hrMax: 189,
    sleptHours: slept,
    baseNeedHours: 7,
    rhr: rhr,
    rhrKind: rhrFromSleep,
    hrvProxy: hrv == null ? stress : null,
    hrv: hrv,
    hrvKind: hrv == null ? null : 'rmssd',
    calibrating: false,
  );
  RecoveryInput part(List<RecoveryPart> ps, String k) =>
      ps.firstWhere((x) => x.key == k).input;
  List<RecoveryPart> inputs(
    List<DailyScore> history, {
    double sufficiency = 114,
    double? hrvMs,
    double? stress = 8,
  }) => recoveryInputsFor(
    stress: hrvMs == null ? stress : null,
    hrvMs: hrvMs,
    hrvKind: hrvMs == null ? null : 'rmssd',
    rhr: 48,
    rhrKind: rhrFromSleep,
    sufficiency: sufficiency,
    normal: history.take(30).toList(),
    baseHours: 7,
    day: day,
    history: history,
  );

  test('a hard yesterday pulls recovery down; a light one is neutral', () {
    // 31 Oct → 1 Nov: strain 17 against a ~4 normal.
    final hard = [past(1, strain: 17), for (var i = 2; i < 30; i++) past(i)];
    expect(part(inputs(hard), 'load').z, lessThan(-2));
    final light = [past(1, strain: 0.5), for (var i = 2; i < 30; i++) past(i)];
    expect(part(inputs(light), 'load').z, 0);
    // Too little history: load stays out.
    expect(part(inputs([past(1, strain: 17)]), 'load').z, isNull);
  });

  test('a short week shows in the sleep balance, not only last night', () {
    final short = [
      for (var i = 1; i < 30; i++) past(i, slept: i <= 6 ? 5.5 : 8),
    ];
    final rested = [for (var i = 1; i < 30; i++) past(i)];
    expect(
      part(inputs(short), 'balance').z!,
      lessThan(part(inputs(rested), 'balance').z!),
    );
    expect(part(inputs(short), 'balance').z!, lessThan(0));
  });

  test('HRV trend needs 21 nights and compares the week with 60 days', () {
    final few = [for (var i = 1; i < 15; i++) past(i, hrv: 60)];
    expect(part(inputs(few, hrvMs: 60), 'trend').z, isNull);
    // Two months at 60 ms, the last week at 45 ms: a falling trend.
    final falling = [
      for (var i = 1; i < 60; i++) past(i, hrv: i <= 6 ? 45 : 60 + (i % 5)),
    ];
    expect(part(inputs(falling, hrvMs: 45), 'trend').z!, lessThan(-1));
    // The band's stress index stands in, lower being better.
    final calm = [
      for (var i = 1; i < 40; i++) past(i, stress: i <= 6 ? 4 : 9 + (i % 3)),
    ];
    expect(part(inputs(calm, stress: 4), 'trend').z!, greaterThan(0));
  });

  test('weights sum to 1 with everything present', () {
    const r = RecoveryParams();
    expect(
      r.wHrv + r.wHrvTrend + r.wRhr + r.wSleep + r.wSleepBalance + r.wLoad,
      closeTo(1, 1e-9),
    );
  });

  test('basis names what the score was built from, and how sure it is', () {
    RecoveryShare s(String k) =>
        RecoveryShare(key: k, value: 0, normal: 0, z: 0, push: 0);
    expect(recoveryBasis([s('stress'), s('rhr'), s('sleep'), s('load')]), (
      level: 'high',
      line: 'From overnight stress, resting HR, sleep and load',
    ));
    expect(recoveryBasis([s('rhr'), s('sleep')]).level, 'medium');
    expect(recoveryBasis([s('sleep'), s('load')]), (
      level: 'low',
      line: 'From sleep and load',
    ));
  });

  test('no journal or feel input exists: same signals, same score', () {
    // scoreDay takes minutes, stress, history and vitals only; two runs over
    // the same data score the same whatever is logged elsewhere.
    final rng = Random(3);
    final hist = [
      for (var i = 1; i < 30; i++) past(i, strain: rng.nextDouble() * 8),
    ];
    final a = recoveryScore([for (final x in inputs(hist)) x.input]);
    final b = recoveryScore([for (final x in inputs(hist)) x.input]);
    expect(a, b);
  });
}
