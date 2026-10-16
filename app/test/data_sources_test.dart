import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/screens/data_sources.dart';

import 'support/harness.dart';
import 'support/health_fake.dart';
import 'support/seed.dart';

const fit = 'com.google.android.apps.fitness';
const ring = 'com.ouraring.oura';

/// A ring that also wrote the night before last (always over, whatever the
/// time now), from 22:00 (an hour before the watch), as one unstaged block.
Future<void> addRingNight(TempoDb db) async {
  final today = DateTime.now();
  final bed = DateTime(today.year, today.month, today.day - 2, 22);
  await HealthSyncService(
    db,
    reader: FakeReader([
      ...watchData(3),
      HealthRecord(
        uuid: 'ring-night',
        kind: HealthKind.sleepAsleep,
        start: bed,
        end: bed.add(const Duration(hours: 9)),
        value: 540,
        sourceApp: ring,
        sourceName: 'Oura',
      ),
    ]),
    useLock: false,
  ).run();
}

Future<int> sleptMinutes(TempoDb db) async {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, today.day - 2, 20);
  final rows = await db.healthMinutesBetween(
    from,
    from.add(const Duration(hours: 14)),
  );
  return rows.where((r) => r.sleep != null && r.sleep != 'awake').length;
}

void main() {
  setUpAll(loadFonts);

  test(
    'sleep sources: listed with names and nights; one can be chosen',
    () async {
      final db = await healthDb(nights: 3);
      await addRingNight(db);
      final names = await sourceNames(db);
      expect(names[ring], 'Oura');
      final src = await sleepSources(db);
      expect(src.map((s) => s.id), [fit, ring]); // most nights first
      expect(src.first.nights, 3);
      expect(src.last.label, 'Oura');
      expect(src.last.nights, 1);
      // Tempo's own exported night is never a source.
      expect(src.any((s) => s.id == tempoAppId), isFalse);

      // Merged: the ring's earlier start adds an hour to the watch's 8 h.
      final merged = await sleptMinutes(db);
      expect(merged, greaterThanOrEqualTo(9 * 60 - 2));
      await setSleepSource(db, fit);
      expect(await db.setting(Keys.healthSleepSource), fit);
      expect(await sleptMinutes(db), inInclusiveRange(8 * 60 - 2, 8 * 60 + 2));
      await setSleepSource(db, ring);
      expect(await sleptMinutes(db), inInclusiveRange(9 * 60 - 2, 9 * 60 + 2));
      await setSleepSource(db, null);
      expect(await db.setting(Keys.healthSleepSource), isNull);
      expect(await sleptMinutes(db), merged);
      await db.close();
    },
  );

  test('labels: Health’s name, else the end of the id', () {
    expect(sourceLabel(ring, {ring: 'Oura'}), 'Oura');
    expect(sourceLabel('com.whoop.app', {}), 'App');
    expect(sourceLabel('com.example.sleepy', {}), 'Sleepy');
  });

  testWidgets('Data sources on Health: access, sleep from, writing', (t) async {
    final db = (await t.runAsync(() async {
      final db = await healthDb(nights: 3);
      await addRingNight(db);
      return db;
    }))!;
    t.view.physicalSize = const Size(390, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const DataSourcesScreen()));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Use the band'), findsOneWidget);
    expect(find.text('HEALTH ACCESS'), findsOneWidget);
    expect(find.text('SLEEP FROM'), findsOneWidget);
    expect(find.text('Every app, merged'), findsOneWidget);
    expect(find.text('Oura'), findsOneWidget);
    expect(find.text('WRITING TO HEALTH'), findsOneWidget);
    await t.tap(find.text('Oura'));
    await settle(t, frames: 60);
    expect(await t.runAsync(() => db.setting(Keys.healthSleepSource)), ring);
    await teardown(t, db);
  });

  testWidgets('Data sources on the band: no Health access or sleep from', (
    t,
  ) async {
    final db = (await t.runAsync(() => seededDb(days: 3)))!;
    t.view.physicalSize = const Size(390, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const DataSourcesScreen()));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('Mi Band 6'), findsOneWidget);
    expect(find.text('Use Health Connect'), findsOneWidget);
    expect(find.text('HEALTH ACCESS'), findsNothing);
    expect(find.text('SLEEP FROM'), findsNothing);
    expect(find.text('WRITING TO HEALTH'), findsOneWidget);
    await teardown(t, db);
  });
}
