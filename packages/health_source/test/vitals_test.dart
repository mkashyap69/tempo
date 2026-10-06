import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

HealthRecord r(
  HealthKind k,
  DateTime a,
  double v, {
  DateTime? b,
  String src = 'x',
  String? extra,
  String uuid = 'u',
}) => HealthRecord(
  uuid: uuid,
  kind: k,
  start: a,
  end: b ?? a,
  value: v,
  sourceApp: src,
  extra: extra,
);

void main() {
  final night0 = DateTime(2026, 10, 1, 23), night1 = DateTime(2026, 10, 2, 7);

  group('night HRV', () {
    test('geometric mean of readings in the night, with slack', () {
      final h = nightHrv(
        [
          r(HealthKind.hrvSdnn, DateTime(2026, 10, 1, 22, 40), 20),
          r(HealthKind.hrvSdnn, DateTime(2026, 10, 2, 3), 80),
          r(HealthKind.hrvSdnn, DateTime(2026, 10, 2, 12), 500 / 10),
        ],
        night0,
        night1,
      )!;
      expect(h.kind, HrvKind.sdnn);
      expect(h.n, 2);
      expect(h.ms, closeTo(40, 1e-9));
    });

    test('prefers RMSSD and drops implausible values and Tempo', () {
      final h = nightHrv(
        [
          r(HealthKind.hrvSdnn, DateTime(2026, 10, 2, 1), 50),
          r(HealthKind.hrvRmssd, DateTime(2026, 10, 2, 2), 30),
          r(HealthKind.hrvRmssd, DateTime(2026, 10, 2, 3), 900),
          r(HealthKind.hrvRmssd, DateTime(2026, 10, 2, 4), 60, src: tempoAppId),
        ],
        night0,
        night1,
      )!;
      expect(h.kind, HrvKind.rmssd);
      expect(h.ms, closeTo(30, 1e-9));
    });

    test('null with nothing in the night', () {
      expect(nightHrv(const [], night0, night1), isNull);
    });
  });

  test('source resting HR is that day only, plausible only', () {
    final day = DateTime(2026, 10, 2);
    expect(
      sourceRestingHr([
        r(HealthKind.restingHr, DateTime(2026, 10, 1, 9), 70),
        r(HealthKind.restingHr, DateTime(2026, 10, 2, 9), 54),
        r(HealthKind.restingHr, DateTime(2026, 10, 2, 10), 8),
      ], day),
      54,
    );
    expect(sourceRestingHr(const [], day), isNull);
  });

  group('workouts', () {
    test('maps types and drops duplicates, Tempo and bad spans', () {
      final a = DateTime(2026, 10, 2, 18);
      final ws = healthWorkouts([
        r(
          HealthKind.workout,
          a,
          0,
          b: a.add(const Duration(minutes: 40)),
          extra: 'RUNNING',
          src: 'com.apple.health',
        ),
        // Strava logging the same run a minute later.
        r(
          HealthKind.workout,
          a.add(const Duration(minutes: 1)),
          0,
          b: a.add(const Duration(minutes: 41)),
          extra: 'RUNNING',
          src: 'com.strava',
        ),
        r(
          HealthKind.workout,
          a.add(const Duration(hours: 2)),
          0,
          b: a.add(const Duration(hours: 3)),
          extra: 'TRADITIONAL_STRENGTH_TRAINING',
          src: tempoAppId,
        ),
        r(HealthKind.workout, a, 0, extra: 'YOGA'),
      ]);
      expect(ws, hasLength(1));
      expect(ws.single.sport, Sport.running);
      expect(ws.single.title, 'Running');
    });

    test('titles and sports', () {
      expect(healthWorkoutTitle('RUNNING_TREADMILL'), 'Running treadmill');
      expect(healthWorkoutTitle('OTHER'), 'Workout');
      expect(sportForHealthType('WEIGHTLIFTING'), Sport.strength);
      expect(sportForHealthType('HIKING'), Sport.walking);
      expect(sportForHealthType('SWIMMING'), isNull);
    });
  });

  group('reconcile', () {
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 3);
    StoredKey s(HealthRecord x) => (key: x.key, kind: x.kind, start: x.start);
    final a = r(HealthKind.heartRate, DateTime(2026, 10, 2, 1), 60, uuid: 'a');
    final b = r(HealthKind.heartRate, DateTime(2026, 10, 2, 2), 61, uuid: 'b');
    final c = r(HealthKind.heartRate, DateTime(2026, 10, 2, 3), 62, uuid: 'c');
    final old = r(HealthKind.heartRate, DateTime(2026, 9, 1), 62, uuid: 'o');

    test('a record no longer in Health is gone', () {
      final x = reconcile(
        stored: [s(a), s(b), s(c), s(old)],
        fresh: [a, c],
        read: {HealthKind.heartRate},
        from: from,
        to: to,
      );
      expect(x.gone, [b.key]);
      expect(x.doubtful, isEmpty);
    });

    test('an empty or much smaller read is doubtful, not a delete', () {
      final empty = reconcile(
        stored: [s(a), s(b), s(c)],
        fresh: const [],
        read: {HealthKind.heartRate},
        from: from,
        to: to,
      );
      expect(empty.gone, isEmpty);
      expect(empty.doubtful, [HealthKind.heartRate]);
      final small = reconcile(
        stored: [s(a), s(b), s(c)],
        fresh: [a],
        read: {HealthKind.heartRate},
        from: from,
        to: to,
      );
      expect(small.gone, isEmpty);
    });

    test('kinds not read this time are left alone', () {
      final x = reconcile(
        stored: [s(a), s(b)],
        fresh: const [],
        read: const {},
        from: from,
        to: to,
      );
      expect(x.gone, isEmpty);
      expect(x.doubtful, isEmpty);
    });
  });
}
