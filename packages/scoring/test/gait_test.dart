import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> mins(List<int> steps) => [
  for (final (i, s) in steps.indexed)
    Minute(DateTime(2026, 10, 6, 19, 1).add(Duration(minutes: i)), steps: s),
];

void main() {
  group('strideMetres', () {
    test('uses the band stride for walks', () {
      // 6 Oct 19:44: 4379 steps, 3356 m.
      expect(
        strideMetres(running: false, bandStride: 3356 / 4379),
        closeTo(.766, .001),
      );
    });
    test('falls back to height, and runs always use height', () {
      expect(strideMetres(running: false, heightCm: 170), closeTo(.7055, 1e-9));
      expect(
        strideMetres(running: true, bandStride: .766, heightCm: 170),
        closeTo(1.105, 1e-9),
      );
    });
    test('ignores an implausible band ratio', () {
      expect(
        strideMetres(running: false, bandStride: .05),
        closeTo(.7055, 1e-9),
      );
    });
  });

  group('gaitOf', () {
    test('cadence over moving minutes, peak, distance and pace', () {
      final g = gaitOf(mins([100, 110, 20, 120]), strideM: 1)!;
      expect(g.steps, 350);
      expect(g.movingMinutes, 3);
      expect(g.cadence, closeTo(110, 1e-9));
      expect(g.peakCadence, 120);
      expect(g.distanceM, 350);
      // 4 min for 0.35 km.
      expect(g.pacePerKm, const Duration(seconds: 686));
      // 3 moving min for 0.33 km.
      expect(g.movingPacePerKm, const Duration(seconds: 545));
      expect(g.running, isFalse);
    });
    test('kilometre splits are interpolated inside the minute', () {
      // 100 m a minute: 1 km every 10 min.
      final g = gaitOf(mins(List.filled(25, 100)), strideM: 1)!;
      expect(g.splits, [
        const Duration(minutes: 10),
        const Duration(minutes: 10),
      ]);
      // 160 steps/min at 1.1 m is a run.
      expect(gaitOf(mins(List.filled(5, 160)), strideM: 1.1)!.running, true);
    });
    test('null with almost no steps', () {
      expect(gaitOf(mins([10, 20, 30]), strideM: .75), isNull);
    });
  });
}
