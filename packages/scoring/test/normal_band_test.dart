import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

SignalReading read(double? v, {bool higherIsWorse = true, int nights = 20}) =>
    bodySignals([
      SignalInput(
        key: 'rhr',
        value: v,
        history: [for (var i = 0; i < nights; i++) 50.0 + (i % 5) - 2],
        higherIsWorse: higherIsWorse,
        minDelta: 3,
      ),
    ]).readings.single;

void main() {
  test('the reading carries the spread it was judged against', () {
    final r = read(50);
    // The sample SD is 1.45; the floor (half of minDelta 3) lifts it to 1.5.
    expect(r.sd, 1.5);
    expect(r.z, closeTo(0, 1e-9));
  });

  test('the band is the middle 80 % around your mean', () {
    final b = normalBand(read(50))!;
    expect(b.lo, closeTo(50 - normalBandZ * 1.5, 1e-9));
    expect(b.hi, closeTo(50 + normalBandZ * 1.5, 1e-9));
  });

  test('no band before it is judged', () {
    expect(normalBand(read(50, nights: 5)), isNull);
    expect(normalPlace(read(50, nights: 5)), NormalPlace.learning);
    expect(normalPlace(read(null)), NormalPlace.missing);
  });

  test('in your normal, better than usual, or outside', () {
    expect(normalPlace(read(51)), NormalPlace.inNormal);
    expect(normalPlace(read(47)), NormalPlace.better);
    expect(normalPlace(read(57)), NormalPlace.outside);
  });

  test('higher is better flips which side is better', () {
    expect(normalPlace(read(53, higherIsWorse: false)), NormalPlace.better);
  });
}
