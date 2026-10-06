// 5–6 Oct night and the day after, end to end
// (docs/packets/ios-2026-10-06T11-14-29, debug-log excerpt
// band-debug-2026-10-06.txt): the night ends at 09:46 rather than bridging
// the band being off the wrist, the 15:40 nap is its own sleep, and the
// stress fetch from long ago gets only the 9 empty minutes before the
// band's next block.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/sync_service.dart' show fetchAgain;

const log = '../docs/packets/ios-2026-10-06T11-14-29.977626Z.jsonl';

void main() {
  final payloads = <int, ChunkAssembler>{};
  final replies = <int, List<int>>{};
  int? cur;
  List<int> bytes(String h) => [
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ];
  for (final l in File(log).readAsLinesSync()) {
    final e = jsonDecode(l) as Map<String, dynamic>;
    final c = (e['char'] as String?) ?? '';
    final h = (e['hex'] as String?) ?? '';
    if (e['dir'] == 'tx' && c.contains('00000004') && h.startsWith('01')) {
      cur = int.parse(h.substring(2, 4), radix: 16);
    } else if (cur != null && e['dir'] == 'rx' && c.contains('00000004')) {
      if (h.startsWith('1001')) replies[cur] = bytes(h);
    } else if (cur != null && e['dir'] == 'rx' && c.contains('00000005')) {
      payloads.putIfAbsent(cur, ChunkAssembler.new).add(bytes(h));
    }
  }
  final cache = <int, Uint8List>{};
  Uint8List data(int code) => cache[code] ??= payloads[code]!.take();

  // Fetch reply: 2026-10-05 17:58 at +5:30.
  final start = DateTime.utc(2026, 10, 5, 12, 28);
  List<sc.Minute> minutes() => [
    for (final r in parseActivity(data(0x01), start))
      sc.Minute(
        r.ts,
        hr: r.hr,
        steps: r.steps,
        motion: r.intensity,
        stage: kindAsleep(r.kind)
            ? sc.Stage.light
            : kindNotWorn(r.kind)
            ? sc.Stage.unknown
            : sc.Stage.wake,
        bandWalking: kindWalking(r.kind),
        offWrist: kindNotWorn(r.kind),
      ),
  ];

  test('1367 activity minutes, 17:58 to 16:44', () {
    expect(data(0x01).length, 1367 * activityRecordSize);
  });

  test('night 00:07–09:46 and a 46-min nap at 15:40', () {
    final s = sc.detectSessions(
      minutes(),
      const sc.SleepParams(minSessionMinutes: 20),
    );
    expect(s.length, 2);
    // 00:07 → 09:46 local (+5:30). It used to run to 10:24, bridging
    // 17 min off the wrist.
    expect(s.first.start.toUtc(), DateTime.utc(2026, 10, 5, 18, 37));
    expect(s.first.end.toUtc(), DateTime.utc(2026, 10, 6, 4, 16));
    expect(s.last.start.toUtc(), DateTime.utc(2026, 10, 6, 10, 10));
    expect(s.last.end.toUtc(), DateTime.utc(2026, 10, 6, 10, 56));
    expect(s.last.asleep.inMinutes, 46);
  });

  test('the nap is listed for the day and counted in napHours', () {
    // Score the local day the night ends on.
    final wake = DateTime.utc(2026, 10, 6, 4, 16).toLocal();
    final day = DateTime(wake.year, wake.month, wake.day);
    final s = sc.daySleep(date: day, minutes: minutes());
    expect(s.night!.end.toUtc(), DateTime.utc(2026, 10, 6, 4, 16));
    expect(s.naps.length, 1);
    expect(s.naps.single.asleep.inMinutes, 46);
    expect(
      sc.scoreDay(date: day, minutes: minutes()).napHours,
      closeTo(46 / 60, 1e-9),
    );
  });

  test('stress from long ago stops at the band block edge (17:58)', () {
    final r = FetchStartReply.parse(replies[0x13]!)!;
    expect(r.count, 9);
    expect(r.start!.toUtc(), DateTime.utc(2026, 10, 5, 12, 19));
    expect(data(0x13), List.filled(9, 0xff));
    expect(parseStress(data(0x13), r.start!), isEmpty);
    // So the sync fetches again from 17:58.
    final last = r.start!.add(const Duration(minutes: 8));
    expect(
      fetchAgain(FetchType.stress, null, last, DateTime.utc(2026, 10, 6, 11)),
      isTrue,
    );
  });

  test('fetchAgain stops when caught up or not moving', () {
    final now = DateTime.utc(2026, 10, 6, 11);
    final c = now.subtract(const Duration(hours: 2));
    expect(fetchAgain(FetchType.stress, c, now, now), isFalse);
    expect(fetchAgain(FetchType.stress, c, c, now), isFalse);
    expect(fetchAgain(FetchType.stress, c, null, now), isFalse);
    expect(
      fetchAgain(
        FetchType.spo2Minutes,
        c,
        c.add(const Duration(hours: 1)),
        now,
      ),
      isFalse,
    );
    expect(
      fetchAgain(FetchType.activity, c, c.add(const Duration(hours: 1)), now),
      isTrue,
    );
  });
}
