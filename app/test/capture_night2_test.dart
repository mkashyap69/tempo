// The night of 5–6 Oct end to end (docs/packets/ios-2026-10-06T02-51-37):
// one night despite a quiet 31-minute wake, deep in the first half, flat
// SpO₂ plateaus left out of breathing, and the evening walk named by the
// band's own walking code.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;

const log = '../docs/packets/ios-2026-10-06T02-51-37.742974Z.jsonl';

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
      ),
  ];

  test('one night: 00:07–08:18 with the quiet wake at 05:28 inside', () {
    final s = sc.detectSessions(
      minutes(),
      const sc.SleepParams(minSessionMinutes: 20),
    );
    expect(s.length, 1);
    expect(s.single.start.toUtc(), DateTime.utc(2026, 10, 5, 18, 37));
    expect(s.single.end.toUtc(), DateTime.utc(2026, 10, 6, 2, 49));
    expect(s.single.asleep.inMinutes, inInclusiveRange(440, 445));
  });

  test('deep sleep sits in the first half of the night', () {
    final s = sc.detectSessions(minutes()).single;
    final staged = sc.stageSleep(s.minutes).minutes;
    final mid = s.start.add(s.end.difference(s.start) ~/ 2);
    final deep = staged.where((m) => m.stage == sc.Stage.deep);
    final early = deep.where((m) => m.ts.isBefore(mid)).length;
    expect(early, greaterThan(deep.length - early));
  });

  test('flat SpO₂ plateaus are left out; the score is fair, not poor', () {
    final s = sc.detectSessions(minutes()).single;
    final n = sc.breathingNight(
      start: s.start,
      end: s.end,
      sleptHours: s.asleep.inMinutes / 60,
      spo2: [
        for (final m in parseSpo2Minutes(data(0x26)))
          (ts: m.ts, avg: m.avg, quality: m.quality),
      ],
      events: [
        for (final e in parseOdEvents(data(0x27))) (ts: e.ts, drop: e.drop),
      ],
    )!;
    // ignore: avoid_print
    print(
      'breathing ${n.score} · ${n.eventsPerHour.toStringAsFixed(1)}/h · '
      'avg ${n.avgSpo2.toStringAsFixed(1)} · artifact ${n.artifactMinutes} min',
    );
    expect(n.artifactMinutes, inInclusiveRange(100, 130));
    expect(n.belowNinety, lessThan(.02));
    // Mi Fitness, same band and night: "Breathing score 79".
    expect(n.score, inInclusiveRange(76, 82));
  });

  test('the evening walk is walking, from the band\'s own code', () {
    final w = sc.detectActivities(minutes(), hrMax: 175);
    final walk = w.firstWhere((a) => a.duration.inMinutes > 40);
    expect(walk.sport, sc.Sport.walking);
    expect(walk.start.toUtc(), DateTime.utc(2026, 10, 5, 13, 9)); // 18:39
  });

  test('stages and wake match Mi Fitness\'s shares for the night', () {
    // Mi Fitness 6 Oct: 9 h 41 m, deep 13 %, REM 14 %, light 73 %,
    // 1 wake-up of 1 min. Our data stops at the 08:18 sync.
    final s = sc.detectSessions(minutes()).single;
    final staged = sc.stageSleep(s.minutes).minutes;
    int count(sc.Stage x) => staged.where((m) => m.stage == x).length;
    final asleep =
        count(sc.Stage.light) + count(sc.Stage.deep) + count(sc.Stage.rem);
    // ignore: avoid_print
    print(
      'deep ${(100 * count(sc.Stage.deep) / asleep).round()} % · '
      'REM ${(100 * count(sc.Stage.rem) / asleep).round()} % · '
      'wake ${count(sc.Stage.wake)} min',
    );
    expect(count(sc.Stage.deep) / asleep, inInclusiveRange(.10, .18));
    expect(count(sc.Stage.rem) / asleep, inInclusiveRange(.10, .20));
    // Was 59 before quiet flagged-awake minutes were staged; Mi Fitness
    // counts almost none, Tempo keeps the restless ones (HR up, moving).
    expect(count(sc.Stage.wake), lessThan(40));
  });
}
