// Golden: Band explorer v2 run, docs/packets/ios-2026-10-05T10-48-50.229864Z
// (Mi Band 6, V1.0.6.20, +5:30), checked against the band's own debug log
// lines in docs/packets/band-debug-2026-10-05.txt.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

const log = '../../docs/packets/ios-2026-10-05T10-48-50.229864Z.jsonl';
const debug = '../../docs/packets/band-debug-2026-10-05.txt';

/// Payload and start reply per probed type code.
Map<int, (Uint8List, FetchStartReply?)> transfers() {
  final out = <int, ChunkAssembler>{};
  final replies = <int, FetchStartReply?>{};
  int? cur;
  for (final l in File(log).readAsLinesSync()) {
    final e = jsonDecode(l) as Map<String, dynamic>;
    final c = (e['char'] as String?) ?? '';
    final h = (e['hex'] as String?) ?? '';
    List<int> b() => [
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ];
    if (e['dir'] == 'tx' && c.contains('00000004') && h.startsWith('01')) {
      cur = int.parse(h.substring(2, 4), radix: 16);
    } else if (cur != null && e['dir'] == 'rx' && c.contains('00000004')) {
      replies[cur] ??= FetchStartReply.parse(b());
    } else if (cur != null && e['dir'] == 'rx' && c.contains('00000005')) {
      out.putIfAbsent(cur, ChunkAssembler.new).add(b());
    }
  }
  return {for (final e in out.entries) e.key: (e.value.take(), replies[e.key])};
}

int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  final t = transfers();
  final dbg = File(debug).readAsStringSync();

  test('0x13 is all-day stress: equals every [STRESS SYNC] line', () {
    final (data, reply) = t[0x13]!;
    expect(data.length, 3052);
    expect(reply!.count, 3052);
    final start = reply.start!;
    final byMinute = {
      for (var i = 0; i < data.length; i++) unix(start) + 60 * i: data[i],
    };
    final lines = RegExp(r'\[STRESS SYNC\] allday stress:(\d+) time:(\d+)')
        .allMatches(dbg)
        .toList();
    expect(lines, hasLength(586));
    for (final m in lines) {
      final ts = int.parse(m[2]!);
      expect(byMinute[ts - ts % 60], int.parse(m[1]!), reason: '$ts');
    }
    final parsed = parseStress(data, start);
    expect(parsed.every((r) => r.value >= 1 && r.value <= 100), isTrue);
  });

  test('0x26 is per-minute SpO₂: avg equals CurAveSpoPerMin', () {
    final mins = parseSpo2Minutes(t[0x26]!.$1);
    expect(mins, hasLength(766));
    final byTs = {for (final m in mins) unix(m.ts): m};
    // Each CurAveSpoPerMin line is followed by its [TIME] line.
    final pairs = RegExp(
      r'CurAveSpoPerMin (\d+)[\s\S]*?\[TIME\](\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)',
    ).allMatches(dbg);
    var compared = 0, equal = 0;
    for (final p in pairs) {
      final v = int.parse(p[1]!);
      if (v == 0) continue; // logged as 0: no reading
      final local = DateTime.utc(
        int.parse(p[2]!),
        int.parse(p[3]!),
        int.parse(p[4]!),
        int.parse(p[5]!),
        int.parse(p[6]!),
        int.parse(p[7]!),
      ).subtract(const Duration(hours: 5, minutes: 30));
      final m = byTs[unix(local)];
      if (m == null) continue;
      compared++;
      if (m.avg == v) equal++;
    }
    expect(compared, greaterThan(150));
    expect(equal / compared, greaterThan(.95));
    expect(mins.first.ts.toUtc(), DateTime.utc(2026, 10, 3, 22, 20, 58));
    expect(mins.first.samples, hasLength(12));
  });

  test('0x27 is desaturation events: time and drop match the debug log', () {
    final events = parseOdEvents(t[0x27]!.$1);
    expect(events, hasLength(131));
    final byTs = {for (final e in events) unix(e.ts): e};
    final logged = RegExp(r'store_od_event time=(\d+),descend=(\d+)')
        .allMatches(dbg)
        .toList();
    expect(logged, hasLength(39));
    for (final m in logged) {
      final e = byTs[int.parse(m[1]!)];
      expect(e, isNotNull, reason: m[0]);
      expect(e!.drop, int.parse(m[2]!));
    }
    final e = events[61];
    expect(e.spo2, hasLength(240));
    expect(e.hr, hasLength(240));
    final spo2 = e.spo2.where((v) => v > 0);
    final hr = e.hr.where((v) => v > 1);
    expect(spo2.every((v) => v >= 70 && v <= 100), isTrue);
    expect(hr.every((v) => v >= 35 && v <= 120), isTrue);
  });
}
