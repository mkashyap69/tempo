import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

const rawTables = [
  'minute_samples',
  'hr_live',
  'stress_samples',
  'spo2_samples',
  'band_workouts',
  'od_events',
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
    BandWorkouts,
    OdEvents,
    SleepSessions,
    DailyScores,
    Baselines,
    Journal,
    SyncState,
    Settings,
    Workouts,
    PlanDays,
    SyncLog,
    Longevity,
    NudgeLog,
    MorningFeel,
  ],
)
class TempoDb extends _$TempoDb {
  TempoDb(super.e);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final t in rawTables) {
        await _appendOnly(t);
      }
      await _appendOnly('nudge_log');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(workouts);
        await m.createTable(planDays);
        await m.createTable(syncLog);
      }
      if (from < 3) {
        await m.addColumn(dailyScores, dailyScores.napHours);
        await m.addColumn(dailyScores, dailyScores.baseNeed);
      }
      if (from < 4) {
        await m.createTable(bandWorkouts);
        await _appendOnly('band_workouts');
      }
      if (from < 5) {
        await m.addColumn(minuteSamples, minuteSamples.aux);
      }
      if (from < 7) {
        await m.createTable(longevity);
      }
      if (from < 8) {
        if (from >= 2) {
          await m.addColumn(planDays, planDays.slot);
          await m.addColumn(planDays, planDays.plannedMinute);
          await m.addColumn(planDays, planDays.status);
          await m.addColumn(planDays, planDays.statusSource);
          await m.addColumn(planDays, planDays.statusAt);
          await m.addColumn(planDays, planDays.algoVersion);
        }
        await m.createTable(nudgeLog);
        await _appendOnly('nudge_log');
      }
      if (from < 9) {
        await m.createTable(morningFeel);
      }
      if (from < 6) {
        await m.addColumn(spo2Samples, spo2Samples.quality);
        await m.createTable(odEvents);
        await _appendOnly('od_events');
      }
    },
  );

  Future<void> _appendOnly(String t) async {
    await customStatement(
      'CREATE TRIGGER ${t}_no_update BEFORE UPDATE ON $t '
      "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
    );
    await customStatement(
      'CREATE TRIGGER ${t}_no_delete BEFORE DELETE ON $t '
      "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
    );
  }

  // ---- raw (append-only) -------------------------------------------------

  /// The one exception to append-only, run only on the user's explicit
  /// "Re-download band history": deletes raw samples from [from] on and
  /// every sync cursor, so the next sync fetches them again from the band.
  /// Used to replace rows an older build stored at the wrong time. The
  /// guard triggers are dropped and recreated inside the transaction.
  /// Returns the minutes removed.
  Future<int> clearRawHistoryFrom(DateTime from) => transaction(() async {
    const tables = ['minute_samples', 'stress_samples', 'spo2_samples'];
    var removed = 0;
    for (final t in tables) {
      await customStatement('DROP TRIGGER IF EXISTS ${t}_no_delete');
      final n = await customUpdate(
        'DELETE FROM $t WHERE ts >= ?',
        variables: [Variable.withInt(toTs(from))],
        updates: {
          for (final tb in allTables)
            if (tb.actualTableName == t) tb,
        },
        updateKind: UpdateKind.delete,
      );
      if (t == 'minute_samples') removed = n;
      await customStatement(
        'CREATE TRIGGER ${t}_no_delete BEFORE DELETE ON $t '
        "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
      );
    }
    await delete(syncState).go();
    return removed;
  });

  /// Stores band workout summaries; ones already stored are ignored.
  Future<void> appendBandWorkouts(List<BandWorkoutsCompanion> rows) => batch(
    (b) => b.insertAll(bandWorkouts, rows, mode: InsertMode.insertOrIgnore),
  );

  /// Band workouts starting in [from, to), oldest first.
  Future<List<BandWorkoutRow>> bandWorkoutsBetween(
    DateTime from,
    DateTime to,
  ) =>
      (select(bandWorkouts)
            ..where((x) => x.start.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(x) => OrderingTerm.asc(x.start)]))
          .get();

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

  Future<void> appendOdEvents(List<OdEventsCompanion> rows) => batch(
    (b) => b.insertAll(odEvents, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<List<OdEventRow>> odEventsBetween(DateTime from, DateTime to) =>
      (select(odEvents)
            ..where((e) => e.ts.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(e) => OrderingTerm.asc(e.ts)]))
          .get();

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

  /// Minutes with a heart-rate reading in [from, to): how long the band
  /// was worn.
  Future<int> hrMinutesBetween(DateTime from, DateTime to) async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM minute_samples '
      'WHERE ts >= ? AND ts < ? AND hr IS NOT NULL',
      variables: [Variable.withInt(toTs(from)), Variable.withInt(toTs(to))],
    ).getSingle();
    return r.read<int>('n');
  }

  /// Steps in [from, to).
  Future<int> stepsBetween(DateTime from, DateTime to) async {
    final r = await customSelect(
      'SELECT COALESCE(SUM(steps), 0) AS s FROM minute_samples '
      'WHERE ts >= ? AND ts < ?',
      variables: [Variable.withInt(toTs(from)), Variable.withInt(toTs(to))],
    ).getSingle();
    return r.read<int>('s');
  }

  Future<DateTime?> firstMinute() async {
    final r = await customSelect('SELECT MIN(ts) AS t FROM minute_samples')
        .getSingle();
    final t = r.read<int?>('t');
    return t == null ? null : fromTs(t);
  }

  /// Step count in [from, to). Local day bounds, same clock as [dateKey].
  Stream<int> watchSteps(DateTime from, DateTime to) => customSelect(
    'SELECT COALESCE(SUM(steps), 0) AS steps FROM minute_samples WHERE ts >= ? AND ts < ?',
    variables: [Variable.withInt(toTs(from)), Variable.withInt(toTs(to))],
    readsFrom: {minuteSamples},
  ).watchSingle().map((r) => r.read<int>('steps'));

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

  /// Main-sleep sessions ending in (from, to], oldest first.
  Future<List<SleepSession>> sleepSessionsBetween(DateTime from, DateTime to) =>
      (select(sleepSessions)
            ..where(
              (s) =>
                  s.end.isBiggerThanValue(toTs(from)) &
                  s.end.isSmallerOrEqualValue(toTs(to)),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.end)]))
          .get();

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

  Stream<String?> watchSetting(String key) => (select(
    settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> deleteSetting(String key) =>
      (delete(settings)..where((s) => s.key.equals(key))).go();

  Stream<int> watchJournalDays() => customSelect(
    'SELECT COUNT(DISTINCT date) AS n FROM journal',
    readsFrom: {journal},
  ).watchSingle().map((r) => r.read<int>('n'));

  Stream<List<JournalData>> watchJournal() => select(journal).watch();

  /// Rates [day]'s morning 1–5 (replaces an earlier answer).
  Future<void> setFeel(DateTime day, int feel, {DateTime? at}) =>
      into(morningFeel).insertOnConflictUpdate(
        MorningFeelCompanion.insert(
          date: dateKey(day),
          feel: feel.clamp(1, 5),
          ts: toTs(at ?? DateTime.now()),
        ),
      );

  Stream<int?> watchFeel(DateTime day) =>
      (select(morningFeel)..where((f) => f.date.equals(dateKey(day))))
          .watchSingleOrNull()
          .map((f) => f?.feel);

  /// Ratings from [from] on, oldest first.
  Future<List<MorningFeelData>> feelSince(DateTime from) =>
      (select(morningFeel)
            ..where((f) => f.date.isBiggerOrEqualValue(dateKey(from)))
            ..orderBy([(f) => OrderingTerm.asc(f.date)]))
          .get();

  Stream<List<JournalData>> watchJournalFor(DateTime day) =>
      (select(journal)..where((j) => j.date.equals(dateKey(day)))).watch();

  Future<List<DailyScore>> scoresBetween(DateTime from, DateTime to) =>
      (select(dailyScores)
            ..where((d) => d.date.isBetweenValues(dateKey(from), dateKey(to)))
            ..orderBy([(d) => OrderingTerm.asc(d.date)]))
          .get();

  Stream<DailyScore?> watchLatestScore() =>
      (select(dailyScores)
            ..orderBy([(d) => OrderingTerm.desc(d.date)])
            ..limit(1))
          .watchSingleOrNull();

  Stream<List<SleepSession>> watchSleepSessions() =>
      select(sleepSessions).watch();

  Future<DateTime?> lastMinute() async {
    final r = await customSelect('SELECT MAX(ts) AS t FROM minute_samples')
        .getSingle();
    final t = r.read<int?>('t');
    return t == null ? null : fromTs(t);
  }

  Future<int> minuteCount(DateTime from, DateTime to) async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM minute_samples WHERE ts >= ? AND ts < ?',
      variables: [Variable.withInt(toTs(from)), Variable.withInt(toTs(to))],
    ).getSingle();
    return r.read<int>('n');
  }

  // ---- workouts ------------------------------------------------------------

  Future<int> addWorkout(WorkoutsCompanion w) => into(workouts).insert(w);

  Future<void> updateWorkout(int id, WorkoutsCompanion w) =>
      (update(workouts)..where((x) => x.id.equals(id))).write(w);

  Future<void> deleteWorkout(int id) =>
      (delete(workouts)..where((x) => x.id.equals(id))).go();

  Future<Workout?> workout(int id) =>
      (select(workouts)..where((x) => x.id.equals(id))).getSingleOrNull();

  Stream<Workout?> watchWorkout(int id) =>
      (select(workouts)..where((x) => x.id.equals(id))).watchSingleOrNull();

  Future<List<Workout>> workoutsBetween(DateTime from, DateTime to) =>
      (select(workouts)
            ..where((x) => x.start.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(x) => OrderingTerm.asc(x.start)]))
          .get();

  Stream<List<Workout>> watchWorkoutsBetween(DateTime from, DateTime to) =>
      (select(workouts)
            ..where((x) => x.start.isBetweenValues(toTs(from), toTs(to) - 1))
            ..orderBy([(x) => OrderingTerm.asc(x.start)]))
          .watch();

  /// Inserts or refreshes the derived row for a band workout (matched on
  /// source 'band' and start). Keeps the user's RPE, title and sport edits.
  Future<void> upsertBandWorkout(WorkoutsCompanion row) => transaction(
    () async {
      final existing =
          await (select(workouts)..where(
                (x) =>
                    x.source.equals('band') & x.start.equals(row.start.value),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await into(workouts).insert(row);
      } else {
        await (update(workouts)..where((x) => x.id.equals(existing.id))).write(
          WorkoutsCompanion(
            end: row.end,
            strain: row.strain,
            trimp: row.trimp,
            avgHr: row.avgHr,
            maxHr: row.maxHr,
            zones: row.zones,
          ),
        );
      }
    },
  );

  /// Every workout, newest first, optionally only one sport.
  Stream<List<Workout>> watchAllWorkouts({String? sport, int limit = 500}) {
    final q = select(workouts)
      ..orderBy([(x) => OrderingTerm.desc(x.start)])
      ..limit(limit);
    if (sport != null) q.where((x) => x.sport.equals(sport));
    return q.watch();
  }

  /// Replaces unconfirmed auto-detected workouts in [from, to) with [rows].
  /// Live and confirmed ones stay; rows overlapping them are dropped.
  Future<void> replaceAutoWorkouts(
    DateTime from,
    DateTime to,
    List<WorkoutsCompanion> rows,
  ) => transaction(() async {
    await (delete(workouts)..where(
          (x) =>
              x.source.equals('auto') &
              x.confirmed.equals(false) &
              x.start.isBetweenValues(toTs(from), toTs(to) - 1),
        ))
        .go();
    final kept = await workoutsBetween(
      from.subtract(const Duration(hours: 6)),
      to,
    );
    for (final r in rows) {
      final s = r.start.value, e = r.end.value;
      if (kept.any((k) => k.start < e && s < k.end)) continue;
      await into(workouts).insert(r);
    }
  });

  // ---- plan ----------------------------------------------------------------

  Future<void> putPlanDay(PlanDaysCompanion p) =>
      into(planDays).insertOnConflictUpdate(p);

  Future<PlanDay?> planDay(DateTime day) => (select(
    planDays,
  )..where((p) => p.date.equals(dateKey(day)))).getSingleOrNull();

  Future<List<PlanDay>> planBetween(DateTime from, DateTime to) =>
      (select(planDays)
            ..where((p) => p.date.isBetweenValues(dateKey(from), dateKey(to)))
            ..orderBy([(p) => OrderingTerm.asc(p.date)]))
          .get();

  /// Records what the user or coach decided for [day] (Tempo Coach).
  /// [minute] null keeps the planned minute; [session] swaps the session.
  Future<void> setPlanIntent(
    DateTime day,
    String status, {
    required String source,
    String? slot,
    int? minute,
    String? session,
  }) => (update(planDays)..where((p) => p.date.equals(dateKey(day)))).write(
    PlanDaysCompanion(
      status: Value(status),
      statusSource: Value(source),
      statusAt: Value(toTs(DateTime.now())),
      slot: slot == null ? const Value.absent() : Value(slot),
      plannedMinute: minute == null ? const Value.absent() : Value(minute),
      session: session == null ? const Value.absent() : Value(session),
    ),
  );

  // ---- nudge log -----------------------------------------------------------

  Future<void> logNudge(NudgeLogCompanion row) => into(nudgeLog).insert(row);

  Future<List<NudgeLogData>> nudgesSince(DateTime from) =>
      (select(nudgeLog)
            ..where((n) => n.ts.isBiggerOrEqualValue(toTs(from)))
            ..orderBy([(n) => OrderingTerm.asc(n.id)]))
          .get();

  Stream<List<PlanDay>> watchPlanBetween(DateTime from, DateTime to) =>
      (select(planDays)
            ..where((p) => p.date.isBetweenValues(dateKey(from), dateKey(to)))
            ..orderBy([(p) => OrderingTerm.asc(p.date)]))
          .watch();

  // ---- sync log ------------------------------------------------------------

  Future<void> logSync(
    String summary,
    String result, {
    Duration? took,
    DateTime? at,
  }) => into(syncLog).insert(
    SyncLogCompanion.insert(
      ts: toTs(at ?? DateTime.now()),
      summary: summary,
      result: result,
      durationMs: Value(took?.inMilliseconds),
    ),
  );

  Stream<List<SyncLogData>> watchSyncLog({int limit = 20}) =>
      (select(syncLog)
            ..orderBy([(l) => OrderingTerm.desc(l.ts)])
            ..limit(limit))
          .watch();

  // ---- longevity ----------------------------------------------------------

  Future<void> putLongevity(LongevityCompanion row) =>
      into(longevity).insertOnConflictUpdate(row);

  /// Snapshots oldest first.
  Future<List<LongevitySnapshot>> longevitySince(DateTime from) =>
      (select(longevity)
            ..where((l) => l.date.isBiggerOrEqualValue(dateKey(from)))
            ..orderBy([(l) => OrderingTerm.asc(l.date)]))
          .get();

  Stream<List<LongevitySnapshot>> watchLongevity() =>
      (select(longevity)..orderBy([(l) => OrderingTerm.asc(l.date)])).watch();

  // ---- restore -------------------------------------------------------------

  /// Tables a JSON export can restore, in insert order.
  static const restorable = [
    ...rawTables,
    'sleep_sessions',
    'daily_scores',
    'baselines',
    'journal',
    'morning_feel',
    'sync_state',
    'workouts',
    'plan_days',
    'sync_log',
    'longevity',
    'nudge_log',
  ];

  /// Restores rows from an export (`table → rows`). Raw rows already here
  /// are kept (insert-or-ignore, so the append-only rule holds); derived
  /// rows are replaced. Workouts and log rows get fresh ids, and a workout
  /// already stored at the same start is skipped. Columns this schema does
  /// not have are dropped. Returns rows written per table.
  Future<Map<String, int>> restoreRows(
    Map<String, List<Map<String, Object?>>> data,
  ) => transaction(() async {
    final out = <String, int>{};
    for (final t in restorable) {
      final rows = data[t];
      if (rows == null || rows.isEmpty) continue;
      final cols = {
        for (final r in await customSelect('PRAGMA table_info($t)').get())
          r.read<String>('name'),
      };
      final fresh = t == 'workouts' || t == 'sync_log' || t == 'nudge_log';
      final verb = rawTables.contains(t)
          ? 'INSERT OR IGNORE'
          : fresh
          ? 'INSERT'
          : 'INSERT OR REPLACE';
      var n = 0;
      for (final r in rows) {
        if (t == 'workouts' && r['start'] is int) {
          final dup = await customSelect(
            'SELECT 1 FROM workouts WHERE start = ?',
            variables: [Variable.withInt(r['start'] as int)],
          ).get();
          if (dup.isNotEmpty) continue;
        }
        final keys = [
          for (final k in r.keys)
            if (cols.contains(k) && !(fresh && k == 'id')) k,
        ];
        if (keys.isEmpty) continue;
        n += await customUpdate(
          // Quoted: od_events has a column named "drop".
          '$verb INTO $t (${keys.map((k) => '"$k"').join(', ')}) '
          'VALUES (${List.filled(keys.length, '?').join(', ')})',
          variables: [for (final k in keys) _variable(r[k])],
          updates: {
            for (final tb in allTables)
              if (tb.actualTableName == t) tb,
          },
          updateKind: UpdateKind.insert,
        );
      }
      out[t] = n;
    }
    return out;
  });

  static Variable<Object> _variable(Object? v) => switch (v) {
    null => const Variable(null),
    int i => Variable.withInt(i),
    double d => Variable.withReal(d),
    bool b => Variable.withBool(b),
    _ => Variable.withString('$v'),
  };
}
