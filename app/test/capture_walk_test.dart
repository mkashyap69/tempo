// The evening walk of 6 Oct, 19:01–19:40, from the band's own per-minute
// log lines (docs/packets/band-debug-2026-10-06-evening.txt: each
// "[ALG]act=" line is the 8-byte activity minute). The explorer transfer
// in ios-2026-10-06T14-10-56 stopped at the 16:46 block edge, so the walk
// is only in the log. The band's day total then was 4379 steps, 3356 m.
import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;

const excerpt = '../docs/packets/band-debug-2026-10-06-evening.txt';

void main() {
  // [TIME]2026-10-6 19:1:58 week 2 → the act line after it is minute 19:01.
  final minutes = <sc.Minute>[];
  DateTime? at;
  for (final l in File(excerpt).readAsLinesSync()) {
    final t = RegExp(r'\[TIME\](\d+)-(\d+)-(\d+) (\d+):(\d+):\d+')
        .firstMatch(l);
    if (t != null) {
      final v = [for (var i = 1; i <= 5; i++) int.parse(t.group(i)!)];
      at = DateTime(v[0], v[1], v[2], v[3], v[4]);
      continue;
    }
    final a = RegExp(r'\[ALG\]act=([0-9a-f ]+)').firstMatch(l);
    if (a == null || at == null) continue;
    final b = [
      for (final x in a.group(1)!.trim().split(' ')) int.parse(x, radix: 16),
    ];
    final hr = b[3];
    minutes.add(
      sc.Minute(
        at,
        hr: hr == 0 || hr == 0xff ? null : hr,
        steps: b[2],
        motion: b[1],
        stage: kindAsleep(b[0])
            ? sc.Stage.light
            : kindNotWorn(b[0])
            ? sc.Stage.unknown
            : sc.Stage.wake,
        bandWalking: kindWalking(b[0]),
        offWrist: kindNotWorn(b[0]),
      ),
    );
  }

  test('175 minutes from 16:46 to 19:40', () {
    expect(minutes.length, 175);
    expect(minutes.first.ts, DateTime(2026, 10, 6, 16, 46));
    expect(minutes.last.ts, DateTime(2026, 10, 6, 19, 40));
  });

  final walk = [
    for (final m in minutes)
      if (m.bandWalking) m,
  ];

  test('the band marks exactly the 40 walk minutes', () {
    expect(walk.length, 40);
    expect(walk.first.ts, DateTime(2026, 10, 6, 19, 1));
    expect(walk.last.ts, DateTime(2026, 10, 6, 19, 40));
  });

  test('auto-detection finds one walk', () {
    final found = sc.detectActivities(minutes, hrMax: 190);
    expect(found.length, 1);
    expect(found.single.sport, sc.Sport.walking);
    expect(found.single.start, DateTime(2026, 10, 6, 19, 1));
    expect(found.single.duration.inMinutes, inInclusiveRange(38, 40));
    expect(found.single.avgHr, inInclusiveRange(110, 113));
    expect(found.single.maxHr, 129);
  });

  test('steps, cadence, distance, pace and splits', () {
    final stride = sc.strideMetres(running: false, bandStride: 3356 / 4379);
    final g = sc.gaitOf(walk, strideM: stride)!;
    expect(g.steps, 4218);
    expect(g.movingMinutes, 39); // 19:40 was the slow last minute
    expect(g.cadence, closeTo(107.3, .1));
    expect(g.peakCadence, 114);
    expect(g.running, isFalse);
    expect(g.distanceM / 1000, closeTo(3.23, .01));
    expect(g.pacePerKm!.inSeconds, inInclusiveRange(735, 750)); // ≈ 12:23
    expect(g.splits.length, 3);
    for (final s in g.splits) {
      expect(s.inSeconds, inInclusiveRange(690, 780));
    }
  });
}
