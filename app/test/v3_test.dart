import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:drift/drift.dart' show Value;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/metric_info.dart';
import 'package:tempo/src/core/net_ledger.dart';
import 'package:tempo/src/core/plan_changes.dart';
import 'package:tempo/src/core/today.dart' show sampleCall;
import 'package:tempo/src/screens/body_check.dart';
import 'package:tempo/src/screens/coach.dart';
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
}) => PlanDay(
  date: date,
  session: session,
  original: original,
  reason: reason,
  adaptedAt: original == null ? null : 1700000000,
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
}
