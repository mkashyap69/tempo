import 'dart:math';

import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> run(
  DateTime from,
  int n, {
  int? hr,
  Stage stage = Stage.wake,
  bool inBed = false,
}) => [
  for (var i = 0; i < n; i++)
    Minute(
      from.add(Duration(minutes: i)),
      hr: hr,
      stage: stage,
      inBed: inBed,
    ),
];

void main() {
  final day = DateTime(2026, 3, 2);
  final bed = DateTime(2026, 3, 1, 22, 30);

  group('time in bed', () {
    test('efficiency and latency from the source\'s in-bed minutes', () {
      // In bed 22:30, asleep 23:00–07:00 with 20 min awake at 03:00.
      final m = [
        ...run(bed.subtract(const Duration(hours: 2)), 120, hr: 70),
        ...run(bed, 30, hr: 65, inBed: true),
        ...run(
          bed.add(const Duration(minutes: 30)),
          240,
          hr: 52,
          stage: Stage.light,
          inBed: true,
        ),
        ...run(bed.add(const Duration(minutes: 270)), 20, hr: 60, inBed: true),
        ...run(
          bed.add(const Duration(minutes: 290)),
          220,
          hr: 52,
          stage: Stage.light,
          inBed: true,
        ),
        ...run(bed.add(const Duration(minutes: 510)), 600, hr: 70),
      ];
      final s = scoreDay(date: day, minutes: m);
      expect(s.latencyMinutes, 30);
      expect(s.bedEfficiency, closeTo(460 / 510, 1e-9));
    });

    test('no in-bed time (the band): efficiency and latency unknown', () {
      final m = [
        ...run(bed, 480, hr: 52, stage: Stage.light),
        ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
      ];
      final s = scoreDay(date: day, minutes: m);
      expect(s.bedEfficiency, isNull);
      expect(s.latencyMinutes, isNull);
      // The score is sufficiency and continuity only, not a flat 99 %.
      expect(s.sleepScore, closeTo(100, 1e-9));
    });

    test('bedSpan is null when in-bed time is just the asleep span', () {
      final m = run(bed, 120, hr: 52, stage: Stage.light, inBed: true);
      expect(bedSpan(SleepSession(m), m), isNull);
    });
  });

  group('resting HR kind', () {
    final minutes = [
      ...run(bed, 480, hr: 52, stage: Stage.light),
      ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
    ];
    test('from the night when it has HR, else the source, tagged', () {
      final a = scoreDay(date: day, minutes: minutes, sourceRhr: 60);
      expect(a.rhr, 52);
      expect(a.rhrKind, rhrFromSleep);
      final noHr = [
        ...run(bed, 480, stage: Stage.light),
        ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
      ];
      final b = scoreDay(date: day, minutes: noHr, sourceRhr: 60);
      expect(b.rhr, 60);
      expect(b.rhrKind, rhrFromSource);
    });

    test('a source resting HR is never judged against sleep ones', () {
      final hist = [
        for (var i = 1; i <= 20; i++)
          DailyScore(
            date: day.subtract(Duration(days: i)),
            strain: 0,
            trimp: 0,
            hrMax: 190,
            sleptHours: 7.5 + (i % 3) / 4,
            rhr: 50 + (i % 3).toDouble(),
            rhrKind: rhrFromSleep,
          ),
      ];
      final noHr = [
        ...run(bed, 480, stage: Stage.light),
        ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
      ];
      // A daytime 60 against sleeping ~51 would read as a terrible night;
      // with no baseline of its kind, recovery leaves resting HR out, the
      // same as when there is none.
      double? rec(double? src) => scoreDay(
        date: day,
        minutes: noHr,
        history: hist,
        sourceRhr: src,
      ).recovery;
      expect(rec(60), isNotNull);
      expect(rec(60), rec(null));
    });
  });

  group('recovery baselines', () {
    final minutes = [
      ...run(bed, 480, hr: 52, stage: Stage.light),
      ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
    ];
    DailyScore past(int i, {double? hrv, double penalty = 0, double rhr = 0}) =>
        DailyScore(
          date: day.subtract(Duration(days: i)),
          strain: 0,
          trimp: 0,
          hrMax: 190,
          sleptHours: 8,
          baseNeedHours: 8,
          rhr: (rhr > 0 ? rhr : 52 + (i % 3) - 1).toDouble(),
          rhrKind: rhrFromSleep,
          hrv: hrv,
          hrvKind: hrv == null ? null : 'sdnn',
          vitalsPenalty: penalty,
          source: 'apple_health',
        );

    test('days with night vitals off stay out of the normal', () {
      final clean = [for (var i = 1; i <= 20; i++) past(i)];
      final ill = [
        for (var i = 1; i <= 20; i++)
          i <= 5 ? past(i, penalty: 8, rhr: 64) : past(i),
      ];
      double? rec(List<DailyScore> h) => scoreDay(
        date: day,
        minutes: minutes,
        history: h,
        source: 'apple_health',
      ).recovery;
      expect(rec(ill), closeTo(rec(clean)!, 1e-9));
    });

    test('HRV: few readings count for less', () {
      final hist = [for (var i = 1; i <= 20; i++) past(i, hrv: 40.0 + i % 3)];
      double rec(int? n) => scoreDay(
        date: day,
        minutes: minutes,
        history: hist,
        source: 'apple_health',
        hrv: 60,
        hrvKind: 'sdnn',
        hrvCount: n,
      ).recovery!;
      expect(rec(1), lessThan(rec(3)));
      expect(rec(3), closeTo(rec(null), 1e-9));
    });

    test('HRV: tonight is blended with the week', () {
      final low = [for (var i = 1; i <= 20; i++) past(i, hrv: 40.0 + i % 3)];
      // One great night after a flat month moves recovery up, but less
      // than its own z would: half of it is the week's mean.
      final s = scoreDay(
        date: day,
        minutes: minutes,
        history: low,
        source: 'apple_health',
        hrv: 60,
        hrvKind: 'sdnn',
      );
      expect(s.recovery, greaterThan(60));
      expect(s.hrv, 60);
    });
  });

  test('needSamples ranks by HRV and resting HR, never by sleep', () {
    final d0 = DateTime(2026);
    final days = [
      for (var i = 0; i < 10; i++)
        DailyScore(
          date: d0.add(Duration(days: i)),
          strain: 0,
          trimp: 0,
          hrMax: 190,
          sleptHours: 6 + i / 3,
          rhr: 60 - i.toDouble(),
          hrv: exp(3 + i / 10),
          hrvKind: 'rmssd',
        ),
    ];
    final s = needSamples(days);
    expect(s.length, 10);
    // Lower resting HR and higher HRV with i: autonomic rises with i.
    for (var i = 1; i < 10; i++) {
      expect(s[i].autonomic, greaterThan(s[i - 1].autonomic));
    }
    // No HR or HRV at all: nothing to rank.
    expect(
      needSamples([
        DailyScore(date: d0, strain: 0, trimp: 0, hrMax: 190, sleptHours: 8),
      ]),
      isEmpty,
    );
  });

  test('sleepNeedFrom matches the scored day\'s need', () {
    final hist = [
      for (var i = 1; i <= 10; i++)
        DailyScore(
          date: day.subtract(Duration(days: i)),
          strain: 12,
          trimp: 0,
          hrMax: 190,
          sleptHours: 6.5,
        ),
    ];
    final minutes = [
      ...run(bed, 480, hr: 52, stage: Stage.light),
      ...run(bed.add(const Duration(hours: 8)), 600, hr: 70),
    ];
    final s = scoreDay(date: day, minutes: minutes, history: hist);
    final n = sleepNeedFrom(history: hist, source: bandSource);
    expect(n.need, s.needHours);
    expect(n.debt, s.debtHours);
    expect(n.need, closeTo(7.5 + .5 * 2 + .01 * 12, 1e-9));
  });

  test('hr max starts from the given default and needs sustained minutes', () {
    final m = [
      ...run(bed, 480, hr: 52, stage: Stage.light),
      ...run(bed.add(const Duration(hours: 8)), 30, hr: 150),
      ...run(bed.add(const Duration(hours: 8, minutes: 30)), 1, hr: 215),
      ...run(bed.add(const Duration(hours: 8, minutes: 31)), 600, hr: 70),
    ];
    final s = scoreDay(
      date: day,
      minutes: m,
      p: const ScoringParams(defaultHrMax: 182),
    );
    expect(s.hrMax, 182);
  });

  group('reserve (Karvonen) zones', () {
    test('rest + share of reserve', () {
      // Max 190, rest 50: Z2 from 50 + 0.6 · 140 = 134.
      expect(zoneRange(2, 190, hrRest: 50), (lo: 134, hi: 147));
      expect(zoneFor(133, 190, hrRest: 50), 1);
      expect(zoneFor(134, 190, hrRest: 50), 2);
      expect(zoneFor(185, 190, hrRest: 50), 5);
      // Without a rest HR: % of max, as before.
      expect(zoneRange(2, 190), (lo: 114, hi: 132));
    });
    test('time in zones follows the model', () {
      final hrs = [120, 140, 160];
      expect(timeInZones(hrs, 190), [0, 1, 1, 1, 0]);
      expect(timeInZones(hrs, 190, hrRest: 50), [1, 1, 1, 0, 0]);
    });
  });

  test('known-group check: body-signal days below the usual median', () {
    final days = [
      for (var i = 0; i < 20; i++) (recovery: 60.0 + i, penalty: 0.0),
      (recovery: 40.0, penalty: 8.0), // 48 before the penalty: below 69.5
      (recovery: 50.0, penalty: 4.0), // 54: below
      (recovery: 75.0, penalty: 4.0), // 79: above
    ];
    expect(offDaysBelowMedian(days), closeTo(2 / 3, 1e-9));
    expect(offDaysBelowMedian(days.take(21).toList()), isNull);
  });
}
