// End to end on the explorer v2 log: band bytes → parsers → breathing
// score for the night of 4–5 Oct (docs/packets/ios-2026-10-05T10-48-50).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;

const log = '../docs/packets/ios-2026-10-05T10-48-50.229864Z.jsonl';

void main() {
  final payloads = <int, ChunkAssembler>{};
  int? cur;
  for (final l in File(log).readAsLinesSync()) {
    final e = jsonDecode(l) as Map<String, dynamic>;
    final c = (e['char'] as String?) ?? '';
    final h = (e['hex'] as String?) ?? '';
    if (e['dir'] == 'tx' && c.contains('00000004') && h.startsWith('01')) {
      cur = int.parse(h.substring(2, 4), radix: 16);
    } else if (cur != null && e['dir'] == 'rx' && c.contains('00000005')) {
      payloads.putIfAbsent(cur, ChunkAssembler.new).add([
        for (var i = 0; i < h.length; i += 2)
          int.parse(h.substring(i, i + 2), radix: 16),
      ]);
    }
  }
  Uint8List data(int code) => payloads[code]!.take();

  test('night of 4–5 Oct: band sleep flag, SpO₂ and dips scored', () {
    final act = parseActivity(
      data(0x01),
      DateTime.utc(2026, 10, 3, 7, 57), // 13:27 at +5:30
    );
    final night = act
        .where(
          (r) =>
              kindAsleep(r.kind) &&
              r.ts.isAfter(DateTime.utc(2026, 10, 4, 14)) &&
              r.ts.isBefore(DateTime.utc(2026, 10, 5, 6)),
        )
        .toList();
    final a = night.first.ts, b = night.last.ts;
    // Sleep assist on since the settings write: the flag starts 23:08.
    expect(a.toUtc(), DateTime.utc(2026, 10, 4, 17, 38));
    final spo2 = parseSpo2Minutes(data(0x26));
    final events = parseOdEvents(data(0x27));
    final n = sc.breathingNight(
      start: a,
      end: b,
      sleptHours: night.length / 60,
      spo2: [for (final m in spo2) (ts: m.ts, avg: m.avg, quality: m.quality)],
      events: [for (final e in events) (ts: e.ts, drop: e.drop)],
    )!;
    // ignore: avoid_print
    print(
      'breathing ${n.score} (${n.label}) · ${n.eventsPerHour.toStringAsFixed(1)}/h · '
      'avg ${n.avgSpo2.toStringAsFixed(1)} · lowest ${n.lowestSpo2} · '
      '<90 ${(n.belowNinety * 100).toStringAsFixed(1)} % · ${n.minutes} min',
    );
    expect(n.events, 115);
    expect(n.avgSpo2, inInclusiveRange(93, 96));
    expect(n.lowestSpo2, inInclusiveRange(80, 90));
    expect(n.score, inInclusiveRange(55, 85));
  });
}
