import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

const t = StrainTarget(11, 14);

NextUp? at(
  int hour, {
  double strain = 4,
  StrainTarget target = t,
  bool planOpen = false,
  RecoveryForecast? forecast,
  Sport? likes,
}) => nextUp(
  nowMinute: hour * 60,
  bedtimeMinute: 22 * 60 + 50,
  bedtime: '22:50',
  strain: strain,
  target: target,
  planOpen: planOpen,
  hrRest: 50,
  hrMax: 185,
  likes: likes,
  needHours: 8.08,
  forecast: forecast,
);

void main() {
  group('minutesToStrain', () {
    test('an easy run fills a gap faster than a walk', () {
      final walk = minutesToStrain(
        strain: 4,
        goal: 11,
        reserve: briskWalkReserve,
        hrRest: 50,
        hrMax: 185,
      )!;
      final run = minutesToStrain(
        strain: 4,
        goal: 11,
        reserve: easyCardioReserve,
        hrRest: 50,
        hrMax: 185,
      )!;
      expect(run, lessThan(walk));
      expect(run % 5, 0);
    });

    test('nothing to fill, or too long to be a suggestion', () {
      final none = minutesToStrain(
        strain: 12,
        goal: 11,
        reserve: .6,
        hrRest: 50,
        hrMax: 185,
      );
      expect(none, isNull);
      final long = minutesToStrain(
        strain: 1,
        goal: 18,
        reserve: briskWalkReserve,
        hrRest: 50,
        hrMax: 185,
      );
      expect(long, isNull);
    });
  });

  group('nextUp', () {
    test('mornings: what fills the rest of today', () {
      final n = at(10)!;
      expect(n.kind, NextUpKind.room);
      expect(n.title, '7.0 strain to go today');
      expect(n.body, startsWith('A '));
      expect(n.body, contains('brisk walk'));
      expect(n.body, contains('easy run'));
      expect(n.body, endsWith('11–14 range.'));
    });

    test('a rider is offered a ride', () {
      expect(at(10, likes: Sport.cycling)!.body, contains('easy ride'));
    });

    test('quiet with a session still to do, in range, or on a capped day', () {
      expect(at(10, planOpen: true), isNull);
      expect(at(10, strain: 12), isNull);
      expect(at(10, target: const StrainTarget(0, 8, cap: true)), isNull);
    });

    test('afternoons: bedtime and tomorrow', () {
      final n = at(
        16,
        forecast: const RecoveryForecast(
          low: 68,
          mid: 72,
          high: 76,
          sleepHours: 8,
          hourLessCost: 6,
          mornings: 30,
        ),
      )!;
      expect(n.kind, NextUpKind.tonight);
      expect(n.title, 'Lights out by 22:50');
      expect(n.body, contains('8 h 05 m'));
      expect(n.body, contains('68–76'));
      expect(n.body, contains('about 6 points'));
    });

    test('the evening is left to the Tonight card', () {
      expect(at(21), isNull);
    });
  });
}
