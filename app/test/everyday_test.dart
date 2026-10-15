import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/everyday.dart';
import 'package:tempo/src/screens/everyday_cards.dart';
import 'package:tempo/src/screens/recovery.dart';
import 'package:tempo/src/screens/sleep.dart';
import 'package:tempo/src/screens/strain.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/trends.dart';

import 'support/harness.dart';
import 'support/health_fake.dart';
import 'support/seed.dart';

void main() {
  group('loaders', () {
    test('band: rhythm, signals and movement from seeded data', () async {
      final db = await seededDb(days: 30);
      final r = await loadRhythm(db);
      expect(r.sri, isNotNull);
      expect(r.sri!, greaterThan(50));
      final b = await loadBodySignals(db);
      expect(b.readings.map((x) => x.key), containsAll(['rhr', 'stress']));
      expect(b.readings.map((x) => x.key), isNot(contains('resp')));
      expect(b.level, isNot(sc.BodyLevel.learning));
      final m = await loadMovement(db);
      expect(m.watchOnly, isFalse);
      expect(m.brisk, greaterThanOrEqualTo(0));
      await db.close();
    });

    test('Health: HRV and breathing rate signals, rhythm', () async {
      final db = await healthDb(nights: 20);
      final b = await loadBodySignals(db);
      final keys = b.readings.map((x) => x.key);
      expect(keys, containsAll(['rhr', 'hrv', 'resp', 'spo2']));
      expect(keys, isNot(contains('stress')));
      // The fake watch writes no breathing rate yet.
      expect(
        b.readings.firstWhere((x) => x.key == 'resp').state,
        sc.SignalState.learning,
      );
      expect((await loadRhythm(db)).sri, isNotNull);
      await db.close();
    });

    test('several signals off on one night', () async {
      final db = await seededDb(days: 30);
      final today = dayOf(DateTime.now());
      final s = (await db.scoreFor(today))!;
      await db.upsertScore(
        s
            .toCompanion(true)
            .copyWith(
              rhr: Value((s.rhr ?? 55) + 15),
              hrvProxy: Value((s.hrvProxy ?? 30) + 40),
            ),
      );
      final b = await loadBodySignals(db);
      expect(b.level, sc.BodyLevel.rest);
      expect(b.off.map((x) => x.key), containsAll(['rhr', 'stress']));
      await db.close();
    });

    test('recovery after a workout uses measured minutes only', () async {
      final db = TempoDb(NativeDatabase.memory());
      final end = DateTime(2026, 9, 1, 18, 40);
      final hrs = {-3: 160, -2: 170, -1: 168, 0: 150, 1: 140, 2: 134};
      await db.appendMinutes([
        for (final e in hrs.entries)
          MinuteSamplesCompanion.insert(
            ts: Value(toTs(end.add(Duration(minutes: e.key)))),
            steps: 0,
            intensity: 0,
            kind: 1,
            hr: Value(e.value),
          ),
      ]);
      final id = await db.addWorkout(
        WorkoutsCompanion.insert(
          start: toTs(end.subtract(const Duration(minutes: 40))),
          end: toTs(end),
          title: 'Run',
          source: 'live',
          strain: 5,
          trimp: 50,
          zones: '[0,0,0,0,0]',
        ),
      );
      final w = (await db.workout(id))!;
      expect(await workoutRecovery(db, w, 190), 36);
      expect(await workoutRecovery(db, w, 250), isNull); // not hard enough
      await db.close();
    });
  });

  group('screens', () {
    setUpAll(loadFonts);

    Future<void> render(WidgetTester t, TempoDb db, Widget w) async {
      t.view.physicalSize = const Size(390, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, w));
      await settle(t);
      expect(t.takeException(), isNull);
    }

    for (final health in [false, true]) {
      final name = health ? 'Health' : 'band';
      testWidgets('Sleep shows Rhythm ($name)', (t) async {
        final db = (await t.runAsync(
          () => health ? healthDb(nights: 20) : seededDb(days: 30),
        ))!;
        await render(t, db, const SleepScreen());
        expect(find.text('Rhythm'), findsOneWidget);
        expect(find.textContaining('/100 regularity'), findsOneWidget);
        await teardown(t, db);
      });

      testWidgets('Recovery shows body signals ($name)', (t) async {
        final db = (await t.runAsync(
          () => health ? healthDb(nights: 20) : seededDb(days: 30),
        ))!;
        await render(t, db, const RecoveryScreen());
        expect(find.text('BODY SIGNALS · LAST NIGHT'), findsOneWidget);
        expect(find.text('Resting heart rate'), findsWidgets);
        expect(
          find.text(health ? 'Breathing rate' : 'Overnight stress'),
          findsOneWidget,
        );
        await teardown(t, db);
      });

      testWidgets('Strain shows movement ($name)', (t) async {
        final db = (await t.runAsync(
          () => health ? healthDb(nights: 20) : seededDb(days: 30),
        ))!;
        await render(t, db, const StrainScreen());
        expect(find.text('Movement today'), findsOneWidget);
        expect(find.text('Brisk minutes'), findsOneWidget);
        await teardown(t, db);
      });

      testWidgets('Trends shows brisk minutes ($name)', (t) async {
        final db = (await t.runAsync(
          () => health ? healthDb(nights: 20) : seededDb(days: 30),
        ))!;
        await render(t, db, const TrendsScreen());
        expect(find.textContaining('Brisk minutes'), findsWidgets);
        await teardown(t, db);
      });
    }

    testWidgets('Today stays quiet on a normal night', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      await render(t, db, const TodayScreen());
      expect(find.text('Body signals are off'), findsNothing);
      await teardown(t, db);
    });

    testWidgets('Today flags several signals off together', (t) async {
      final db = (await t.runAsync(() async {
        final db = await seededDb(days: 30);
        final today = dayOf(DateTime.now());
        final s = (await db.scoreFor(today))!;
        await db.upsertScore(
          s
              .toCompanion(true)
              .copyWith(
                rhr: Value((s.rhr ?? 55) + 15),
                hrvProxy: Value((s.hrvProxy ?? 30) + 40),
              ),
        );
        return db;
      }))!;
      await render(t, db, const TodayScreen());
      expect(find.text('Body signals are off'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('activity shows heart-rate recovery when measured', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      final ws = await t.runAsync(
        () => db.workoutsBetween(DateTime(2000), DateTime(2100)),
      );
      expect(ws, isNotEmpty);
      await render(t, db, RecoveryHrCard(workoutId: ws!.first.id));
      expect(t.takeException(), isNull);
      await teardown(t, db);
    });
  });
}
