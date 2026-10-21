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
      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Copy report'), findsOneWidget);
      await teardown(t, db);
    });
  });
}
