import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('needs three sessions with zone time', () {
    expect(
      typicalZoneShares([
        [10, 20, 0, 0, 0],
        [0, 0, 0, 0, 0],
        [5, 25, 0, 0, 0],
      ]),
      isNull,
    );
  });

  test('the middle half of each zone share', () {
    final t = typicalZoneShares([
      [0, 30, 10, 0, 0], // Z2 .75
      [0, 20, 20, 0, 0], // Z2 .5
      [0, 25, 15, 0, 0], // Z2 .625
      [0, 40, 0, 0, 0], // Z2 1
      [0, 10, 30, 0, 0], // Z2 .25
    ])!;
    expect(t[1].lo, closeTo(.5, 1e-9));
    expect(t[1].hi, closeTo(.75, 1e-9));
    expect(t[4].hi, 0);
  });

  test('more or less than usual, with a margin', () {
    final t = [
      for (var i = 0; i < 5; i++)
        i == 1 ? (lo: .5, hi: .75) : (lo: 0.0, hi: .25),
    ];
    expect(zoneShareVsTypical([0, 20, 0, 0, 20], t), [0, 0, 0, 0, 1]);
    expect(zoneShareVsTypical([0, 4, 16, 0, 0], t), [0, -1, 1, 0, 0]);
    // 0.76 is within the margin of 0.75.
    expect(zoneShareVsTypical([0, 76, 24, 0, 0], t), [0, 0, 0, 0, 0]);
    expect(zoneShareVsTypical([0, 0, 0, 0, 0], t), [0, 0, 0, 0, 0]);
  });
}
