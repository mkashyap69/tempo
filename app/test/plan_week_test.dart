import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/week_override.dart';
import 'package:tempo/src/screens/plan_week.dart';

import 'support/harness.dart';
import 'support/seed.dart';

const base = sc.CoachPrefs(
  goal: sc.Goal.fitness,
  likes: {sc.Sport.running},
  days: {1, 2, 3, 4, 5, 6, 7},
  maxMinutes: 60,
  longDay: 7,
  liftDays: {3},
);

void main() {
  setUpAll(loadFonts);

  test('busy days come off; the long day moves', () {
    final p = prefsForWeek(base, const WeekOverride(busy: {3, 5}, longDay: 6));
    expect(p.days, {1, 2, 4, 6, 7});
    expect(p.liftDays, isEmpty);
    expect(p.longDay, 6);
    expect(prefsForWeek(base, null), same(base));
  });

  test('a long day that is busy falls back to the usual one', () {
    final p = prefsForWeek(base, const WeekOverride(busy: {6}, longDay: 6));
    expect(p.longDay, 7);
  });

  test('round-trips through its setting', () {
    final o = WeekOverride.parse(
      const WeekOverride(busy: {5, 2}, longDay: 6).toJson(),
    )!;
    expect(o.busy, {2, 5});
    expect(o.longDay, 6);
    expect(WeekOverride.parse('nope'), isNull);
  });

  test('next week is rebuilt around busy days and the long day', () async {
    final db = await seededDb(days: 20);
    addTearDown(db.close);
    final mon = nextMonday();
    await db.putSetting(
      weekOverrideKey(mon),
      const WeekOverride(busy: {2, 4}, longDay: 6).toJson(),
    );
    final rows = await CoachService(db).ensureWeek(mon, rebuild: true);
    final week = [
      for (final r in rows)
        sc.Session.fromJson(jsonDecode(r.session) as Map<String, dynamic>),
    ];
    expect(week[1].isRest, isTrue);
    expect(week[3].isRest, isTrue);
    expect(week[5].key.startsWith('long_'), isTrue);
  });

  testWidgets('the sheet previews the week and saves next week only', (
    t,
  ) async {
    final db = (await t.runAsync(() => seededDb(days: 20)))!;
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      harness(
        db,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPlanWeekSheet(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('Plan next week with me'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-preview')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('week-day-2')));
    await settle(t);
    expect(find.text('BUSY'), findsOneWidget);
    await t.tap(find.text('Looks good'));
    await settle(t);
    final o = (await t.runAsync(() => loadWeekOverride(db, nextMonday())))!;
    expect(o.busy, {2});
    await t.pump(const Duration(seconds: 5));
    await teardown(t, db);
  });
}
