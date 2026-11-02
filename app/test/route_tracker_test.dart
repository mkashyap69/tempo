import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/route_tracker.dart';
import 'package:tempo/src/core/workout_presence.dart';
import 'package:tempo/src/design/beating_heart.dart';
import 'package:tempo/src/state/live_session.dart';

/// Metres of latitude per degree, near enough for building test tracks.
const _mPerDegLat = 111195.0;

void main() {
  group('haversineM', () {
    test('one degree of latitude is about 111.2 km', () {
      expect(haversineM(0, 0, 1, 0), closeTo(111195, 5));
    });
    test('the same point is zero', () {
      expect(haversineM(52.5, 13.4, 52.5, 13.4), 0);
    });
  });

  group('RouteTracker with GPS', () {
    final t0 = DateTime(2026, 11, 2, 7);

    /// A straight run north at [speed] m/s, one fix a second.
    List<GeoFix> track(int seconds, double speed, {double acc = 5}) => [
      for (var i = 0; i <= seconds; i++)
        GeoFix(
          48 + i * speed / _mPerDegLat,
          11,
          accuracyM: acc,
          at: t0.add(Duration(seconds: i)),
        ),
    ];

    test('a steady 6:00/km run measures distance, pace and splits', () {
      final r = RouteTracker();
      // 1000 m / 360 s.
      const speed = 1000 / 360;
      final fixes = track(800, speed);
      for (final (i, f) in fixes.indexed) {
        r.addFix(f, i.toDouble());
      }
      // Fixes 2.8 m apart sit under the 3 m jitter floor, so legs are two
      // fixes long: distance is still right to the metre or two.
      expect(r.meters, closeTo(800 * speed, 4));
      expect(r.paceNow(800)!, closeTo(360, 6));
      expect(r.paceAvg(800)!, closeTo(360, 6));
      expect(r.splits.length, 2);
      expect(r.splits.first, closeTo(360, 3));
    });

    test('standing still with wandering fixes adds nothing', () {
      final r = RouteTracker();
      for (var i = 0; i < 120; i++) {
        // ±2 m of wobble, 8 m accuracy.
        final wob = (i.isEven ? 2 : -2) / _mPerDegLat;
        r.addFix(
          GeoFix(48 + wob, 11, accuracyM: 8, at: t0.add(Duration(seconds: i))),
          i.toDouble(),
        );
      }
      expect(r.meters, 0);
      expect(r.paceNow(120), isNull);
    });

    test('poor fixes are skipped and a jump is not counted', () {
      final r = RouteTracker();
      r.addFix(GeoFix(48, 11, accuracyM: 5, at: t0), 0);
      expect(
        r.addFix(
          GeoFix(
            48.001,
            11,
            accuracyM: 80,
            at: t0.add(const Duration(seconds: 5)),
          ),
          5,
        ),
        isFalse,
      );
      // 1.1 km in 2 s: a GPS jump.
      expect(
        r.addFix(
          GeoFix(
            48.01,
            11,
            accuracyM: 5,
            at: t0.add(const Duration(seconds: 7)),
          ),
          7,
        ),
        isFalse,
      );
      expect(r.meters, 0);
      // Running on from the new spot counts again.
      r.addFix(
        GeoFix(
          48.01 + 30 / _mPerDegLat,
          11,
          accuracyM: 5,
          at: t0.add(const Duration(seconds: 17)),
        ),
        17,
      );
      expect(r.meters, closeTo(30, 0.5));
    });

    test('ground covered during a pause is not counted', () {
      final r = RouteTracker();
      r.addFix(GeoFix(48, 11, accuracyM: 5, at: t0), 0);
      r.addFix(
        GeoFix(
          48 + 100 / _mPerDegLat,
          11,
          accuracyM: 5,
          at: t0.add(const Duration(seconds: 30)),
        ),
        30,
      );
      r.breakLeg();
      // Walked 500 m while paused; resumes there.
      r.addFix(
        GeoFix(
          48 + 600 / _mPerDegLat,
          11,
          accuracyM: 5,
          at: t0.add(const Duration(minutes: 6)),
        ),
        30,
      );
      r.addFix(
        GeoFix(
          48 + 650 / _mPerDegLat,
          11,
          accuracyM: 5,
          at: t0.add(const Duration(minutes: 6, seconds: 15)),
        ),
        45,
      );
      expect(r.meters, closeTo(150, 1));
    });
  });

  group('RouteTracker with the band', () {
    test('day totals become distance; miles split at 1609 m', () {
      final r = RouteTracker(splitM: 1609.344);
      for (var s = 0; s <= 1200; s += 20) {
        r.setTotal(s * 1.5, s.toDouble()); // 1.5 m/s
      }
      expect(r.meters, 1800);
      expect(r.splits.single, closeTo(1609.344 / 1.5, 1));
      expect(
        r.paceNow(1200, window: 120, minWindowS: 40),
        closeTo(1000 / 1.5, 1),
      );
    });
  });

  group('WorkoutView', () {
    LiveState run({LivePhase phase = LivePhase.live, bool metric = true}) =>
        LiveState(
          phase: phase,
          sport: sc.Sport.running,
          title: 'Running · open session',
          bpm: 152,
          hrMax: 190,
          hrRest: 50,
          elapsed: const Duration(minutes: 31, seconds: 4),
          distanceM: 5123,
          paceNow: 362,
          paceAvg: 364,
          metric: metric,
          trimp: 40,
        );

    test('one line with heart rate, distance, pace and strain', () {
      final v = WorkoutView.of(run());
      expect(v.line, startsWith('152 bpm · Z'));
      expect(v.line, contains('5.12 km · 6:02 /km · strain +'));
      expect(v.clockTitle, 'Running · 31:04');
    });

    test('miles, and paused', () {
      final v = WorkoutView.of(run(phase: LivePhase.paused, metric: false));
      expect(v.line, startsWith('Paused · 152 bpm'));
      expect(v.line, contains('3.18 mi · 9:43 /mi'));
      expect(v.clockTitle, 'Running · 31:04 · paused');
      expect(v.toMap()['paused'], true);
      expect(v.toMap()['distanceUnit'], 'mi');
    });

    test('timed only, no distance: says so', () {
      final v = WorkoutView.of(
        const LiveState(
          phase: LivePhase.live,
          sport: sc.Sport.strength,
          title: 'Strength · open session',
          timerOnly: true,
        ),
      );
      expect(v.line, 'Timing · heart rate from Health later');
      expect(v.distance, isNull);
    });
  });

  test('the heart beats once per beat of the reading', () {
    expect(BeatingHeart.period(60), const Duration(seconds: 1));
    expect(BeatingHeart.period(120), const Duration(milliseconds: 500));
    expect(BeatingHeart.period(10), const Duration(seconds: 2));
  });
}
