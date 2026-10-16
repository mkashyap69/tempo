import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/picks_service.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/core/today.dart';
import 'package:tempo/src/screens/coach.dart';
import 'package:tempo/src/screens/picks.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/workout_detail.dart';

import 'support/harness.dart';
import 'support/health_fake.dart';
import 'support/seed.dart';

void main() {
  test('profile keeps the games you play', () {
    const p = Profile(games: {sc.Game.badminton, sc.Game.tableTennis});
    final back = Profile.fromJson(p.toJson());
    expect(back.games, {sc.Game.badminton, sc.Game.tableTennis});
    expect(
      Profile.fromJson({
        'games': ['nope'],
      }).games,
      isEmpty,
    );
  });

  test('picks from seeded band data: three, one recommended', () async {
    final db = await seededDb(days: 30);
    final p0 = await loadAppProfile(db);
    await saveAppProfile(db, p0!.copyWith(games: {sc.Game.badminton}));
    final t = await loadToday(db);
    final picks = await loadPicks(db, t);
    expect(picks.map((p) => p.kind), [
      sc.PickKind.run,
      sc.PickKind.strength,
      sc.PickKind.play,
    ]);
    expect(picks.where((p) => p.recommended), hasLength(1));
    expect(picks[2].session.title, 'Badminton');
    for (final p in picks) {
      expect(p.session.minutes, lessThanOrEqualTo(t.profile.maxMinutes));
    }
    // Recent workouts are read: the seeded ride two days ago is there.
    final recent = await recentSessions(db, dayOf(DateTime.now()));
    expect(recent.any((r) => r.sport == sc.Sport.cycling), isTrue);
    await db.close();
  });

  test('picks on a Health source', () async {
    final db = await healthDb(nights: 20);
    final picks = await loadPicks(db, await loadToday(db));
    expect(picks, hasLength(3));
    await db.close();
  });

  group('screens', () {
    setUpAll(loadFonts);

    Future<void> render(WidgetTester t, Widget w, dynamic db) async {
      t.view.physicalSize = const Size(390, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, w));
      await settle(t);
      expect(t.takeException(), isNull);
    }

    testWidgets('Coach shows the three picks; choosing one plans it', (
      t,
    ) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      await render(t, const CoachScreen(standalone: true), db);
      expect(find.text('CHOOSE TODAY’S WORKOUT'), findsOneWidget);
      expect(find.text('Tempo’s pick'), findsOneWidget);
      expect(find.byType(PickCard), findsNWidgets(3));
      // Open the strength pick and make it today's plan.
      final strength = find.byType(PickCard).at(1);
      await t.ensureVisible(strength);
      await t.tap(strength);
      await settle(t, frames: 10);
      expect(find.text('EXERCISES'), findsWidgets);
      expect(find.textContaining(' × '), findsWidgets); // sets × reps
      await t.tap(find.text('Make it today’s plan'));
      await settle(t, frames: 10);
      expect(t.takeException(), isNull);
      final plan = (await t.runAsync(() => loadToday(db)))!.plan!;
      expect(plan.sport, sc.Sport.strength);
      expect(plan.detail, isA<sc.StrengthDetail>());
      await t.pump(const Duration(seconds: 6)); // let the toast go
      await teardown(t, db);
    });

    testWidgets('a picked plan shows what to do on the workout screen', (
      t,
    ) async {
      final db = (await t.runAsync(() async {
        final db = await seededDb(days: 30);
        final picks = await loadPicks(db, await loadToday(db));
        await CoachService(db).swapToday(picks[0].session, 'test');
        return db;
      }))!;
      await render(t, const WorkoutDetailScreen(), db);
      expect(find.text('WHAT TO DO'), findsOneWidget);
      expect(find.text('How it should feel'.toUpperCase()), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('Today has one quiet row for the picks', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      await render(t, const TodayScreen(), db);
      expect(find.text('Choose a workout'), findsOneWidget);
      await t.ensureVisible(find.text('Choose a workout'));
      await t.tap(find.text('Choose a workout'));
      await settle(t, frames: 10);
      expect(find.byType(PickCard), findsNWidgets(3));
      expect(t.takeException(), isNull);
      await teardown(t, db);
    });
  });
}
