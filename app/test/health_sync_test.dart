import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_reader.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/minutes.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/core/score_service.dart';

import 'support/health_fake.dart';

void main() {
  late TempoDb db;
  setUp(() async {
    db = TempoDb(NativeDatabase.memory());
    await saveDataSource(db, DataSource.healthConnect);
  });
  tearDown(() => db.close());

  final today = DateTime.now();
  final day0 = DateTime(today.year, today.month, today.day);

  HealthSyncService service(FakeReader r, {bool background = false}) =>
      HealthSyncService(db, reader: r, useLock: false, background: background);

  test('first read imports, scores with HRV and finds workouts', () async {
    final r = FakeReader(watchData(20));
    final rep = await service(r).run();
    expect(rep.firstImport, isTrue);
    expect(rep.failed, isEmpty);
    // Tempo's own night was dropped.
    final stored = await db.healthRecordsBetween(
      day0.subtract(const Duration(days: 30)),
      day0.add(const Duration(days: 1)),
    );
    expect(stored.where((x) => x.sourceApp == tempoAppId), isEmpty);
    expect(await db.cursor(HealthSyncService.device, 'records'), isNotNull);

    // Yesterday: its night and day are wholly in the past whenever this
    // runs.
    final s = (await db.scoreFor(day0.subtract(const Duration(days: 1))))!;
    expect(s.source, 'health_connect');
    expect(s.sleptHours, closeTo(8, 1e-9));
    expect(s.hrv, isNotNull);
    expect(s.hrvKind, 'rmssd');
    expect(s.hrvProxy, isNull);
    expect(s.calibrating, isFalse);
    expect(s.recovery, isNotNull);
    expect(s.rhr, closeTo(52.5, 1.5));

    // Steps: the busier app per minute, not phone + watch.
    final y = day0.subtract(const Duration(days: 1));
    final steps = await db.stepsBetween(
      y,
      y.add(const Duration(days: 1)),
      health: true,
    );
    expect(steps, 11 * 330);

    // The run is a confirmed Health workout with strain from its HR.
    final ws = await db.workoutsBetween(y, y.add(const Duration(days: 1)));
    final run = ws.singleWhere((w) => w.source == 'health');
    expect(run.sport, sc.Sport.running.name);
    expect(run.confirmed, isTrue);
    expect(run.avgHr, 150);
    expect(run.strain, greaterThan(0));
    expect(
      ws.where((w) => w.source == 'auto' && w.start == run.start),
      isEmpty,
    );

    // Staged night from the source, no stress for a Health source.
    final mins = await loadMinutes(
      db,
      y.subtract(const Duration(hours: 1)),
      y.add(const Duration(hours: 8)),
    );
    expect(mins.unstaged, isFalse);
    expect(mins.minutes.any((m) => m.stage == sc.Stage.deep), isTrue);
    expect(await loadStress(db, y, day0), isEmpty);
  });

  test('a re-read tombstones records deleted in Health', () async {
    final data = watchData(3);
    final r = FakeReader(data);
    await service(r).run();
    final y = day0.subtract(const Duration(days: 1));
    final run = data.firstWhere(
      (x) =>
          x.kind == HealthKind.workout &&
          x.start.isAfter(y) &&
          x.start.isBefore(day0),
    );
    r.records = [...data]..remove(run);
    final rep = await service(r).run();
    expect(rep.firstImport, isFalse);
    expect(rep.gone, 1);
    final ws = await db.workoutsBetween(y, day0);
    expect(ws.where((w) => w.source == 'health'), isEmpty);
    // Still stored, append-only, but hidden.
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM health_records '
            "WHERE key = '${run.key}'",
          )
          .getSingle()
          .then((x) => x.read<int>('n')),
      1,
    );
  });

  test('an empty read is doubtful and deletes nothing', () async {
    final r = FakeReader(watchData(3));
    await service(r).run();
    final before = await db.hrMinutesBetween(
      day0.subtract(const Duration(days: 3)),
      day0,
      health: true,
    );
    r.emptying = {HealthKind.heartRate};
    final rep = await service(r).run();
    expect(rep.gone, 0);
    expect(rep.doubtful, contains(HealthKind.heartRate));
    expect(
      await db.hrMinutesBetween(
        day0.subtract(const Duration(days: 3)),
        day0,
        health: true,
      ),
      before,
    );
  });

  test('every read failing (phone locked) keeps the cursor', () async {
    final r = FakeReader(watchData(2))..failing = FakeReader([]).kinds;
    await expectLater(
      service(r).run(),
      throwsA(isA<HealthUnreadableException>()),
    );
    expect(await db.cursor(HealthSyncService.device, 'records'), isNull);
    expect(await db.setting(Keys.lastError), startsWith('health_unreadable'));
  });

  test('a partial read scores what it got and reads again', () async {
    final r = FakeReader(watchData(2))..failing = {HealthKind.spo2};
    final rep = await service(r).run();
    expect(rep.failed, {HealthKind.spo2});
    expect(await db.cursor(HealthSyncService.device, 'records'), isNull);
    expect(await db.setting(Keys.lastError), startsWith('health_partial'));
    expect(
      (await db.scoreFor(day0.subtract(const Duration(days: 1))))?.sleptHours,
      isNotNull,
    );
    r.failing = {};
    await service(r).run();
    expect(await db.cursor(HealthSyncService.device, 'records'), isNotNull);
    expect(await db.setting(Keys.lastError), isNull);
  });

  test('no access and background limits', () async {
    final r = FakeReader(watchData(1))..access = false;
    await expectLater(service(r).run(), throwsA(isA<HealthAccessException>()));
    expect(await db.setting(Keys.lastError), startsWith('health_access'));
    final bg = FakeReader(watchData(1))..background = false;
    final rep = await service(bg, background: true).run();
    expect(rep.skipped, isTrue);
    expect(bg.reads, 0);
  });

  test('switching back to the band keeps the Health days', () async {
    await service(FakeReader(watchData(5))).run();
    final y = day0.subtract(const Duration(days: 1));
    expect((await db.scoreFor(y))!.source, 'health_connect');
    // The band only has data from today.
    await saveDataSource(db, DataSource.band);
    await db.appendMinutes([
      for (var i = 0; i < 30; i++)
        MinuteSamplesCompanion.insert(
          ts: Value(toTs(day0.add(Duration(minutes: i)))),
          steps: 0,
          intensity: 0,
          kind: 1,
          hr: const Value(60),
        ),
    ]);
    await ScoreService(db)
        .recomputeFrom(day0.subtract(const Duration(days: 10)));
    expect((await db.scoreFor(y))!.source, 'health_connect');
    expect((await db.scoreFor(y))!.sleptHours, isNotNull);
    expect((await db.scoreFor(day0))!.source, sc.bandSource);
    // Stale-algo Health rows are not a reason to rescore forever.
    await ScoreService(db).recomputeIfStale();
  });

  test('a session timed in Tempo takes heart rate from Health', () async {
    final y = day0.subtract(const Duration(days: 1));
    final data = watchData(2)..removeWhere((x) => x.kind == HealthKind.workout);
    final run = DateTime(y.year, y.month, y.day, 18);
    final id = await db.addWorkout(
      WorkoutsCompanion.insert(
        start: toTs(run),
        end: toTs(run.add(const Duration(minutes: 40))),
        sport: Value(sc.Sport.running.name),
        title: 'Running',
        source: 'live',
        confirmed: const Value(true),
        strain: 0,
        trimp: 0,
        zones: '[0,0,0,0,0]',
      ),
    );
    await service(FakeReader(data)).run();
    final w = (await db.workout(id))!;
    expect(w.avgHr, 150);
    expect(w.strain, greaterThan(0));
  });

  test('a restored Apple Health source on Android reads Health Connect', () {
    expect(
      resolveDataSource('apple_health', platform: DataSource.healthConnect),
      DataSource.healthConnect,
    );
    expect(resolveDataSource(null), DataSource.band);
    expect(resolveDataSource('band'), DataSource.band);
  });

  test('plugin data points map to records', () {
    // Exercised on device; the mapping is covered by health_source tests.
    expect(PluginHealthReader(ios: true).kinds, contains(HealthKind.hrvSdnn));
    expect(
      PluginHealthReader(ios: false).kinds,
      containsAll([HealthKind.sleepSession, HealthKind.hrvRmssd]),
    );
  });
}
