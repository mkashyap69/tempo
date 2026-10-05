// Heart Rate Measurement (0x2A37) per the Bluetooth SIG spec. Synthetic
// until a live capture shows what the Mi Band 6 actually sends.
import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bpm only: no RR', () {
    final m = parseHrMeasurement([0x00, 72])!;
    expect(m.bpm, 72);
    expect(m.hasRr, isFalse);
    expect(m.rrMs, isEmpty);
  });

  test('RR intervals in 1/1024 s become ms', () {
    // flags 0x10, 64 bpm, RR 1024 (1000 ms) and 960 (938 ms)
    final m = parseHrMeasurement([0x10, 64, 0x00, 0x04, 0xc0, 0x03])!;
    expect(m.bpm, 64);
    expect(m.hasRr, isTrue);
    expect(m.rrMs, [1000, 938]);
  });

  test('uint16 bpm and energy expended before RR', () {
    // flags 0x19: u16 bpm, energy present, RR present
    final m = parseHrMeasurement([0x19, 0x2c, 0x01, 0x10, 0x00, 0x00, 0x02])!;
    expect(m.bpm, 300);
    expect(m.rrMs, [500]);
  });

  test('short packets are rejected; odd trailing byte ignored', () {
    expect(parseHrMeasurement([]), isNull);
    expect(parseHrMeasurement([0x01, 0x2c]), isNull);
    expect(parseHrMeasurement([0x10, 60, 0x00, 0x04, 0x01])!.rrMs, [1000]);
  });

  test('fetch probe command for any type code', () {
    final t = DateTime(2026, 10, 5, 7, 30, 15);
    final b = FetchCommands.startCode(0x2a, t);
    expect(b.take(2), [0x01, 0x2a]);
    expect(b.length, 10);
    expect(FetchCommands.start(FetchType.activity, t).skip(2), b.skip(2));
  });
}
