import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/journal.dart';
import 'package:tempo/src/screens/journal.dart';
import 'package:tempo/src/screens/journal_customise.dart';

import 'support/harness.dart';
import 'support/seed.dart';

Future<void> render(
  WidgetTester t,
  TempoDb db,
  Widget w, {
  double h = 1600,
}) async {
  t.view.physicalSize = Size(390, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(harness(db, w));
  await settle(t);
  expect(t.takeException(), isNull);
}

void main() {
  final yesterday = dayOf(DateTime.now()).subtract(const Duration(days: 1));

  group('journal config', () {
    test('defaults: the five old tags and every automatic entry', () async {
      final db = TempoDb(NativeDatabase.memory());
      final c = await loadJournalConfig(db);
      expect(c.asked.map((d) => d.key), sc.defaultJournalKeys);
      expect(c.automatic.length, 8);
      await db.close();
    });

    test('switching entries and adding your own', () async {
      final db = TempoDb(NativeDatabase.memory());
      await setEntryEnabled(db, 'caffeine_mg', true);
      await setEntryEnabled(db, 'travel', false);
      final key = await addCustomEntry(db, 'Hot yoga');
      expect(key, 'custom_hot_yoga');
      // Same name again reuses the entry.
      expect(await addCustomEntry(db, 'Hot yoga'), key);
      final c = await loadJournalConfig(db);
      expect(c.asked.map((d) => d.key), contains('caffeine_mg'));
      expect(c.asked.map((d) => d.key), isNot(contains('travel')));
      expect(c.custom.single.name, 'Hot yoga');
      expect(c.asked.last.key, key);
      await db.close();
    });
  });

  test('a check-in with amounts and times; clearing an amount', () async {
    final db = TempoDb(NativeDatabase.memory());
    await setEntryEnabled(db, 'drinks', true);
    await setEntryEnabled(db, 'last_meal', true);
    final c = await loadJournalConfig(db);
    expect(await journalCheckedIn(db, yesterday), isFalse);
    await saveCheckin(
      db,
      yesterday,
      c,
      answers: {'alcohol': false},
      amounts: {'drinks': 0, 'last_meal': 21 * 60 + 30},
    );
    expect(await journalCheckedIn(db, yesterday), isTrue);
    var rows = {for (final r in await db.journalFor(yesterday)) r.tag: r};
    expect(rows['drinks']!.value, isFalse);
    expect(rows['drinks']!.amount, 0);
    expect(rows['last_meal']!.amount, 1290);
    expect(rows[sc.checkinTag]!.value, isTrue);
    await saveCheckin(
      db,
      yesterday,
      c,
      answers: const {},
      amounts: {'drinks': null},
    );
    rows = {for (final r in await db.journalFor(yesterday)) r.tag: r};
    expect(rows.containsKey('drinks'), isFalse);
    await db.close();
  });

  test('automatic entries and impact days from band data', () async {
    final db = await seededDb(days: 30);
    final c = await loadJournalConfig(db);
    final auto = await autoEntriesFor(db, yesterday, c);
    expect(auto['auto_steps'], isNotNull);
    expect(auto['auto_brisk'], isNotNull);
    final days = await loadImpactDays(
      db,
      c,
      from: yesterday.subtract(const Duration(days: 20)),
      to: yesterday,
    );
    expect(days, isNotEmpty);
    // The seed tags every evening but yesterday's.
    final d = days.firstWhere((d) => d.x.containsKey('alcohol'));
    expect(d.x['alcohol'], anyOf(0, 1));
    expect(d.x.keys.where((k) => k.startsWith('auto_')), isNotEmpty);
    expect(d.y[sc.Outcome.sleptHours], isNotNull);
    expect(d.strain, isNotNull);
    await db.close();
  });

  test('experiments: one at a time, stopped ones keep their days', () async {
    final db = TempoDb(NativeDatabase.memory());
    await startExperiment(db, 'caffeine_late', false);
    final e = (await loadExperiment(db))!;
    expect(e.doIt, isFalse);
    expect(e.runningOn(DateTime.now()), isTrue);
    // Stopping on the first day leaves nothing to analyse.
    await stopExperiment(db);
    expect(await loadExperiment(db), isNull);
    expect(await loadPastExperiments(db), isEmpty);
    await db.close();
  });

  testWidgets('check-in shows entries, automatic ones and saves', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 20);
      await setEntryEnabled(db, 'drinks', true);
      // Yesterday not checked in yet.
      for (final r in await db.journalFor(yesterday)) {
        await db.clearJournal(yesterday, r.tag);
      }
      return db;
    }))!;
    await render(t, db, const JournalScreen(), h: 2600);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('AUTOMATIC'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('More drinks'));
    await settle(t);
    expect(find.text('1 drinks'), findsOneWidget);
    await t.tap(find.text('Save check-in'));
    await settle(t, frames: 30);
    final rows = await t.runAsync(() => db.journalFor(yesterday));
    expect(rows!.any((r) => r.tag == 'drinks' && r.amount == 1), isTrue);
    await teardown(t, db);
  });

  testWidgets('customise: search and switch an entry on', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 5)))!;
    await render(t, db, const JournalCustomiseScreen(), h: 2600);
    await t.enterText(find.byType(EditableText), 'creat');
    await settle(t);
    expect(find.text('Creatine'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Creatine').last);
    await settle(t, frames: 30);
    final c = await t.runAsync(() => loadJournalConfig(db));
    expect(c!.enabled, contains('creatine'));
    await teardown(t, db);
  });

  testWidgets('insights: outcomes, impacts and the caveat', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 40)))!;
    await render(t, db, const JournalScreen(), h: 3000);
    await t.tap(find.text('Insights'));
    await settle(t, frames: 80);
    expect(t.takeException(), isNull);
    expect(find.text('Time asleep'), findsOneWidget);
    expect(find.textContaining('Patterns, not proof'), findsOneWidget);
    await t.tap(find.text('Sleep'));
    await settle(t, frames: 60);
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });
}
