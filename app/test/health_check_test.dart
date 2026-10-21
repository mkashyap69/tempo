import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_check.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/screens/health_check.dart';
import 'package:tempo/src/screens/settings.dart';

import 'support/harness.dart';
import 'support/health_fake.dart';
import 'support/seed.dart' show loadFonts;

void main() {
  group('checkHealth', () {
    late TempoDb db;
    late FakeReader reader;
    setUp(() async {
      db = TempoDb(NativeDatabase.memory());
      await saveDataSource(db, DataSource.healthConnect);
      reader = FakeReader(watchData(10));
      await HealthSyncService(db, reader: reader, useLock: false).run();
    });
    tearDown(() => db.close());

    KindCheck of(HealthCheckReport r, HealthKind k) =>
        r.kinds.firstWhere((x) => x.kind == k);

    test('right after a read, everything Health has is stored', () async {
      final r = await checkHealth(db, reader);
      expect(r.access, isTrue);
      expect(r.allOk, isFalse); // some kinds have no data at all
      for (final k in r.kinds) {
        expect(k.verdict, isIn([KindVerdict.ok, KindVerdict.empty]));
        expect(k.missing, 0, reason: k.kind.name);
        expect(k.extra, 0, reason: k.kind.name);
      }
      final hr = of(r, HealthKind.heartRate);
      expect(hr.verdict, KindVerdict.ok);
      expect(hr.stored, hr.inHealth);
      expect(hr.min, greaterThanOrEqualTo(52));
      expect(hr.max, 150);
      expect(of(r, HealthKind.spo2).verdict, KindVerdict.empty);
      // Tempo's own night is skipped on purpose, not missing.
      expect(of(r, HealthKind.sleepSession).dropped, 1);
      expect(of(r, HealthKind.sleepSession).verdict, KindVerdict.ok);
    });

    test('flags missing, extra, newer, odd and failed kinds', () async {
      final last = DateTime.parse((await db.setting(Keys.lastSync))!);
      final steps = reader.records.lastWhere((x) => x.kind == HealthKind.steps);
      reader.records = [
        for (final x in reader.records)
          if (x != steps) x,
        // Written before the last read but never stored.
        rec(HealthKind.hrvRmssd, last.subtract(const Duration(hours: 2)), 45),
        // Written after it: the next read's.
        rec(HealthKind.restingHr, last.add(const Duration(seconds: 1)), 50),
        // A unit gone wrong.
        rec(HealthKind.spo2, last.add(const Duration(seconds: 2)), 9700),
      ];
      reader.failing = {HealthKind.workout};
      final r = await checkHealth(
        db,
        reader,
        now: last.add(const Duration(minutes: 1)),
      );
      expect(of(r, HealthKind.hrvRmssd).verdict, KindVerdict.missing);
      expect(of(r, HealthKind.hrvRmssd).missing, 1);
      expect(of(r, HealthKind.steps).verdict, KindVerdict.extra);
      expect(of(r, HealthKind.steps).extra, 1);
      expect(of(r, HealthKind.restingHr).verdict, KindVerdict.ok);
      expect(of(r, HealthKind.restingHr).newer, 1);
      expect(of(r, HealthKind.spo2).verdict, KindVerdict.odd);
      expect(of(r, HealthKind.workout).verdict, KindVerdict.failed);
      expect(of(r, HealthKind.workout).error, contains('locked'));
      final text = r.text('Health Connect', const {});
      expect(text, contains('hrvRmssd: missing'));
      expect(text, contains('workout: failed'));
      // Read-only: the check stored nothing.
      final stored = await db.healthRecordsStarting(
        last.subtract(const Duration(days: 1)),
        last.add(const Duration(hours: 1)),
      );
      expect(stored.where((x) => x.kind == 'spo2'), isEmpty);
    });

    test('records carry their status; permissions come through', () async {
      final last = DateTime.parse((await db.setting(Keys.lastSync))!);
      reader.records = [
        ...reader.records,
        rec(
          HealthKind.hrvRmssd,
          last.subtract(const Duration(hours: 1)),
          44,
          uuid: 'lost',
        ),
      ];
      reader.denied = {HealthKind.spo2};
      final r = await checkHealth(
        db,
        reader,
        now: last.add(const Duration(minutes: 1)),
      );
      final hrv = of(r, HealthKind.hrvRmssd).recent;
      expect(hrv.first.record.uuid, 'lost'); // newest first
      expect(hrv.first.status, RecordStatus.missing);
      expect(hrv.skip(1).every((x) => x.status == RecordStatus.stored), isTrue);
      final own = of(
        r,
        HealthKind.sleepSession,
      ).recent.where((x) => x.record.fromTempo);
      expect(own.single.status, RecordStatus.dropped);
      expect(of(r, HealthKind.heartRate).recent.length, KindCheck.recentLimit);
      expect(r.permissions!.kinds[HealthKind.spo2], isFalse);
      expect(r.permissions!.kinds[HealthKind.heartRate], isTrue);
      expect(r.text('Health Connect', const {}), contains('spo2 no'));
    });

    test('pipeline follows a night through to the score', () async {
      final today = DateTime.now();
      final y = DateTime(today.year, today.month, today.day - 1);
      // Yesterday at 13:00: the night that ended yesterday morning is whole
      // whenever this runs.
      final q = await checkPipeline(db, now: y.add(const Duration(hours: 13)));
      expect(q.sleepRecordMin, 480);
      expect(q.sleepMin, closeTo(480, 5));
      expect(q.stages['deep'], closeTo(90, 2));
      expect(q.hrMeasuredMin, greaterThan(0));
      expect(q.stepsBySource.keys, containsAll(['phone', 'watch']));
      expect(
        q.stepsTempo,
        lessThan(q.stepsBySource.values.reduce((a, b) => a + b)),
      );
      expect(q.today, isNotNull); // yesterday's row, as "today" at 13:00
      expect(q.today!.source, 'health_connect');
      expect(q.chosen[SourceMetric.sleep], isNull);
    });

    test('a re-read reaches back 90 days and keeps what is stored', () async {
      final old = DateTime.now().subtract(const Duration(days: 60));
      reader.records = [
        ...reader.records,
        rec(HealthKind.restingHr, old, 51, uuid: 'old'),
      ];
      final before = (await db.healthRecordsStarting(
        DateTime(2000),
        DateTime.now(),
      )).length;
      await rereadHealth(db);
      final r = await HealthSyncService(
        db,
        reader: reader,
        useLock: false,
      ).run();
      expect(r.from.isBefore(old), isTrue);
      expect(r.from.isAfter(old.subtract(const Duration(days: 31))), isTrue);
      final after = await db.healthRecordsStarting(
        DateTime(2000),
        DateTime.now(),
      );
      expect(after.length, before + 1);
      expect(after.where((x) => x.uuid == 'old'), hasLength(1));
    });

    test('no access is reported, not thrown', () async {
      reader.access = false;
      final r = await checkHealth(db, reader);
      expect(r.access, isFalse);
      expect(r.allOk, isFalse);
    });
  });

  group('developer settings', () {
    setUpAll(loadFonts);

    testWidgets('hidden until seven taps on the version line', (t) async {
      final db = (await t.runAsync(() => healthDb(nights: 3)))!;
      t.view.physicalSize = const Size(390, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, const SettingsScreen()));
      await settle(t);
      expect(find.text('Health data check'), findsNothing);
      expect(find.text('Band explorer'), findsNothing);
      final version = find.textContaining('Tempo 1.0');
      for (var i = 0; i < 7; i++) {
        await t.tap(version);
        await t.pump(const Duration(milliseconds: 100));
      }
      await settle(t);
      expect(find.text('Health data check'), findsOneWidget);
      expect(find.text('Band explorer'), findsOneWidget);
      expect(find.text('Re-read last 90 days'), findsOneWidget);
      expect(find.text('Run background sync now'), findsOneWidget);
      expect(find.text('Send a test notification'), findsOneWidget);
      expect(find.text('Needs the Mi Band as the data source'), findsOneWidget);
      await t.tap(find.text('Hide developer settings'));
      await settle(t);
      expect(find.text('Health data check'), findsNothing);
      await teardown(t, db);
    });

    testWidgets('the check screen runs and lists every kind', (t) async {
      final db = (await t.runAsync(() => healthDb(nights: 3)))!;
      t.view.physicalSize = const Size(390, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final reader = FakeReader(watchData(3));
      await t.pumpWidget(harness(db, HealthCheckScreen(reader: reader)));
      await settle(t);
      await t.tap(find.text('Run check'));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Heart rate'), findsWidgets);
      expect(find.text('Workouts'), findsWidgets);
      expect(find.text('Copy report'), findsOneWidget);
      expect(find.text('Save report'), findsOneWidget);
      expect(find.text('Last night and today'.toUpperCase()), findsOneWidget);
      expect(find.text('PERMISSIONS'), findsOneWidget);
      await t.tap(find.text('Heart rate').last);
      await settle(t);
      expect(find.text('Stored'), findsWidgets);
      expect(t.takeException(), isNull);
      await teardown(t, db);
    });
  });
}
