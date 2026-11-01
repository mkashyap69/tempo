import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('RPE to zone follows the coach\'s expected efforts', () {
    expect(
      [for (var r = 1; r <= 10; r++) zoneForRpe(r)],
      [1, 1, 2, 2, 3, 3, 4, 4, 5, 5],
    );
    expect(zoneForRpe(expectedRpe(Intensity.easy)), 2);
    expect(zoneForRpe(expectedRpe(Intensity.moderate)), 3);
    expect(zoneForRpe(expectedRpe(Intensity.hard)), 4);
    expect(manualZones(40, 7), [0, 0, 0, 40, 0]);
  });

  test('load is session RPE less what the watch caught', () {
    final full = manualExtraTrimp(rpe: 5, minutes: 60);
    expect(full, closeTo(trimpFromRpe(5, 60), 1e-9));
    expect(
      manualExtraTrimp(rpe: 5, minutes: 60, hrTrimp: full / 2),
      closeTo(full / 2, 1e-9),
    );
    expect(manualExtraTrimp(rpe: 5, minutes: 60, hrTrimp: full * 2), 0);
    // A 45-minute moderate session lands in a moderate day's strain.
    final s = strainFromTrimp(manualExtraTrimp(rpe: 5, minutes: 45));
    expect(s, inInclusiveRange(6, 14));
  });
}
