import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:drift/drift.dart' show Value;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/metric_info.dart';
import 'package:tempo/src/core/net_ledger.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/core/plan_changes.dart';
import 'package:tempo/src/core/today.dart' show sampleCall;
import 'package:tempo/src/screens/body_check.dart';
import 'package:tempo/src/core/journal.dart' show startExperiment;
import 'package:tempo/src/screens/coach.dart';
import 'package:tempo/src/screens/discoveries.dart';
import 'package:tempo/src/screens/weekly_review.dart';
import 'package:tempo/src/screens/coach_replies.dart' show openPlan;
import 'package:tempo/src/core/today.dart' show loadToday;

import 'support/health_fake.dart' show healthDb;

import 'package:tempo/src/screens/journal.dart';
import 'package:tempo/src/screens/plan_changes.dart';
import 'package:tempo/src/screens/privacy.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/trends.dart';

import 'support/harness.dart';
import 'support/seed.dart';

String session(String key) => jsonEncode(sc.sessionTemplate(key).toJson());

PlanDay row(
  String date, {
  required String session,
  String? original,
  String? reason,
  String status = 'planned',
  String? source,
  int stamp = 1700000000,
}) => PlanDay(
  date: date,
  session: session,
  original: original,
  reason: reason,
  adaptedAt: original == null ? null : stamp,
  general: false,
  status: status,
  statusSource: source,
  statusAt: source == null ? null : 1700000000,
);

void main() {
  setUpAll(loadFonts);

  group('plan changes', () {
    test('lists changed and skipped days, newest first', () {
      final out = planChanges([
        row('2026-11-23', session: session('easy_run')),
        row(
          '2026-11-24',
          session: session('easy_run'),
          original: session('threshold_run'),
          reason: '· HRV under your normal two nights running.',
        ),
        row(
          '2026-11-25',
          session: session('easy_walk'),
          original: session('long_run'),
          reason: '· Swapped with Sat by you.',
        ),
        row(
          '2026-11-26',
          session: session('easy_run'),
          status: 'skipped',
          source: 'user',
        ),
      ]);
      expect(out.map((r) => r.day.day), [26, 25, 24]);
      expect(out[0].skipped, isTrue);
      expect(out[0].by, ChangeBy.you);
      expect(out[0].from, isNull);
      expect(out[1].by, ChangeBy.you);
      expect(out[2].by, ChangeBy.coach);
      expect(out[2].from, sc.sessionTemplate('threshold_run').title);
      expect(out[2].to, sc.sessionTemplate('easy_run').title);
      expect(out[2].why, 'HRV under your normal two nights running.');
    });

    test('a day moved back to its first session is not a change', () {
      expect(
        planChanges([
          row(
            '2026-11-24',
            session: session('easy_run'),
            original: session('easy_run'),
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('undo', () {
    final today = DateTime(2026, 11, 26);

    test('days changed with one stamp are one change', () {
      final out = planChanges([
        row(
          '2026-11-26',
          session: session('easy_run'),
          original: session('threshold_run'),
          stamp: 5,
        ),
        row(
          '2026-11-28',
          session: session('threshold_run'),
          original: session('easy_run'),
          stamp: 5,
        ),
        row(
          '2026-11-24',
          session: session('easy_walk'),
          original: session('long_run'),
          stamp: 3,
        ),
      ], today: today);
      final sat = out.firstWhere((r) => r.day.day == 28);
      expect(sat.together, [DateTime(2026, 11, 26)]);
      expect(sat.canUndo, isTrue);
      expect(out.firstWhere((r) => r.day.day == 24).canUndo, isFalse);
    });

    test('a change that reaches back before today stays', () {
      final out = planChanges([
        row(
          '2026-11-25',
          session: session('easy_run'),
          original: session('threshold_run'),
          stamp: 7,
        ),
        row(
          '2026-11-27',
          session: session('threshold_run'),
          original: session('easy_run'),
          stamp: 7,
        ),
      ], today: today);
      expect(out.every((r) => !r.canUndo), isTrue);
    });

    test('undo puts both days back and drops a held-back session', () async {
      final db = TempoDb(NativeDatabase.memory());
      addTearDown(db.close);
      final thu = DateTime(2026, 11, 26), sat = DateTime(2026, 11, 28);
      Future<void> put(DateTime d, String now, String first) => db.putPlanDay(
        PlanDaysCompanion.insert(
          date: dateKey(d),
          session: session(now),
          original: Value(session(first)),
          reason: const Value('■ HRV low'),
          adaptedAt: const Value(42),
          general: false,
        ),
      );
      await put(thu, 'easy_run', 'threshold_run');
      await put(sat, 'threshold_run', 'easy_run');
      await db.putSetting(Keys.carried, session('threshold_run'));
      final days = await undoPlanChange(db, 42);
      expect(days, [thu, sat]);
      final rows = await db.planBetween(thu, sat);
      expect(rows.first.session, session('threshold_run'));
      expect(rows.first.original, isNull);
      expect(rows.first.reason, isNull);
      expect(rows.last.session, session('easy_run'));
      expect(await db.setting(Keys.carried), '');
      expect(planChanges(rows, today: thu), isEmpty);
    });

    test('a skipped day can be planned again', () async {
      final db = TempoDb(NativeDatabase.memory());
      addTearDown(db.close);
      final thu = DateTime(2026, 11, 26);
      await db.putPlanDay(
        PlanDaysCompanion.insert(
          date: dateKey(thu),
          session: session('easy_run'),
          general: false,
        ),
      );
      await db.setPlanIntent(thu, 'skipped', source: 'user');
      final before = planChanges(await db.planBetween(thu, thu), today: thu);
      expect(before.single.canUndo, isTrue);
      await undoSkip(db, thu);
      expect(planChanges(await db.planBetween(thu, thu), today: thu), isEmpty);
    });
  });

  group('experiment so far', () {
    sc.ExperimentResult res(
      int before,
      int during,
      sc.ImpactConfidence c, {
      double effect = 4,
    }) => sc.ExperimentResult(
      outcome: sc.Outcome.recovery,
      effect: effect,
      low: effect - 2,
      high: effect + 2,
      daysBefore: before,
      daysDuring: during,
      adherence: 1,
      confidence: c,
    );

    test('too early until a week each side', () {
      expect(
        experimentSoFar(res(14, 3, sc.ImpactConfidence.notEnough)),
        contains('3 of 7 days in'),
      );
      expect(
        experimentSoFar(res(2, 9, sc.ImpactConfidence.notEnough)),
        contains('has 2'),
      );
    });

    test('then the effect against the days before', () {
      final t = experimentSoFar(res(14, 9, sc.ImpactConfidence.moderate));
      expect(t, startsWith('So far: '));
      expect(t, contains('against the 14 days before'));
    });
  });

  group('network ledger', () {
    final now = DateTime(2026, 11, 26, 12);

    test('counts calls by kind over the last week', () {
      var raw = addNetCall(null, 'weather', now);
      raw = addNetCall(raw, 'weather', now.subtract(const Duration(days: 2)));
      raw = addNetCall(raw, 'weather', now.subtract(const Duration(days: 9)));
      final c = netCounts(raw, now.subtract(const Duration(days: 7)));
      expect(c['weather'], 2);
      expect(c['sync'], 0);
      expect(c.keys, netKinds.keys);
    });

    test('keeps 30 days', () {
      var raw = addNetCall(
        null,
        'weather',
        now.subtract(const Duration(days: 40)),
      );
      raw = addNetCall(raw, 'weather', now);
      expect((jsonDecode(raw) as List).length, 1);
    });

    test('a broken ledger reads as empty', () {
      expect(netCounts('nope', now)['weather'], 0);
    });
  });

  group('onboarding voice', () {
    test('everyday priorities hear words, the rest hear numbers', () {
      expect(sampleCall(sc.Goal.wellbeing), startsWith('Well rested.'));
      expect(sampleCall(sc.Goal.fatLoss), isNot(contains('strain')));
      expect(sampleCall(sc.Goal.performance), startsWith('Recovery 78%'));
      expect(sampleCall(sc.Goal.fitness), contains('11–14 strain'));
    });
  });

  group('metric explainers', () {
    test('every body signal has one, with a doctor line', () {
      for (final k in ['rhr', 'hrv', 'stress', 'resp', 'spo2', 'temp']) {
        final i = metricInfo(k)!;
        expect(i.what, isNotEmpty);
        expect(i.doctor, contains('doctor'));
      }
      expect(metricInfo('nope'), isNull);
    });

    test('every place has a word and advice', () {
      for (final p in sc.NormalPlace.values) {
        expect(placeWord(p), isNotEmpty);
        expect(placeAdvice(p), isNotEmpty);
      }
    });
  });

  Future<void> render(
    WidgetTester t,
    TempoDb db,
    Widget w, {
    double h = 2600,
  }) async {
    t.view.physicalSize = Size(390, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, w));
    await t.pumpWidget(harness(db, w));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  const words = ['Push', 'Build', 'Steady', 'Ease', 'Rest'];

  testWidgets('Today leads the call with its word, and Why explains it', (
    t,
  ) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayScreen());
    final word = find.byKey(const ValueKey('call-word'));
    expect(word, findsOneWidget);
    final label = (t.widget(word) as Text).data!;
    expect(words, contains(label));
    await t.tap(word);
    await settle(t);
    expect(find.text('Why $label today'), findsOneWidget);
    expect(find.text('What would change it'), findsOneWidget);
    for (final w in words) {
      expect(find.text(w), findsWidgets);
    }
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });

  testWidgets('Health opens on the body check; a row explains the number', (
    t,
  ) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TrendsScreen(tab: true), h: 9000);
    expect(find.byType(BodyCheckCard), findsOneWidget);
    final row = find.text('Resting heart rate').first;
    await t.tap(row);
    await settle(t);
    expect(find.byType(MetricScreen), findsOneWidget);
    for (final s in [
      'WHAT IT IS',
      'WHAT TO DO',
      'WHAT MOVES IT',
      'WHEN IT’S WORTH A DOCTOR’S VIEW',
    ]) {
      expect(find.text(s), findsOneWidget);
    }
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });

  testWidgets('Train links plan changes, which lists what changed', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      final today = dayOf(DateTime.now());
      await db.putPlanDay(
        PlanDaysCompanion.insert(
          date: dateKey(today),
          session: session('easy_run'),
          original: Value(session('threshold_run')),
          reason: const Value('· HRV under your normal two nights running.'),
          adaptedAt: Value(toTs(DateTime.now())),
          general: false,
        ),
      );
      return db;
    }))!;
    await render(t, db, const CoachScreen(standalone: true), h: 5000);
    await t.tap(find.text('Plan changes'));
    await settle(t);
    expect(find.byType(PlanChangesScreen), findsOneWidget);
    expect(
      find.text('HRV under your normal two nights running.'),
      findsOneWidget,
    );
    expect(find.text('Coach'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('Privacy counts the weather lookups', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 3);
      await recordNetCall(db, 'weather');
      await recordNetCall(db, 'weather');
      return db;
    }))!;
    await render(t, db, const PrivacyScreen());
    expect(find.text('Weather for Today'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Encrypted backup'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('a running experiment says how it is going so far', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      await startExperiment(db, 'alcohol', false);
      return db;
    }))!;
    await render(t, db, const JournalScreen(standalone: true), h: 4000);
    expect(find.byKey(const ValueKey('experiment-so-far')), findsOneWidget);
    expect(find.textContaining('So far: too early to tell'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('Next up turns to tonight in the afternoon', (t) async {
    testHour = 16;
    addTearDown(() => testHour = 9);
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayScreen(), h: 3000);
    expect(find.byKey(const ValueKey('next-up')), findsOneWidget);
    expect(find.textContaining('Lights out by'), findsWidgets);
    expect(find.text('YOUR DAY SO FAR'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('Next up stays out of the evening', (t) async {
    testHour = 22;
    addTearDown(() => testHour = 9);
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayScreen(), h: 3000);
    expect(find.byKey(const ValueKey('next-up')), findsNothing);
    await teardown(t, db);
  });

  testWidgets('a quick reply previews, then swaps today with Undo', (t) async {
    final db = (await t.runAsync(() => healthDb()))!;
    final today = (await t.runAsync(() => loadToday(db)))!;
    final plan = openPlan(today);
    await render(t, db, const TodayScreen(), h: 3200);
    if (plan == null || plan.minutes <= 20) {
      // A done or rest day: no replies to offer.
      expect(find.byKey(const ValueKey('reply-shortOnTime')), findsNothing);
      await teardown(t, db);
      return;
    }
    await t.tap(find.byKey(const ValueKey('reply-shortOnTime')));
    await settle(t);
    expect(find.byKey(const ValueKey('reply-headline')), findsOneWidget);
    expect(find.text('Keep my plan'), findsOneWidget);
    await t.tap(find.text('Use this'));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    // The toast offers Undo right away.
    expect(find.text('Undo'), findsOneWidget);
    final row = (await t.runAsync(() => db.planDay(today.day)))!;
    expect(row.original, isNotNull);
    expect(row.reason, contains('Short on time'));
    expect(row.statusSource, 'user');
    await t.pump(const Duration(seconds: 5)); // let the toast go
    await teardown(t, db);
  });

  testWidgets('Health shows the four tiles; a signal shows its 30 days', (
    t,
  ) async {
    final db = (await t.runAsync(() => healthDb()))!;
    await render(t, db, const TrendsScreen(tab: true), h: 7000);
    expect(find.byKey(const ValueKey('health-tiles')), findsOneWidget);
    for (final l in ['Sleep · 7 nights', 'Fitness', 'Weight', 'Blood']) {
      expect(find.text(l), findsOneWidget);
    }
    await render(t, db, const MetricScreen(signalKey: 'rhr'), h: 2400);
    expect(find.byKey(const ValueKey('metric-chart')), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('Discoveries has its own screen', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      await startExperiment(db, 'alcohol', false);
      return db;
    }))!;
    await render(t, db, const DiscoveriesScreen(), h: 2400);
    expect(find.text('What moves your numbers'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discoveries-experiment')),
      findsOneWidget,
    );
    expect(find.text('EFFECT ON NEXT-MORNING RECOVERY'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('Week in review tells the week as a story', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const WeeklyReviewScreen(), h: 4000);
    expect(find.byKey(const ValueKey('week-story')), findsOneWidget);
    expect(find.text('ONE THING FOR NEXT WEEK'), findsOneWidget);
    await teardown(t, db);
  });
}
