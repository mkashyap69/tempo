import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/pause.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/core/today.dart';
import 'package:tempo/src/design/components.dart' show TempoPage;
import 'package:tempo/src/screens/highlight.dart';
import 'package:tempo/src/screens/sleep.dart' show TonightCard;
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/today_parts.dart' show showPauseSheet;
import 'package:tempo/src/screens/weekly_review.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// The user flow (docs/research/User flow and journey.md): one voice, one
/// insight a day, a rest day with "not today", and the Monday review.
void main() {
  setUpAll(loadFonts);

  Future<void> render(WidgetTester t, TempoDb db, Widget w) async {
    t.view.physicalSize = const Size(390, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, w));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  /// Seeded data with last night's resting HR well above usual.
  Future<TempoDb> illDb() async {
    final db = await seededDb(days: 30);
    final s = (await db.scoreFor(dayOf(DateTime.now())))!;
    await db.upsertScore(
      s
          .toCompanion(true)
          .copyWith(
            rhr: Value((s.rhr ?? 55) + 15),
            hrvProxy: Value((s.hrvProxy ?? 30) + 40),
          ),
    );
    return db;
  }

  test(
    'one voice: the state outranks the number, the target follows',
    () async {
      final db = await illDb();
      final t = await loadToday(db);
      expect(t.rhrFlag, sc.RhrFlag.illness);
      expect(t.state, sc.DayState.rest);
      expect(t.target.cap, isTrue);
      expect(t.restDay, isTrue);
      final call = callFor(t);
      expect(call.reason, sc.CallReason.illness);
      expect(call.text, isNot(contains('primed')));
      await db.close();
    },
  );

  testWidgets('a rest day is the call, no pause box on the page', (t) async {
    final db = (await t.runAsync(illDb))!;
    await render(t, db, const TodayScreen());
    expect(find.textContaining('Take it easy today.'), findsOneWidget);
    expect(find.text('Body signals are off'), findsOneWidget);
    expect(find.text('Not today?'), findsNothing);
    expect(find.textContaining('Pause the plan'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('the pause sheet (from + and You) closes or pauses', (t) async {
    final db = (await t.runAsync(illDb))!;
    await render(
      t,
      db,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPauseSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // Closing the sheet is the "no": nothing changes.
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('Not today?'), findsOneWidget);
    await t.tapAt(const Offset(195, 40));
    await settle(t);
    expect(find.text('Not today?'), findsNothing);
    expect(activePause((await t.runAsync(() => loadPauses(db)))!), isNull);
    // Pausing.
    await t.tap(find.text('open'));
    await settle(t);
    await t.tap(find.text('Pause the plan'));
    await settle(t);
    final pauses = (await t.runAsync(() => loadPauses(db)))!;
    expect(activePause(pauses)?.reason, PauseReason.ill);
    expect(find.text('Not today?'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('a rest evening is tonight and the call', (t) async {
    testHour = 22;
    addTearDown(() => testHour = 9);
    final db = (await t.runAsync(illDb))!;
    await render(t, db, const TodayScreen());
    expect(find.text('TONIGHT'), findsOneWidget);
    expect(find.text('Start easy walk'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('today\'s insight is logged once and stays for the day', (
    t,
  ) async {
    if (DateTime.now().weekday == DateTime.monday) return; // the review day
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayInsightCard());
    expect(find.text('TODAY’S INSIGHT'), findsOneWidget);
    final first = (await t.runAsync(() => loadInsightLog(db)))!;
    expect(first, hasLength(1));
    await t.pumpWidget(const SizedBox());
    await render(t, db, const TodayInsightCard());
    final again = (await t.runAsync(() => loadInsightLog(db)))!;
    expect(again, hasLength(1));
    expect(find.text(first.single.title), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('last week\'s review confirms this week\'s plan', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    final mon = mondayOf(DateTime.now()).subtract(const Duration(days: 7));
    await render(t, db, WeeklyReviewScreen(monday: mon));
    expect(find.text('Week in review'), findsOneWidget);
    expect(find.text('YOUR WEEK IN THREE LINES'), findsOneWidget);
    await t.ensureVisible(find.text('Looks good'));
    await t.tap(find.text('Looks good'));
    await settle(t);
    final ok = await t.runAsync(() => db.setting(Keys.weekPlanOk));
    expect(ok, isNotNull);
    expect(find.textContaining('Week set.'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('wellbeing reads energy and effort, without strain numbers', (
    t,
  ) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      final p = await loadAppProfile(db);
      await saveAppProfile(db, p!.copyWith(goal: sc.Goal.wellbeing));
      return db;
    }))!;
    await render(t, db, const TodayScreen());
    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('EFFORT'), findsOneWidget);
    expect(find.textContaining('strain under'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('past bedtime: says so, and no reminder in the past', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    final today = (await t.runAsync(() => loadToday(db)))!;
    // An hour and a half after tonight's bedtime.
    final late = (today.bedtimeMinute + 90) % 1440;
    testHour = late ~/ 60;
    addTearDown(() => testHour = 9);
    final now = DateTime.now();
    appNow = () =>
        DateTime(now.year, now.month, now.day, late ~/ 60, late % 60);
    await t.pumpWidget(
      harness(db, TempoPage(children: [TonightCard(t: today)])),
    );
    appNow = () =>
        DateTime(now.year, now.month, now.day, late ~/ 60, late % 60);
    await settle(t);
    expect(find.textContaining('bedtime · passed'), findsOneWidget);
    expect(find.textContaining('Bed now and you get'), findsOneWidget);
    expect(find.textContaining('Remind me at'), findsNothing);
    await teardown(t, db);
  });
}
