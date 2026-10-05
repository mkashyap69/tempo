// Golden: characteristic reads and live HR from the first Band explorer
// run, docs/packets/explorer-2026-10-05T10-34-28.json (V1.0.6.20, +5:30).
import 'dart:convert';
import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

const report = '../../docs/packets/explorer-2026-10-05T10-34-28.json';

void main() {
  final j = jsonDecode(File(report).readAsStringSync()) as Map<String, dynamic>;
  final chars = (j['characteristics'] as Map).cast<String, Object?>();
  List<int> bytes(String short) {
    final h =
        chars.entries.firstWhere((e) => e.key.startsWith(short)).value
            as String;
    return [
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ];
  }

  test('0x0006 battery: 46 %, not charging, last charged to 98 %', () {
    final b = parseHuamiBattery(bytes('00000006'))!;
    expect(b.level, 46);
    expect(b.charging, isFalse);
    expect(b.lastChargeAt!.toUtc(), DateTime.utc(2026, 10, 4, 17, 36, 51));
    expect(b.lastChargeLevel, 98);
    // Same level as the SIG battery characteristic.
    expect(parseBattery(bytes('00002a19'), huami: false), 46);
  });

  test('0x0007 realtime: 81 steps, 51 m, 6 kcal', () {
    final r = parseRealtimeSteps(bytes('00000007'))!;
    expect(r.steps, 81);
    expect(r.meters, 51);
    expect(r.kcal, 6);
  });

  test('band clock (0x2A2B) in step: 2026-10-05 16:01:38 +5:30', () {
    final t = bytes('00002a2b');
    expect(t.length, 11);
    expect(
      decodeFetchTime([...t.sublist(0, 7), t[10]])!.toUtc(),
      DateTime.utc(2026, 10, 5, 10, 31, 38),
    );
  });

  test('live HR (0x2A37) carries bpm only: no RR intervals', () {
    final raw = ((j['liveHr'] as Map)['raw'] as List).cast<String>();
    expect(raw, hasLength(43));
    for (final h in raw) {
      final m = parseHrMeasurement([
        for (var i = 0; i < h.length; i += 2)
          int.parse(h.substring(i, i + 2), radix: 16),
      ])!;
      expect(m.flags, 0);
      expect(m.rrMs, isEmpty);
    }
  });
}
