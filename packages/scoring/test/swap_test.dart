import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

DoneWorkout w(Sport? s, int minutes, {int hard = 0, double strain = 0}) =>
    DoneWorkout(
      start: DateTime(2026, 10, 6, 18),
      minutes: minutes,
      sport: s,
      zoneMinutes: [0, minutes - hard, 0, hard, 0],
      strain: strain,
    );

void main() {
  final strength = sessionTemplate('strength_full');
  final easyRun = sessionTemplate('easy_run');
  final threshold = sessionTemplate('threshold_run');
  Swap swap(Session plan, List<DoneWorkout> ws, {double strain = 0}) =>
      substitute(
        plan: plan,
        match: matchSession(plan, ws),
        workouts: ws,
        dayStrain: strain,
      );

  test('same family and enough: counted', () {
    final s = swap(easyRun, [w(Sport.cycling, 45)]);
    expect(s.kind, SwapKind.counted);
    expect(s.by!.sport, Sport.cycling);
    expect(
      swap(threshold, [w(Sport.hiit, 40, hard: 12)]).kind,
      SwapKind.counted,
    );
  });

  test('strength planned, a light walk: credited, strength stands', () {
    final s = swap(strength, [w(Sport.walking, 60)], strain: 6);
    expect(s.kind, SwapKind.stands);
    expect(s.hardDay, isFalse);
  });

  test('strength planned, a hard ride: strength moves', () {
    final s = swap(strength, [w(Sport.cycling, 50, hard: 15)], strain: 14);
    expect(s.kind, SwapKind.moved);
    expect(s.hardDay, isTrue);
  });

  test('a long easy workout past the plan\'s strain also makes it hard', () {
    final s = swap(strength, [
      w(Sport.walking, 120),
    ], strain: strength.strainHi + .5);
    expect(s.kind, SwapKind.moved);
  });

  test('short bits are ignored; rest days only report hardness', () {
    expect(swap(strength, [w(Sport.walking, 8)]).kind, SwapKind.none);
    final r = swap(sessionTemplate('rest'), [w(Sport.running, 40, hard: 10)]);
    expect(r.kind, SwapKind.none);
    expect(r.hardDay, isTrue);
  });

  group('moveTarget', () {
    Session k(String key) => sessionTemplate(key);
    test('next easy day not next to a heavy one, never tomorrow', () {
      // Mon strength (today) · Tue easy · Wed easy · Thu threshold · Fri easy
      // · Sat easy · Sun rest
      final week = [
        k('strength_full'),
        k('easy_run'),
        k('easy_run'),
        k('threshold_run'),
        k('easy_run'),
        k('easy_walk'),
        k('rest'),
      ];
      // Tue is tomorrow; Wed and Fri touch Thursday's hard day → Saturday.
      expect(moveTarget(week, 0, k('strength_full')), 5);
    });
    test('none left this week', () {
      final week = [
        k('easy_run'),
        k('easy_run'),
        k('easy_run'),
        k('easy_run'),
        k('easy_run'),
        k('threshold_run'),
        k('strength_full'),
      ];
      expect(moveTarget(week, 4, k('strength_full')), isNull);
    });
    test('unavailable days are skipped', () {
      final week = [for (var i = 0; i < 7; i++) k('easy_walk')];
      expect(moveTarget(week, 0, k('strength_full'), available: {1, 4}), 3);
    });
  });

  test('what you did becomes a plan session', () {
    final s = sessionFromDone(w(Sport.cycling, 62, hard: 14, strain: 12));
    expect(s.title, 'Ride 62′');
    expect(s.isHard, isTrue);
    expect(s.minutes, 62);
    expect(Session.fromJson(s.toJson()).title, 'Ride 62′');
    expect(sessionFromDone(w(Sport.walking, 60)).intensity, Intensity.easy);
  });
}
