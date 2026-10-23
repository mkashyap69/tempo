import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('Tempo Age v3 (algo 10)', () {
    test('estimated VO2 max moves at most 2 years; measured up to 5', () {
      LongevityInputs i({required bool measured}) => LongevityInputs(
        age: 35,
        male: true,
        daysOfData: 40,
        vo2max: 70,
        vo2maxMeasured: measured,
      );
      double fit(TempoAge t) =>
          t.contributors.firstWhere((c) => c.lever == Lever.fitness).years;
      expect(fit(tempoAge(i(measured: false))), closeTo(-2, 1e-9));
      expect(fit(tempoAge(i(measured: true))), closeTo(-5, 1e-9));
      // And the range is a year wider while it's an estimate.
      expect(
        tempoAge(i(measured: false)).halfRange -
            tempoAge(i(measured: true)).halfRange,
        closeTo(1, 1e-9),
      );
    });
    test('levers from several groups are shrunk; smoking is not', () {
      const one = LongevityInputs(
        age: 35,
        male: true,
        daysOfData: 40,
        steps: 3000,
      );
      const two = LongevityInputs(
        age: 35,
        male: true,
        daysOfData: 40,
        steps: 3000,
        sleepHours: 5,
        smoking: Smoking.current,
      );
      double y(TempoAge t, Lever l) =>
          t.contributors.firstWhere((c) => c.lever == l).years;
      expect(
        y(tempoAge(two), Lever.steps),
        closeTo(y(tempoAge(one), Lever.steps) * crossGroupShrink, 1e-9),
      );
      expect(y(tempoAge(two), Lever.smoking), closeTo(10, 1e-9));
    });
  });
}
