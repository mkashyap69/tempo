import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/score_service.dart';

void main() {
  late TempoDb db;
  setUp(() => db = TempoDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('raw minutes → sleep session, daily score, baselines', () async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final bed = day.subtract(const Duration(hours: 1)); // 23:00 yesterday
    final rows = <MinuteSamplesCompanion>[
      for (var i = 0; i < 8 * 60; i++)
        MinuteSamplesCompanion.insert(
          ts: Value(toTs(bed.add(Duration(minutes: i)))),
          steps: 0,
          intensity: 0,
          kind: 0xf0, // band sleep flag (V1.0.6.20)
          hr: Value(50 + i % 3),
        ),
      for (var i = 0; i < 60; i++)
        MinuteSamplesCompanion.insert(
          ts: Value(toTs(bed.add(Duration(minutes: 480 + i)))),
          steps: 100,
          intensity: 100,
          kind: 0x01,
          hr: const Value(160),
        ),
    ];
    await db.appendMinutes(rows);
    await ScoreService(db).recomputeFrom(day);

    final s = (await db.scoreFor(day))!;
    expect(s.sleptHours, 8);
    expect(s.rhr, closeTo(51, 1));
    expect(s.strain, greaterThan(0));
    expect(s.algoVersion, sc.algoVersion);
    expect(await db.sleepEndingAt(s.sleepEnd!), isNotNull);
  });

  test('HR max setting acts as floor', () async {
    await db.putSetting(hrMaxKey, '200');
    final d = DateTime.now();
    await ScoreService(db).recomputeFrom(DateTime(d.year, d.month, d.day));
    expect((await db.scoreFor(d))!.hrMax, 200);
  });
}
