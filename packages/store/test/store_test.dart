import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';

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
      });
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
}
