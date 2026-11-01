import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/block_service.dart';
import 'package:tempo/src/core/body.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/limit.dart';
import 'package:tempo/src/core/manual_activity.dart';
import 'package:tempo/src/core/strength.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/core/score_service.dart';
import 'package:tempo/src/screens/add_activity.dart';
import 'package:tempo/src/screens/goal.dart';
import 'package:tempo/src/screens/today_tiles.dart';
import 'package:tempo/src/screens/week_template.dart';
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

  group('U3', () {
    test('the week template survives a round trip into the planner', () {
      const p = Profile(
        dayMinutes: {1: 30, 7: 150},
        longDay: 7,
        liftDays: {1, 4},
        hardSessions: 3,
      );
      final back = Profile.fromJson(p.toJson());
      expect(back.prefs.minutesOn(1), 30);
      expect(back.prefs.minutesOn(2), p.maxMinutes);
      expect(back.longDay, 7);
      expect(back.liftDays, {1, 4});
      expect(back.prefs.hardPerWeek, 3);
      expect(back.copyWith(hardSessions: () => null).prefs.hardPerWeek, 2);
    });

    test('an injury limits the plan from today, and ends', () async {
      final db = await bodyDb();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await saveAppProfile(
        db,
        const Profile(likes: {sc.Sport.running, sc.Sport.strength}),
      );
      await setLimit(db, sc.TrainingLimit.noRunning, on: today);
      expect(await limitOn(db, today), sc.TrainingLimit.noRunning);
      expect(
        await limitOn(db, today.subtract(const Duration(days: 1))),
        sc.TrainingLimit.none,
      );
      final rows = await CoachService(db).ensureWeek(today, rebuild: true);
      for (final r in rows) {
        if (DateTime.parse(r.date).isBefore(today)) continue;
        expect(r.session, isNot(contains('"running"')), reason: r.date);
      }
      final tomorrow = today.add(const Duration(days: 1));
      await setLimit(db, sc.TrainingLimit.none, on: tomorrow);
      expect(await limitOn(db, today), sc.TrainingLimit.noRunning);
      expect(await limitOn(db, tomorrow), sc.TrainingLimit.none);
      expect(await limitedWeek(db, mondayOf(today)), isTrue);
      await db.close();
    });

    test('saved routines replace by name', () async {
      final db = await bodyDb();
      const a = sc.Routine('Push', [
        sc.Exercise('Bench press', sets: 3, reps: '8'),
      ]);
      const b = sc.Routine('push', [
        sc.Exercise('Bench press', sets: 5, reps: '5'),
      ]);
      await saveRoutine(db, a);
      await saveRoutine(db, b);
      final rs = await loadRoutines(db);
      expect(rs.single.items.single.sets, 5);
      await deleteRoutine(db, 'push');
      expect(await loadRoutines(db), isEmpty);
      await db.close();
    });
  });

  group('U4', () {
    test('a hand-added session adds its load once', () async {
      final db = await bodyDb();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day - 1);
      final before = (await db.scoresBetween(day, day)).single.strain;
      final id = await addManualActivity(
        db,
        sport: sc.Sport.cycling,
        start: day.add(const Duration(hours: 7)),
        minutes: 60,
        rpe: 6,
      );
      final w = (await db.workoutsBetween(
        day,
        day.add(const Duration(days: 1)),
      )).firstWhere((x) => x.id == id);
      expect(w.source, 'manual');
      expect(w.rpe, 6);
      expect(w.zones, '[0,0,60,0,0]');
      final after = (await db.scoresBetween(day, day)).single.strain;
      expect(after, greaterThan(before));
      // Rescoring again doesn't add it twice.
      await ScoreService(db).recomputeFrom(day);
      expect(
        (await db.scoresBetween(day, day)).single.strain,
        closeTo(after, 1e-6),
      );
      await db.close();
    });

    testWidgets('the add-activity screen saves a ride', (t) async {
      final db = (await t.runAsync(bodyDb))!;
      final now = DateTime.now();
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harness(
          db,
          AddActivityScreen(now: DateTime(now.year, now.month, now.day, 20)),
        ),
      );
      await settle(t);
      await t.tap(find.text('Cycling'));
      await t.tap(find.text('Yesterday'));
      await settle(t);
      expect(find.textContaining('strain'), findsWidgets);
      await t.tap(find.text('Add activity'));
      await settle(t, frames: 60);
      await t.runAsync(() async {
        final ws = await db.workoutsBetween(
          DateTime(now.year, now.month, now.day - 1),
          DateTime(now.year, now.month, now.day),
        );
        expect(ws.where((w) => w.source == 'manual').single.sport, 'cycling');
      });
      await teardown(t, db);
    });
  });

  group('U5', () {
    test('race time parses and gives paces', () {
      expect(parseRaceTime('24:30'), 24 * 60 + 30);
      expect(parseRaceTime('1:45:00'), 105 * 60);
      expect(parseRaceTime('24:75'), isNull);
      expect(parseRaceTime('abc'), isNull);
      final p = const Profile().copyWith(paceRace: () => (5000.0, 1197));
      final back = Profile.fromJson(p.toJson());
      expect(back.vdot, closeTo(50, .3));
      expect(raceTimeSummary(back), '5K 19:57');
      expect(back.copyWith(paceRace: () => null).vdot, isNull);
    });
  });

  group('U6', () {
    testWidgets('Get stronger plans three lifting days and shows main lifts', (
      t,
    ) async {
      final db = (await t.runAsync(() async {
        final db = await bodyDb();
        final now = DateTime.now();
        await saveBlock(db, sc.BlockGoal.strength, now: now);
        await logSet(
          db,
          exercise: 'back_squat',
          setNo: 1,
          kg: 100,
          reps: 5,
          at: now.subtract(const Duration(hours: 2)),
        );
        return db;
      }))!;
      final rows = (await t.runAsync(
        () => CoachService(db).ensureWeek(DateTime.now()),
      ))!;
      final lifts = rows.where((r) => r.session.contains('"strength"'));
      // While calibrating the plan is general (no block); after, three
      // lifting days.
      if (rows.first.general) {
        expect(lifts.length, lessThanOrEqualTo(2));
      } else {
        expect(lifts.length, 3);
      }
      t.view.physicalSize = const Size(390, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, const GoalScreen()));
      await settle(t, frames: 40);
      expect(find.text('Get stronger'), findsWidgets);
      expect(find.text('MAIN LIFTS · ESTIMATED 1RM'), findsOneWidget);
      expect(find.text('Back squat'), findsOneWidget);
      await teardown(t, db);
    });
  });
}
