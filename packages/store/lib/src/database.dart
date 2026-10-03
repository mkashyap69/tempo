import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

const rawTables = [
  'minute_samples',
  'hr_live',
  'stress_samples',
  'spo2_samples',
];

int toTs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
DateTime fromTs(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

@DriftDatabase(
  tables: [
    MinuteSamples,
    HrLive,
    StressSamples,
    Spo2Samples,
    SleepSessions,
    DailyScores,
    Baselines,
    Journal,
    SyncState,
    Settings,
  ],
)
class TempoDb extends _$TempoDb {
  TempoDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final t in rawTables) {
        await customStatement(
          'CREATE TRIGGER ${t}_no_update BEFORE UPDATE ON $t '
          "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
        );
        await customStatement(
          'CREATE TRIGGER ${t}_no_delete BEFORE DELETE ON $t '
          "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
        );
      }
    },
  );

  // ---- raw (append-only) -------------------------------------------------

  /// Inserts new minutes; rows for minutes already stored are ignored.
  Future<void> appendMinutes(List<MinuteSamplesCompanion> rows) => batch(
    (b) => b.insertAll(minuteSamples, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<void> appendStress(List<StressSamplesCompanion> rows) => batch(
    (b) => b.insertAll(stressSamples, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<void> appendSpo2(List<Spo2SamplesCompanion> rows) => batch(
    (b) => b.insertAll(spo2Samples, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<void> appendHrLive(int ts, int bpm) => into(hrLive).insert(
    HrLiveCompanion.insert(ts: Value(ts), bpm: bpm),
    mode: InsertMode.insertOrIgnore,
  );

  Future<List<MinuteSample>> minutesBetween(DateTime from, DateTime to) =>
      (select(minuteSamples)
            ..where((m) => m.ts.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(m) => OrderingTerm.asc(m.ts)]))
          .get();

  Future<List<StressSample>> stressBetween(DateTime from, DateTime to) =>
      (select(stressSamples)
            ..where((m) => m.ts.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(m) => OrderingTerm.asc(m.ts)]))
          .get();

  Future<List<Spo2Sample>> spo2Between(DateTime from, DateTime to) =>
      (select(spo2Samples)
            ..where((m) => m.ts.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(m) => OrderingTerm.asc(m.ts)]))
          .get();

  Future<List<HrLiveData>> hrLiveSince(DateTime from) =>
      (select(hrLive)
            ..where((m) => m.ts.isBiggerOrEqualValue(toTs(from)))
            ..orderBy([(m) => OrderingTerm.asc(m.ts)]))
          .get();

  Future<DateTime?> firstMinute() async {
    final r = await customSelect('SELECT MIN(ts) AS t FROM minute_samples')
        .getSingle();
    final t = r.read<int?>('t');
    return t == null ? null : fromTs(t);
  }

  // ---- derived -----------------------------------------------------------

  Future<void> upsertScore(DailyScoresCompanion row) =>
      into(dailyScores).insertOnConflictUpdate(row);

  Future<DailyScore?> scoreFor(DateTime day) => (select(
    dailyScores,
  )..where((d) => d.date.equals(dateKey(day)))).getSingleOrNull();

  Stream<DailyScore?> watchScore(DateTime day) => (select(
    dailyScores,
  )..where((d) => d.date.equals(dateKey(day)))).watchSingleOrNull();

  /// Days strictly before [day], newest first.
  Future<List<DailyScore>> scoresBefore(DateTime day, {int limit = 60}) =>
      (select(dailyScores)
            ..where((d) => d.date.isSmallerThanValue(dateKey(day)))
            ..orderBy([(d) => OrderingTerm.desc(d.date)])
            ..limit(limit))
          .get();

  Stream<List<DailyScore>> watchScoresSince(DateTime day) =>
      (select(dailyScores)
            ..where((d) => d.date.isBiggerOrEqualValue(dateKey(day)))
            ..orderBy([(d) => OrderingTerm.asc(d.date)]))
          .watch();

  /// Scores computed by an older algorithm, for recompute on upgrade.
  Future<List<DailyScore>> staleScores(int currentAlgo) => (select(
    dailyScores,
  )..where((d) => d.algoVersion.isNotValue(currentAlgo))).get();

  Future<void> replaceSleepSessions(
    DateTime from,
    DateTime to,
    List<SleepSessionsCompanion> rows,
  ) => transaction(() async {
    await (delete(
      sleepSessions,
    )..where((s) => s.end.isBetweenValues(toTs(from), toTs(to)))).go();
    await batch((b) => b.insertAll(sleepSessions, rows));
  });

  Future<SleepSession?> sleepEndingAt(int endTs) => (select(
    sleepSessions,
  )..where((s) => s.end.equals(endTs))).getSingleOrNull();

  Future<void> putBaseline(String metric, int window, double mean, double sd) =>
      into(baselines).insertOnConflictUpdate(
        BaselinesCompanion.insert(
          metric: metric,
          window: window,
          mean: mean,
          sd: sd,
          updatedAt: toTs(DateTime.now()),
        ),
      );

  Future<List<Baseline>> allBaselines() => select(baselines).get();

  // ---- journal / sync / settings ----------------------------------------

  Future<void> setJournal(DateTime day, String tag, bool value) => into(journal)
      .insertOnConflictUpdate(
        JournalCompanion.insert(date: dateKey(day), tag: tag, value: value),
      );

  Future<List<JournalData>> journalFor(DateTime day) =>
      (select(journal)..where((j) => j.date.equals(dateKey(day)))).get();

  Future<DateTime?> cursor(String device, String type) async {
    final r =
        await (select(syncState)
              ..where((s) => s.device.equals(device) & s.dataType.equals(type)))
            .getSingleOrNull();
    return r == null ? null : fromTs(r.lastTs);
  }

  Future<void> setCursor(String device, String type, DateTime t) =>
      into(syncState).insertOnConflictUpdate(
        SyncStateCompanion.insert(
          device: device,
          dataType: type,
          lastTs: toTs(t),
        ),
      );

  Stream<List<SyncStateData>> watchSyncState() => select(syncState).watch();

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> putSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
