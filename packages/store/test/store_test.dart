import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';

/// daily_scores as it stood in schema 9 (every older fixture has it).
const v9Scores =
    'CREATE TABLE daily_scores (date TEXT NOT NULL PRIMARY KEY, '
    'strain REAL NOT NULL, trimp REAL NOT NULL, '
    'hr_max INTEGER NOT NULL, sleep_perf REAL, slept_hours REAL, '
    'need_hours REAL, nap_hours REAL NOT NULL DEFAULT 0.0, '
    'base_need REAL, sleep_start INTEGER, sleep_end INTEGER, '
    'recovery REAL, rhr REAL, hrv_proxy REAL, '
    'calibrating INTEGER NOT NULL, algo_version INTEGER NOT NULL)';

void main() {
  late TempoDb db;
  setUp(() => db = TempoDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  MinuteSamplesCompanion m(int ts, {int? hr, int steps = 0}) =>
      MinuteSamplesCompanion.insert(
        ts: Value(ts),
        steps: steps,
        intensity: 0,
        kind: 1,
        hr: Value(hr),
      );

  test('append ignores duplicates, keeps the first write', () async {
    await db.appendMinutes([m(60, hr: 70), m(120, hr: 71)]);
    await db.appendMinutes([m(60, hr: 99), m(180, hr: 72)]);
    final rows = await db.minutesBetween(fromTs(0), fromTs(1000));
    expect(rows.map((r) => r.hr), [70, 71, 72]);
  });

  test('raw tables reject update and delete', () async {
    await db.appendMinutes([m(60, hr: 70)]);
    expect(
      () => db
          .update(db.minuteSamples)
          .write(const MinuteSamplesCompanion(hr: Value(1))),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.delete(db.minuteSamples).go(),
      throwsA(isA<SqliteException>()),
    );
    await db.appendHrLive(5, 120);
    expect(() => db.delete(db.hrLive).go(), throwsA(isA<SqliteException>()));
  });

  test('scores upsert and carry algo version', () async {
    final day = DateTime(2026, 3, 2);
    DailyScoresCompanion s(double strain, int algo) =>
        DailyScoresCompanion.insert(
          date: dateKey(day),
          strain: strain,
          trimp: 1,
          hrMax: 190,
          calibrating: true,
          algoVersion: algo,
        );
    await db.upsertScore(s(5, 1));
    await db.upsertScore(s(7, 2));
    final got = await db.scoreFor(day);
    expect(got!.strain, 7);
    expect(await db.staleScores(2), isEmpty);
    expect(
      (await db.scoresBefore(DateTime(2026, 3, 3))).single.date,
      '2026-03-02',
    );
  });

  test('sync cursors and settings', () async {
    expect(await db.cursor('band', 'activity'), isNull);
    await db.setCursor('band', 'activity', fromTs(600));
    await db.setCursor('band', 'activity', fromTs(1200));
    expect(await db.cursor('band', 'activity'), fromTs(1200));
    await db.putSetting('device_id', 'AA:BB');
    expect(await db.setting('device_id'), 'AA:BB');
  });

  test('journal upsert', () async {
    final d = DateTime(2026, 3, 2);
    await db.setJournal(d, 'alcohol', true);
    await db.setJournal(d, 'alcohol', false);
    expect((await db.journalFor(d)).single.value, isFalse);
  });

  WorkoutsCompanion w(
    int start,
    int end, {
    String source = 'auto',
    bool confirmed = false,
  }) => WorkoutsCompanion.insert(
    start: start,
    end: end,
    title: 'Walk',
    source: source,
    confirmed: Value(confirmed),
    strain: 1,
    trimp: 10,
    zones: '[0,0,0,0,0]',
  );

  test('auto workouts are replaced; live and confirmed ones stay', () async {
    await db.addWorkout(w(1000, 2000));
    await db.addWorkout(w(3000, 4000, confirmed: true));
    await db.addWorkout(w(5000, 6000, source: 'live'));
    await db.replaceAutoWorkouts(fromTs(0), fromTs(10000), [
      w(1100, 1900),
      w(3500, 3600), // overlaps the confirmed one → dropped
      w(7000, 8000),
    ]);
    final all = await db.workoutsBetween(fromTs(0), fromTs(10000));
    expect(all.map((x) => x.start), [1100, 3000, 5000, 7000]);
  });

  test('plan days upsert by date', () async {
    final d = DateTime(2026, 10, 4);
    await db.putPlanDay(
      PlanDaysCompanion.insert(
        date: dateKey(d),
        session: '{"a":1}',
        general: false,
      ),
    );
    await db.putPlanDay(
      PlanDaysCompanion.insert(
        date: dateKey(d),
        session: '{"a":2}',
        general: true,
        reason: const Value('why'),
      ),
    );
    final p = await db.planDay(d);
    expect(p!.session, '{"a":2}');
    expect(p.reason, 'why');
  });

  test('sync log newest first', () async {
    await db.logSync('a', 'ok', at: fromTs(10));
    await db.logSync('b', 'failed', at: fromTs(20));
    final l = await db.watchSyncLog().first;
    expect(l.map((e) => e.summary), ['b', 'a']);
  });

  test('settings watch and delete', () async {
    await db.putSetting('k', 'v');
    expect(await db.watchSetting('k').first, 'v');
    await db.deleteSetting('k');
    expect(await db.setting('k'), isNull);
  });

  test(
    'restore keeps raw rows, replaces derived, renumbers workouts',
    () async {
      await db.appendMinutes([m(60, hr: 50)]);
      await db.addWorkout(
        WorkoutsCompanion.insert(
          start: 1000,
          end: 2000,
          sport: const Value('running'),
          title: 'Run',
          source: 'live',
          strain: 8,
          trimp: 30,
          zones: '[0,0,0,0,0]',
        ),
      );
      final n = await db.restoreRows({
        'minute_samples': [
          {'ts': 60, 'steps': 9, 'intensity': 0, 'kind': 1, 'hr': 99},
          {'ts': 120, 'steps': 3, 'intensity': 0, 'kind': 1, 'hr': 70},
        ],
        'daily_scores': [
          {
            'date': '2026-10-01',
            'strain': 9.5,
            'trimp': 40,
            'hr_max': 190,
            'calibrating': 0,
            'algo_version': 2,
            'from_the_future': 'dropped',
          },
        ],
        'workouts': [
          {
            'id': 1,
            'start': 1000,
            'end': 2000,
            'sport': 'running',
            'title': 'dup',
            'source': 'live',
            'strain': 8,
            'trimp': 30,
            'zones': '[]',
          },
          {
            'id': 1,
            'start': 5000,
            'end': 6000,
            'sport': 'cycling',
            'title': 'Ride',
            'source': 'live',
            'confirmed': 1,
            'strain': 6,
            'trimp': 20,
            'zones': '[]',
          },
        ],
        'settings': [
          {'key': 'x', 'value': 'ignored'},
        ],
        // "drop" is an SQL keyword; restore used to fail on it.
        'od_events': [
          {'ts': 300, 'drop': 4, 'spo2': '00', 'hr': '00'},
        ],
      });
      expect(n['od_events'], 1);
      expect(n['minute_samples'], 1);
      expect(n['daily_scores'], 1);
      expect(n['workouts'], 1);
      expect(n.containsKey('settings'), isFalse);
      final mins = await db.minutesBetween(fromTs(0), fromTs(200));
      expect(mins.map((r) => r.hr), [50, 70]); // first write kept
      final s = await db.scoreFor(DateTime(2026, 10, 1));
      expect(s!.strain, 9.5);
      expect(s.napHours, 0);
      final w = await db.workoutsBetween(fromTs(0), fromTs(10000));
      expect(w.map((x) => x.title), ['Run', 'Ride']);
    },
  );

  test('band workouts: raw rows append-only, derived row upserts', () async {
    BandWorkoutsCompanion raw(int start) => BandWorkoutsCompanion.insert(
      start: Value(start),
      end: start + 1800,
      kind: 1,
      raw: '0301',
      fetchedAt: start + 4000,
    );
    await db.appendBandWorkouts([raw(1000), raw(1000), raw(9000)]);
    final rows = await db.bandWorkoutsBetween(fromTs(0), fromTs(10000));
    expect(rows.map((r) => r.start), [1000, 9000]);
    expect(
      () => db.customStatement('DELETE FROM band_workouts'),
      throwsA(anything),
    );

    WorkoutsCompanion derived(double strain) => WorkoutsCompanion.insert(
      start: 1000,
      end: 2800,
      sport: const Value('running'),
      title: 'Outdoor run',
      source: 'band',
      confirmed: const Value(true),
      strain: strain,
      trimp: 20,
      zones: '[0,0,0,0,0]',
    );
    await db.upsertBandWorkout(derived(6));
    final id = (await db.workoutsBetween(fromTs(0), fromTs(10000))).single.id;
    await db.updateWorkout(id, const WorkoutsCompanion(rpe: Value(6)));
    await db.upsertBandWorkout(derived(7.5));
    final w = (await db.workoutsBetween(fromTs(0), fromTs(10000))).single;
    expect(w.strain, 7.5);
    expect(w.rpe, 6); // user edits survive a rescore
    expect((await db.watchAllWorkouts(sport: 'running').first).length, 1);
    expect((await db.watchAllWorkouts(sport: 'cycling').first), isEmpty);
  });

  test(
    'clearRawHistoryFrom: only on request, then append-only again',
    () async {
      await db.appendMinutes([m(60, hr: 50), m(120, hr: 51), m(180, hr: 52)]);
      await db.setCursor('band', 'activity', fromTs(240));
      final n = await db.clearRawHistoryFrom(fromTs(120));
      expect(n, 2);
      expect(
        (await db.minutesBetween(fromTs(0), fromTs(1000))).map((r) => r.ts),
        [60],
      );
      expect(await db.cursor('band', 'activity'), isNull);
      // Corrected rows can land in the freed minutes.
      await db.appendMinutes([m(120, hr: 70)]);
      expect((await db.minutesBetween(fromTs(100), fromTs(130))).single.hr, 70);
      // The guard is back.
      expect(
        () => db.customStatement('DELETE FROM minute_samples'),
        throwsA(anything),
      );
    },
  );

  test('plan intent: set, keep on re-plan, nudge log append-only', () async {
    final d = DateTime(2026, 10, 5);
    await db.putPlanDay(
      PlanDaysCompanion.insert(date: dateKey(d), session: '{}', general: false),
    );
    expect((await db.planDay(d))!.status, 'planned');
    await db.setPlanIntent(
      d,
      'moved',
      source: 'user',
      slot: 'pm',
      minute: 1080,
    );
    var p = (await db.planDay(d))!;
    expect(p.status, 'moved');
    expect(p.plannedMinute, 1080);
    expect(p.statusSource, 'user');
    // An adaptation that rewrites the session leaves the intent alone.
    await db.putPlanDay(
      PlanDaysCompanion.insert(
        date: dateKey(d),
        session: '{"x":1}',
        general: false,
      ),
    );
    p = (await db.planDay(d))!;
    expect(p.session, '{"x":1}');
    expect(p.status, 'moved');
    await db.logNudge(
      NudgeLogCompanion.insert(
        ts: 10,
        day: dateKey(d),
        kind: 'session',
        notifId: 110,
        event: 'scheduled',
        algoVersion: 'nudge-1',
      ),
    );
    expect((await db.nudgesSince(fromTs(0))).single.kind, 'session');
    expect(
      () => db.customStatement('DELETE FROM nudge_log'),
      throwsA(anything),
    );
  });

  test('v7 → v8 keeps plan rows and adds intent defaults', () async {
    final old = TempoDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE plan_days (date TEXT NOT NULL PRIMARY KEY, '
            'session TEXT NOT NULL, original TEXT, reason TEXT, '
            'adapted_at INTEGER, general INTEGER NOT NULL)',
          );
          raw.execute(
            "INSERT INTO plan_days VALUES ('2026-10-05', '{}', NULL, NULL, NULL, 0)",
          );
          raw.execute(v9Scores);
          raw.execute('PRAGMA user_version = 7');
        },
      ),
    );
    final p = (await old.planDay(DateTime(2026, 10, 5)))!;
    expect(p.status, 'planned');
    expect(p.plannedMinute, isNull);
    expect(await old.nudgesSince(fromTs(0)), isEmpty);
    await old.close();
  });

  test('morning feel: re-rating replaces, clamps to 1–5', () async {
    final db = TempoDb(NativeDatabase.memory());
    final d = DateTime(2026, 10, 6);
    await db.setFeel(d, 2);
    await db.setFeel(d, 4);
    await db.setFeel(d.add(const Duration(days: 1)), 9);
    final all = await db.feelSince(d);
    expect(
      [for (final f in all) (f.date, f.feel)],
      [('2026-10-06', 4), ('2026-10-07', 5)],
    );
    expect(await db.watchFeel(d).first, 4);
    expect(
      await db.watchFeel(d.subtract(const Duration(days: 1))).first,
      isNull,
    );
    await db.close();
  });

  test('v8 → v9 adds morning_feel and keeps journal rows', () async {
    final old = TempoDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE journal (date TEXT NOT NULL, tag TEXT NOT NULL, '
            'value INTEGER NOT NULL, PRIMARY KEY (date, tag))',
          );
          raw.execute(
            "INSERT INTO journal VALUES ('2026-10-05', 'alcohol', 1)",
          );
          raw.execute(v9Scores);
          raw.execute('PRAGMA user_version = 8');
        },
      ),
    );
    expect((await old.journalFor(DateTime(2026, 10, 5))).single.tag, 'alcohol');
    await old.setFeel(DateTime(2026, 10, 6), 3);
    expect((await old.feelSince(DateTime(2026, 10, 1))).single.feel, 3);
    await old.close();
  });

  group('Health sources', () {
    HealthRecordsCompanion rec(
      String key,
      int startMs,
      int endMs, {
      String kind = 'heartRate',
      double value = 60,
    }) => HealthRecordsCompanion.insert(
      key: key,
      uuid: 'u',
      kind: kind,
      startMs: startMs,
      endMs: endMs,
      value: value,
      sourceApp: 'w',
      fetchedAt: 0,
    );
    DateTime ms(int x) => DateTime.fromMillisecondsSinceEpoch(x);

    test('records append-only; tombstones hide them', () async {
      await db.appendHealthRecords([
        rec('a', 1000, 1000),
        rec('b', 2000, 2000),
      ]);
      await db.appendHealthRecords([rec('a', 1000, 1000, value: 99)]);
      var rows = await db.healthRecordsBetween(ms(0), ms(5000));
      expect(rows.map((r) => r.value), [60, 60]);
      await db.addHealthDeletions(['a']);
      await db.addHealthDeletions(['a']); // twice is fine
      rows = await db.healthRecordsBetween(ms(0), ms(5000));
      expect(rows.single.key, 'b');
      expect((await db.healthRecordsStarting(ms(0), ms(5000))).single.key, 'b');
      expect(
        () => db.customStatement("DELETE FROM health_records WHERE key = 'b'"),
        throwsA(anything),
      );
      expect(
        () =>
            db.customStatement("DELETE FROM health_deletions WHERE key = 'a'"),
        throwsA(anything),
      );
    });

    test('range query finds records overlapping the range', () async {
      // A sleep session from 22:00 to 06:00, asked about 05:00–07:00.
      const h = 3600 * 1000;
      await db.appendHealthRecords([
        rec('s', 22 * h, 30 * h, kind: 'sleepSession'),
        rec('x', 40 * h, 41 * h),
      ]);
      final rows = await db.healthRecordsBetween(ms(29 * h), ms(31 * h));
      expect(rows.single.key, 's');
      expect(
        await db.healthRecordsBetween(
          ms(29 * h),
          ms(31 * h),
          kinds: ['heartRate'],
        ),
        isEmpty,
      );
      final span = (await db.healthRecordSpan())!;
      expect(span.$1, ms(22 * h));
      expect(span.$2, ms(41 * h));
    });

    test('health minutes replace a window and answer aggregates', () async {
      HealthMinutesCompanion hm(int ts, {int steps = 0, int? hr}) =>
          HealthMinutesCompanion.insert(
            ts: Value(ts),
            steps: steps,
            hr: Value(hr),
            hrMeasured: hr != null,
          );
      await db.replaceHealthMinutes(fromTs(0), fromTs(300), [
        hm(0),
        hm(60, steps: 10, hr: 70),
        hm(120, steps: 5),
      ]);
      await db.appendMinutes([m(60, hr: 80, steps: 1000)]);
      expect(await db.stepsBetween(fromTs(0), fromTs(300), health: true), 15);
      expect(await db.stepsBetween(fromTs(0), fromTs(300)), 1000);
      expect(
        await db.hrMinutesBetween(fromTs(0), fromTs(300), health: true),
        1,
      );
      expect(await db.firstMinute(health: true), fromTs(60));
      expect(await db.lastMinute(health: true), fromTs(120));
      await db.replaceHealthMinutes(fromTs(100), fromTs(300), [hm(180)]);
      expect(
        (await db.healthMinutesBetween(
          fromTs(0),
          fromTs(300),
        )).map((r) => r.ts),
        [0, 60, 180],
      );
      expect(
        await db.watchSteps(fromTs(0), fromTs(300), health: true).first,
        10,
      );
    });

    test('stale scores by source', () async {
      Future<void> put(String date, String source) => db.upsertScore(
        DailyScoresCompanion.insert(
          date: date,
          strain: 0,
          trimp: 0,
          hrMax: 190,
          calibrating: true,
          algoVersion: 1,
          source: Value(source),
        ),
      );
      await put('2026-10-01', 'band');
      await put('2026-10-02', 'apple_health');
      expect(await db.staleScores(2), hasLength(2));
      expect(
        (await db.staleScores(2, source: 'apple_health')).single.date,
        '2026-10-02',
      );
    });
  });

  test('v9 → v10 adds Health tables and tags old scores band', () async {
    final old = TempoDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(v9Scores);
          raw.execute(
            "INSERT INTO daily_scores (date, strain, trimp, hr_max, "
            "calibrating, algo_version) VALUES ('2026-10-05', 9, 90, 190, 0, 7)",
          );
          raw.execute('PRAGMA user_version = 9');
        },
      ),
    );
    final s = (await old.scoreFor(DateTime(2026, 10, 5)))!;
    expect(s.source, 'band');
    expect(s.hrv, isNull);
    await old.appendHealthRecords([
      HealthRecordsCompanion.insert(
        key: 'k',
        uuid: 'u',
        kind: 'steps',
        startMs: 0,
        endMs: 60000,
        value: 10,
        sourceApp: 'w',
        fetchedAt: 0,
      ),
    ]);
    expect(
      () => old.customStatement('UPDATE health_records SET value = 1'),
      throwsA(anything),
    );
    await old.close();
  });
}
