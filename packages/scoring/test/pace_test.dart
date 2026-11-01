import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// Against Daniels' published VDOT tables (Daniels' Running Formula).
void main() {
  test('VDOT from a race matches the tables', () {
    // 5K in 19:57 is VDOT 50; 10K 41:21 is 50; 5K 25:00 is about 38.
    expect(vdotFromRace(5000, 19 * 60 + 57), closeTo(50, .3));
    expect(vdotFromRace(10000, 41 * 60 + 21), closeTo(50, .3));
    expect(vdotFromRace(5000, 25 * 60), closeTo(38.3, .5));
  });

  test('equivalent times match the tables', () {
    // VDOT 50: half 1:31:35, marathon 3:10:49.
    expect(raceSeconds(50, 21097.5), closeTo(91 * 60 + 35, 60));
    expect(raceSeconds(50, 42195), closeTo(3 * 3600 + 10 * 60 + 49, 120));
    // Round trip.
    final t = raceSeconds(45, 10000);
    expect(vdotFromRace(10000, t), closeTo(45, 1e-3));
  });

  test('zone paces get faster zone by zone', () {
    // VDOT 50: easy 5:07 /km, threshold 4:15 /km, marathon 4:31 inside Z3.
    final z2 = zonePace(2, 50), z3 = zonePace(3, 50), z4 = zonePace(4, 50);
    expect(z2.fast, closeTo(5 * 60 + 7, 5));
    final m = raceSeconds(50, 42195) / 42.195;
    expect(m, inInclusiveRange(z3.fast, z3.slow));
    expect(z4.fast, inInclusiveRange(4 * 60 + 5, 4 * 60 + 25));
    for (var z = 1; z < 5; z++) {
      expect(zonePace(z + 1, 50).fast, lessThan(zonePace(z, 50).fast));
      expect(zonePace(z, 50).slow, greaterThan(zonePace(z, 50).fast));
    }
  });

  test('distance and text', () {
    final km = kmFor(120, 2, 50);
    expect(km, inInclusiveRange(20, 25));
    expect(paceText(300), '5:00');
    expect(paceText(300, miles: true), '8:03');
    expect(durationText(3 * 3600 + 28 * 60 + 40), '3:28:40');
    expect(durationText(24 * 60 + 5), '24:05');
  });

  test('a run\'s paces in one line; long runs say how far', () {
    final t = sessionPaces(sessionTemplate('threshold_run'), 50)!;
    expect(t, startsWith('Z'));
    expect(t, endsWith('/km'));
    expect(t, contains('Z4 '));
    final l = sessionPaces(sessionTemplate('long_run'), 50)!;
    expect(l, contains('about '));
    expect(sessionPaces(sessionTemplate('strength_full'), 50), isNull);
    expect(goalMetres(BlockGoal.marathon), 42195);
  });
}
