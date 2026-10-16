import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/screens/activity_detail.dart';
import 'package:tempo/src/screens/today.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// Fixes from the 16 Oct screenshots: a game showed pace and a 71-minute
/// "km split"; a finished workout kept its full card with a play button.
void main() {
  setUpAll(loadFonts);

  Future<void> render(WidgetTester t, TempoDb db, Widget w) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, w));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  testWidgets('a game has no pace and cadence card', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 10)))!;
    final ws = (await t.runAsync(
      () => db.workoutsBetween(DateTime(2000), DateTime(2100)),
    ))!;
    // Retag a seeded walk or run as a game: same steps, no pace.
    final onFoot = ws.firstWhere(
      (w) => w.sport == 'walking' || w.sport == 'running',
    );
    await render(t, db, ActivityDetailScreen(id: onFoot.id));
    expect(find.text('Pace & cadence'), findsOneWidget);
    await teardown(t, db);

    final db2 = (await t.runAsync(() => seededDb(days: 10)))!;
    final w2 = (await t.runAsync(
      () => db2.workoutsBetween(DateTime(2000), DateTime(2100)),
    ))!.firstWhere((w) => w.sport == 'walking' || w.sport == 'running');
    await t.runAsync(
      () => db2.updateWorkout(
        w2.id,
        const WorkoutsCompanion(
          sport: Value('sport'),
          title: Value('Badminton'),
        ),
      ),
    );
    await render(t, db2, ActivityDetailScreen(id: w2.id));
    expect(find.text('Pace & cadence'), findsNothing);
    await teardown(t, db2);
  });

  testWidgets('a finished session is one line on Today', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      final day = dayOf(DateTime.now());
      await CoachService(db).ensureWeek(day);
      await CoachService(db).swapToday(sc.sessionTemplate('easy_run'), 'test');
      await db.setPlanIntent(day, sc.Intent.done.name, source: 'user');
      return db;
    }))!;
    await render(t, db, const TodayScreen());
    expect(find.text('Easy run · done'), findsOneWidget);
    expect(find.text('SUGGESTED FOR TODAY'), findsNothing);
    expect(find.text('Choose a workout'), findsNothing);
    await teardown(t, db);
  });
}
