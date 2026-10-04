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
}
