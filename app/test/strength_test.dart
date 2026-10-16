import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/strength.dart';
import 'package:tempo/src/screens/strength_log.dart';

import 'support/harness.dart';
import 'support/seed.dart';

Future<void> render(
  WidgetTester t,
  TempoDb db,
  Widget w, {
  double h = 2400,
}) async {
  t.view.physicalSize = Size(390, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(harness(db, w));
  await settle(t);
  expect(t.takeException(), isNull);
}

void main() {
  final today = dayOf(DateTime.now());
  DateTime ago(int days, [int h = 18]) =>
      today.subtract(Duration(days: days)).add(Duration(hours: h));

  test('history, next weights and freshness from logged sets', () async {
    final db = TempoDb(NativeDatabase.memory());
    for (var i = 0; i < 3; i++) {
      await logSet(
        db,
        exercise: 'back_squat',
        setNo: i + 1,
        kg: 80,
        reps: 8,
        rir: 2,
        at: ago(3).add(Duration(minutes: i * 3)),
      );
    }
    final h = await exerciseHistory(db, 'back_squat');
    expect(h.single.topKg, 80);
    final xs = await withTargets(db, [
      const sc.Exercise('Back squat', sets: 3, reps: '6–8'),
      const sc.Exercise('Plank', sets: 2, reps: '30 s'),
    ], sc.LiftDay.normal);
    expect(xs.first.kg, 82.5);
    expect(xs.first.target, contains('Up'));
    expect(xs.last.kg, isNull);
    final f = (await loadFreshness(db))!;
    expect(f[sc.Muscle.quads]!, lessThan(f[sc.Muscle.biceps]!));
    await db.close();
  });

  test('no sets lately: no freshness (picks fall back)', () async {
    final db = TempoDb(NativeDatabase.memory());
    expect(await loadFreshness(db), isNull);
    await db.close();
  });

  test('sets outside a workout still add strain load', () async {
    final db = TempoDb(NativeDatabase.memory());
    final d = today.subtract(const Duration(days: 1));
    for (var i = 0; i < 10; i++) {
      await logSet(
        db,
        exercise: 'bench_press',
        setNo: i + 1,
        kg: 60,
        reps: 8,
        at: d.add(Duration(hours: 18, minutes: i * 3)),
      );
    }
    expect(await strengthExtraTrimp(db, d), closeTo(16, 1e-9));
    // Inside a strength workout with HR load already 10: adds the rest.
    await db.addWorkout(
      WorkoutsCompanion.insert(
        start: toTs(d.add(const Duration(hours: 17, minutes: 55))),
        end: toTs(d.add(const Duration(hours: 18, minutes: 40))),
        sport: Value(sc.Sport.strength.name),
        title: 'Strength',
        source: 'live',
        confirmed: const Value(true),
        strain: 2,
        trimp: 10,
        zones: '[0,0,0,0,0]',
      ),
    );
    expect(await strengthExtraTrimp(db, d), closeTo(6, 1e-9));
    await db.close();
  });

  test('plates a side', () {
    expect(platesFor(100), [25, 15]);
    expect(platesFor(62.5), [20, 1.25]);
    expect(platesFor(20), isEmpty);
  });

  testWidgets('log screen: a plan, tick a set, rest starts, finish saves', (
    t,
  ) async {
    final db = (await t.runAsync(() => seededDb(days: 3)))!;
    final plan = sc.sessionTemplate('strength_lower');
    final s = sc.Session(
      key: plan.key,
      title: 'Lower body',
      sport: plan.sport,
      segments: plan.segments,
      strainLo: plan.strainLo,
      strainHi: plan.strainHi,
      intensity: plan.intensity,
      detail: sc.strengthDetail(sc.StrengthFocus.lower, sc.Goal.fitness, 2),
    );
    await render(t, db, StrengthLogScreen(plan: s));
    expect(find.text('Back squat'), findsOneWidget);
    expect(find.text('Romanian deadlift'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Done set 1').first);
    await settle(t);
    expect(find.textContaining('Rest '), findsOneWidget);
    final sets = await t.runAsync(
      () => db.strengthSetsBetween(today, today.add(const Duration(days: 1))),
    );
    expect(sets!.single.exercise, 'back_squat');
    await t.tap(find.text('Finish'));
    await settle(t, frames: 40);
    final ws = await t.runAsync(
      () => db.workoutsBetween(today, today.add(const Duration(days: 1))),
    );
    expect(ws!.any((w) => w.sport == 'strength'), isTrue);
    await teardown(t, db);
  });

  testWidgets('library search and history screen render', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 2)))!;
    await render(t, db, const ExercisePickerScreen());
    await t.enterText(find.byType(EditableText), 'deadlift');
    await settle(t);
    expect(find.text('Romanian deadlift'), findsOneWidget);
    await render(t, db, ExerciseHistoryScreen(sc.exerciseById['back_squat']!));
    expect(find.text('Two sessions are needed for a line.'), findsOneWidget);
    await teardown(t, db);
  });
}
