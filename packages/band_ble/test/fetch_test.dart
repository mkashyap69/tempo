// Synthetic vectors; replace with golden captures once docs/packets/ has them.
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('band time round-trips at minute precision', () {
    final t = DateTime(2026, 10, 3, 21, 45);
    expect(decodeBandTime(encodeBandTime(t)), t);
  });

  test('start command layout', () {
    final c = FetchCommands.start(
      FetchType.activity,
      DateTime(2026, 1, 2, 3, 4),
    );
    expect(c.sublist(0, 2), [0x01, 0x01]);
    expect(c.sublist(2, 8), [0xea, 0x07, 1, 2, 3, 4]);
  });

  test('start reply', () {
    final t = encodeBandTime(DateTime(2026, 1, 2, 3, 4));
    final r = FetchStartReply.parse([
      0x10,
      0x01,
      0x01,
      0x2c,
      0x01,
      0,
      0,
      ...t,
    ])!;
    expect(r.ok, isTrue);
    expect(r.count, 300);
    expect(r.start, DateTime(2026, 1, 2, 3, 4));
    expect(FetchStartReply.parse([0x10, 0x01, 0x04])!.ok, isFalse);
    expect(FetchStartReply.parse([0x10, 0x02, 0x01]), isNull);
  });

  test('transfer done', () {
    expect(parseTransferDone([0x10, 0x02, 0x01]), isTrue);
    expect(parseTransferDone([0x10, 0x02, 0x04]), isFalse);
    expect(parseTransferDone([0x10, 0x01, 0x01]), isNull);
  });

  test('assembler strips sequence byte, joins split records, counts gaps', () {
    final a = ChunkAssembler()
      ..add([0, 1, 2, 3])
      ..add([1, 4, 5])
      ..add([3, 6]);
    expect(a.take(), [1, 2, 3, 4, 5, 6]);
    expect(a.gaps, 1);
  });

  test('activity records', () {
    final start = DateTime(2026, 1, 1, 23);
    final r = parseActivity(
      Uint8List.fromList([0x70, 10, 0, 55, 0x01, 80, 12, 0xff, 9]),
      start,
    );
    expect(r.length, 2); // trailing partial record dropped
    expect(r[0].kind, 0x70);
    expect(r[0].hr, 55);
    expect(r[1].ts, start.add(const Duration(minutes: 1)));
    expect(r[1].steps, 12);
    expect(r[1].hr, isNull);
  });

  test('stress skips empty minutes', () {
    final s = parseStress(
      Uint8List.fromList([30, 0xff, 0, 45]),
      DateTime(2026),
    );
    expect(s.map((x) => x.value), [30, 45]);
    expect(s[1].ts, DateTime(2026).add(const Duration(minutes: 3)));
  });

  test('spo2 records', () {
    final t = DateTime(2026, 2, 3, 4, 5);
    final s = parseSpo2(
      Uint8List.fromList([...encodeBandTime(t), 97, ...encodeBandTime(t), 0]),
    );
    expect(s.single.value, 97);
    expect(s.single.ts, t);
  });

  test('settings payloads', () {
    expect(SettingsCommands.hrInterval(1), [0x14, 1]);
    final u = SettingsCommands.userInfo(
      UserProfile(birthDate: DateTime(1990, 5, 6), heightCm: 175, weightKg: 70),
    );
    expect(u.length, 16);
    expect(u.sublist(3, 7), [0xc6, 0x07, 5, 6]);
    expect(u[10] | (u[11] << 8), 14000);
    expect(
      SettingsCommands.currentTime(DateTime(2026, 10, 3, 9, 8, 7)).length,
      11,
    );
  });
}
