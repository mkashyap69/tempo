import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/body.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/screens/today_tiles.dart';
import 'package:tempo/src/screens/trends.dart' show bucketed;

import 'support/harness.dart';
import 'support/health_fake.dart';

/// A Health reader that also has weight, body fat and period days (U2).
class _BodyReader extends FakeReader {
  _BodyReader(super.records);
  @override
  Set<HealthKind> get kinds => {
    ...super.kinds,
    HealthKind.weight,
    HealthKind.bodyFat,
    HealthKind.menstruation,
  };
}

Future<TempoDb> bodyDb() async {
  final db = TempoDb(NativeDatabase.memory());
  await saveAppProfile(db, const Profile(male: false));
  await db.putSetting(Keys.onboarded, '1');
  await saveDataSource(db, DataSource.healthConnect);
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  DateTime ago(int d, [int h = 7]) =>
      DateTime(d0.year, d0.month, d0.day - d, h);
  await HealthSyncService(
    db,
    reader: _BodyReader([
      ...watchData(14),
      for (var i = 28; i <= 34; i++) rec(HealthKind.weight, ago(i), 72),
      for (var i = 0; i <= 6; i++) rec(HealthKind.weight, ago(i), 70.5),
      rec(HealthKind.bodyFat, ago(1), 24),
      for (final s in [52, 24])
        for (var i = 0; i < 4; i++)
          rec(HealthKind.menstruation, ago(s - i, 0), 2),
    ]),
    useLock: false,
  ).run();
  await CoachService(db).ensureWeek(now);
  return db;
}

/// U1–U6 (docs/decisions.md, 2026-11-01): the user-review improvements.
void main() {
  group('U1', () {
    test('step goal: default by age, your own survives a round trip', () {
      expect(const Profile(age: 40).effectiveStepGoal, 8000);
      expect(const Profile(age: 65).effectiveStepGoal, 6000);
      final p = const Profile(age: 40).copyWith(stepGoal: () => 12000);
      expect(Profile.fromJson(p.toJson()).effectiveStepGoal, 12000);
      expect(p.copyWith(stepGoal: () => null).effectiveStepGoal, 8000);
    });

    test('long trends fold days into weekly means, skipping gaps', () {
      final days = <double?>[
        for (var i = 0; i < 14; i++) i < 7 ? 10 : (i.isEven ? null : 20),
      ];
      expect(bucketed(days, 7), [10, 20]);
      expect(bucketed([null, null, 4], 2), [null, 4]);
    });
  });

  group('U2', () {
    test('weight trend, body fat and the cycle from Health', () async {
      final db = await bodyDb();
      final w = (await loadWeightTrend(db))!;
      expect(w.weekMean, closeTo(70.5, 1e-9));
      expect(w.change4w, closeTo(-1.5, 1e-9));
      expect(await latestBodyFat(db), 24);
      final c = (await loadCycle(db))!;
      expect(c.day, 25);
      expect(c.typicalLength, isNull); // one full cycle seen
      await db.close();
    });

    testWidgets('Today shows weight and cycle tiles', (t) async {
      final db = (await t.runAsync(bodyDb))!;
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harness(db, const SingleChildScrollView(child: TodayTiles())),
      );
      await settle(t, frames: 40);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.textContaining('70.5', findRichText: true), findsWidgets);
      expect(find.textContaining('▼ 1.5 in 4 weeks · 24% fat'), findsOneWidget);
      expect(find.text('Cycle'), findsOneWidget);
      expect(find.textContaining('Day 25', findRichText: true), findsWidgets);
      await teardown(t, db);
    });
  });
}
