// End to end on a real capture: band bytes → store → scoring → the night.
// docs/packets/android-2026-10-04T12-33-07 (Mi Band 6, V1.0.6.20).
import 'dart:convert';
import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/score_service.dart';
import 'package:tempo/src/core/stages.dart';

const capture = '../docs/packets/android-2026-10-04T12-33-07.587236Z.jsonl';

void main() {
  // 03:42 and 07:51 at UTC+5:30, the phone's zone in the capture. (A
  // lone flagged minute at 03:22 had movement and is staged awake.)
  final onset = DateTime.utc(2026, 10, 3, 22, 12);
  final wake = DateTime.utc(2026, 10, 4, 2, 21);

  late TempoDb db;
  setUp(() async {
    db = TempoDb(NativeDatabase.memory());
    final asm = ChunkAssembler();
    for (final l in File(capture).readAsLinesSync()) {
      final e = jsonDecode(l) as Map<String, dynamic>;
      if (e['dir'] == 'rx' && (e['char'] as String).contains('00000005')) {
        final h = e['hex'] as String;
        asm.add([
          for (var i = 0; i < h.length; i += 2)
            int.parse(h.substring(i, i + 2), radix: 16),
        ]);
      }
    }
    final recs = parseActivity(
      Uint8List.fromList(asm.take()),
      DateTime.utc(2026, 10, 3, 7, 57),
    );
    await db.appendMinutes([
      for (final a in recs)
        MinuteSamplesCompanion.insert(
          ts: Value(toTs(a.ts)),
          steps: a.steps,
          intensity: a.intensity,
          kind: a.kind,
          hr: Value(a.hr),
          aux: Value(a.aux),
        ),
    ]);
  });
  tearDown(() => db.close());

  test(
    'the night is the band-flagged sleep, staged, awake-in-bed excluded',
    () async {
      final rows = await db.minutesBetween(
        onset.subtract(const Duration(hours: 3)),
        wake.add(const Duration(hours: 3)),
      );
      final d = decodeMinutes(rows);
      final night = sc
          .detectSessions(d.minutes)
          .where((s) => s.end.isAfter(onset) && s.start.isBefore(wake))
          .single;
      expect(night.start.toUtc(), onset);
      // The flag runs to 07:51, but HR climbs past 85 from 07:46: awake.
      // 0x70/0x7a afterwards (HR 85–92) are awake too, not sleep.
      expect(night.end.toUtc(), wake.subtract(const Duration(minutes: 6)));
      expect(d.unstaged, isFalse);
      final deep = night.stage(sc.Stage.deep).inMinutes;
      final rem = night.stage(sc.Stage.rem).inMinutes;
      final light = night.stage(sc.Stage.light).inMinutes;
      final asleep = night.asleep.inMinutes;
      // ignore: avoid_print
      print(
        'asleep $asleep · deep $deep · REM $rem · light $light · '
        'awake ${night.inBed.inMinutes - asleep}',
      );
      expect(deep, greaterThan(0));
      expect(rem, greaterThan(0));
      expect(deep / asleep, inInclusiveRange(.08, .4));
      expect(rem / asleep, inInclusiveRange(.05, .4));
    },
  );

  test('scoring stores that night with its stages', () async {
    await ScoreService(db).recomputeFrom(DateTime(2026, 10, 3));
    final day = DateTime(
      wake.toLocal().year,
      wake.toLocal().month,
      wake.toLocal().day,
    );
    final s = (await db.scoreFor(day))!;
    expect(fromTs(s.sleepStart!).toUtc(), onset);
    expect(
      fromTs(s.sleepEnd!).toUtc(),
      wake.subtract(const Duration(minutes: 6)),
    );
    final ss = (await db.sleepEndingAt(s.sleepEnd!))!;
    final stages = (jsonDecode(ss.stages) as Map).cast<String, int>();
    expect(stages['deep'], greaterThan(0));
    expect(stages['rem'], greaterThan(0));
  });
}
