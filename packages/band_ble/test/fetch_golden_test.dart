// Golden: the activity fetch in docs/packets/android-2026-10-04T12-33-07
// (Mi Band 6, V1.0.6.20, phone at UTC+5:30).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

const capture = '../../docs/packets/android-2026-10-04T12-33-07.587236Z.jsonl';

void main() {
  final events = [
    for (final l in File(capture).readAsLinesSync())
      jsonDecode(l) as Map<String, dynamic>,
  ];
  List<int> hexOf(Map<String, dynamic> e) => [
    for (var i = 0; i < (e['hex'] as String).length; i += 2)
      int.parse((e['hex'] as String).substring(i, i + 2), radix: 16),
  ];
  bool on(Map<String, dynamic> e, String dir, String char) =>
      e['dir'] == dir && (e['char'] as String? ?? '').contains(char);

  test('start reply: 1716 records from 13:27 local (+5:30)', () {
    final reply = events
        .where((e) => on(e, 'rx', '00000004'))
        .map((e) => FetchStartReply.parse(hexOf(e)))
        .firstWhere((r) => r != null && r.count > 0)!;
    expect(reply.count, 1716);
    expect(reply.start!.toUtc(), DateTime.utc(2026, 10, 3, 7, 57));
  });

  group('activity payload', () {
    // Also in the capture: a 14:18 nap on 3 Oct flagged the same way.
    final asm = ChunkAssembler();
    for (final e in events.where((e) => on(e, 'rx', '00000005'))) {
      asm.add(hexOf(e));
    }
    final data = asm.take();
    // Minute 0 is 2026-10-03 13:27 at UTC+5:30.
    final start = DateTime.utc(2026, 10, 3, 7, 57);
    final recs = parseActivity(Uint8List.fromList(data), start);
    DateTime at(int h, int m, {int day = 4}) => DateTime.utc(
      2026,
      10,
      day,
      h,
      m,
    ).subtract(const Duration(hours: 5, minutes: 30));
    ActivityRecord rec(DateTime t) => recs[t.difference(start).inMinutes];

    test('13728 bytes, 8 per minute, no gaps', () {
      expect(data.length, 13728);
      expect(recs.length, 1716);
      expect(asm.gaps, 0);
    });

    test('night: band sleep flag 03:22 (once), then 03:42–07:51', () {
      final asleep = [
        for (final r in recs)
          if (kindAsleep(r.kind) &&
              r.ts.isAfter(at(20, 0, day: 3)) &&
              r.ts.isBefore(at(9, 0)))
            r.ts,
      ];
      expect(asleep.first, at(3, 22));
      expect(asleep[1], at(3, 42));
      expect(asleep.last, at(7, 51));
      final inside = recs.where(
        (r) => !r.ts.isBefore(at(3, 45)) && r.ts.isBefore(at(7, 45)),
      );
      expect(inside.every((r) => r.hr != null), isTrue);
    });

    test('before the flag: still minutes with HR only every 30 min', () {
      final pre = recs.where(
        (r) => !r.ts.isBefore(at(0, 40)) && r.ts.isBefore(at(3, 20)),
      );
      expect(pre.where((r) => r.hr != null).length, lessThan(12));
      expect(pre.where((r) => kindAsleep(r.kind)), isEmpty);
    });

    test('after waking: 0x70/0x7a awake, then 0x73/0xf3 off-wrist', () {
      expect(rec(at(7, 55)).kind & 0xf0, 0x70);
      expect(kindAsleep(rec(at(7, 55)).kind), isFalse);
      expect(rec(at(7, 55)).hr, greaterThan(80));
      final off = recs.where(
        (r) => !r.ts.isBefore(at(8, 30)) && r.ts.isBefore(at(10, 30)),
      );
      expect(off.every((r) => kindNotWorn(r.kind) && r.hr == null), isTrue);
    });

    test('aux bytes 6–7 sit at 0x80 awake and move only in sleep', () {
      int b6(ActivityRecord r) => (r.aux! >> 16) & 0xff;
      expect(b6(rec(at(23, 0, day: 3))), 0x80);
      expect(b6(rec(at(5, 0))), isNot(0x80));
    });
  });
}
