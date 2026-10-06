import 'dart:convert';
import 'dart:math' as math;

import 'package:band_ble/band_ble.dart' show bandSportNames, bandSportTitles;

import 'package:drift/drift.dart';
import 'package:health_source/health_source.dart' as hs;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'data_source.dart';
import 'minutes.dart';
import 'pause.dart';
import 'profile.dart' show Keys, sportLabel;

const hrMaxKey = 'hr_max';

/// Minutes between all-day HR samples. 1, 10 or 30. See [SettingsCommands].
const hrIntervalKey = 'hr_interval';

/// Derives sleep sessions, daily scores and baselines from raw samples of
/// the active data source (see data_source.dart).
class ScoreService {
  ScoreService(this.db);
  final st.TempoDb db;

  /// Recomputes every day from [from] (local date) to today, in order, since
  /// each day's history feeds the next. Never before the active source's
  /// first data: earlier days keep the scores another source gave them.
  Future<int> recomputeFrom(DateTime from) async {
    final params = sc.ScoringParams(
      defaultHrMax: int.tryParse(await db.setting(hrMaxKey) ?? '') ?? 190,
    );
    final source = await loadDataSource(db);
    final first = await firstDataMinute(db, source: source);
    final today = _day(DateTime.now());
    _pauses = await loadPauses(db);
    var day = _day(from);
    if (first != null && day.isBefore(_day(first))) day = _day(first);
    var n = 0;
    while (!day.isAfter(today)) {
      await _scoreOne(day, params, source);
      n++;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    await _baselines(today, source);
    return n;
  }

  /// Full recompute when the algorithm version changed. Only days of the
  /// active source count: another source's days can't be rescored (their
  /// data isn't read any more) and stay as they were.
  Future<void> recomputeIfStale() async {
    final source = await loadDataSource(db);
    final first = await firstDataMinute(db, source: source);
    if (first == null) return;
    final stale = [
      for (final d in await db.staleScores(sc.algoVersion, source: source.key))
        if (!parseDateKey(d.date).isBefore(_day(first))) d,
    ];
    if (stale.isEmpty) return;
    await recomputeFrom(first);
  }

  List<Pause> _pauses = const [];

  Future<void> _scoreOne(
    DateTime day,
    sc.ScoringParams p,
    DataSource source,
  ) async {
    final from = day.subtract(const Duration(hours: 12));
    final to = day.add(const Duration(hours: 36));
    // A day the active source has nothing for keeps a score another source
    // gave it (switching back to the band must not blank the Health weeks).
    final existing = await db.scoreFor(day);
    if (existing != null &&
        existing.source != source.key &&
        !await hasDataBetween(
          db,
          day,
          day.add(const Duration(days: 1)),
          source: source,
        )) {
      return;
    }
    final minutes = (await loadMinutes(db, from, to, source: source)).minutes;
    final stress = [
      for (final s in await loadStress(db, from, to, source: source))
        sc.StressReading(st.fromTs(s.ts), s.value),
    ];
    // Paused days (ill, travelling) don't shape baselines or calibration.
    final history = [
      for (final d in await db.scoresBefore(day, limit: 90))
        if (!isPaused(_pauses, parseDateKey(d.date))) toScoring(d),
    ];
    double? hrv, sourceRhr;
    String? hrvKind;
    var records = const <hs.HealthRecord>[];
    if (source.isHealth) {
      records = await loadHealthRecords(db, from, to);
      final night = sc.daySleep(date: day, minutes: minutes).night;
      if (night != null) {
        final h = hs.nightHrv(records, night.start, night.end);
        hrv = h?.ms;
        hrvKind = h?.kind.name;
      }
      sourceRhr = hs.sourceRestingHr(records, day);
    }
    final s = sc.scoreDay(
      date: day,
      minutes: minutes,
      stress: stress,
      history: history,
      p: p,
      extraTrimp: await _strengthExtra(day),
      source: source.key,
      hrv: hrv,
      hrvKind: hrvKind,
      sourceRhr: sourceRhr,
    );
    await db.upsertScore(fromScoring(s));
    await _activities(day, s, minutes, source: source, records: records);

    if (s.sleepStart != null && s.sleepEnd != null) {
      final night = sc.SleepSession(
        minutes
            .where(
              (m) =>
                  !m.ts.isBefore(s.sleepStart!) && m.ts.isBefore(s.sleepEnd!),
            )
            .toList(),
      );
      await db.replaceSleepSessions(s.sleepEnd!, s.sleepEnd!, [
        st.SleepSessionsCompanion.insert(
          start: st.toTs(s.sleepStart!),
          end: st.toTs(s.sleepEnd!),
          stages: jsonEncode({
            for (final stage in sc.Stage.values)
              stage.name: night.stage(stage).inMinutes,
          }),
          algoVersion: sc.algoVersion,
        ),
      ]);
    }
  }

  /// HR undercounts lifting: confirmed strength sessions with an RPE count
  /// as at least their session-RPE load (see sc.strengthCorrection).
  Future<double> _strengthExtra(DateTime day) async {
    final ws = await db.workoutsBetween(day, day.add(const Duration(days: 1)));
    var extra = 0.0;
    for (final w in ws) {
      if (w.sport != sc.Sport.strength.name || w.rpe == null) continue;
      if (w.source == 'auto' && !w.confirmed) continue;
      extra += sc.strengthCorrection(
        hrTrimp: w.trimp,
        rpe: w.rpe!,
        minutes: ((w.end - w.start) / 60).round(),
      );
    }
    return extra;
  }

  /// Auto-detects workouts on [day] and stores them as unconfirmed 'auto'
  /// rows. Live sessions and confirmed rows are kept.
  Future<void> _activities(
    DateTime day,
    sc.DailyScore s,
    List<sc.Minute> all, {
    required DataSource source,
    List<hs.HealthRecord> records = const [],
  }) async {
    final end = day.add(const Duration(days: 1));
    final mins = [
      for (final m in all)
        if (!m.ts.isBefore(day) && m.ts.isBefore(end)) m,
    ];
    if (mins.isEmpty) return;
    final found = sc.detectActivities(mins, hrMax: s.hrMax);
    final wake = s.sleepEnd ?? day;
    final rest = s.rhr ?? 60;
    double trimpTo(DateTime t) => sc.trimp(
      [
        for (final m in mins)
          if (!m.ts.isBefore(wake) && m.ts.isBefore(t)) m.hr,
      ],
      hrRest: rest,
      hrMax: s.hrMax.toDouble(),
    );
    List<int?> hrIn(DateTime a, DateTime b) => [
      for (final m in mins)
        if (!m.ts.isBefore(a) && m.ts.isBefore(b)) m.hr,
    ];

    // Workouts recorded on the band (or another app, via Health) come
    // first: confirmed, and auto detection then skips anything overlapping
    // them.
    final dismissed = await dismissedBandWorkouts(db);
    if (source.isHealth) {
      final ws = [
        for (final w in hs.healthWorkouts(records))
          if (!w.start.isBefore(day) &&
              w.start.isBefore(end) &&
              !dismissed.contains(st.toTs(w.start)))
            w,
      ];
      for (final w in ws) {
        final hrs = hrIn(w.start, w.end).whereType<int>().toList();
        final t0 = trimpTo(w.start), t1 = trimpTo(w.end);
        await db.upsertBandWorkout(
          st.WorkoutsCompanion.insert(
            start: st.toTs(w.start),
            end: st.toTs(w.end),
            sport: Value(w.sport?.name),
            title: w.sport == null ? w.title : sportLabel(w.sport),
            source: 'health',
            confirmed: const Value(true),
            strain: sc.strainFromTrimp(t1) - sc.strainFromTrimp(t0),
            trimp: t1 - t0,
            avgHr: Value(
              hrs.isEmpty
                  ? null
                  : (hrs.reduce((x, y) => x + y) / hrs.length).round(),
            ),
            maxHr: Value(hrs.isEmpty ? null : hrs.reduce(math.max)),
            zones: jsonEncode(sc.timeInZones(hrIn(w.start, w.end), s.hrMax)),
          ),
        );
      }
      // Deleted in Health (or dismissed): its derived row goes too.
      await db.removeHealthWorkoutsExcept(day, end, {
        for (final w in ws) st.toTs(w.start),
      });
      // Sessions timed in Tempo with no live heart rate (a Health source
      // has none): heart rate and strain come from the watch's minutes,
      // and are refreshed as late readings arrive.
      for (final w in await db.workoutsBetween(day, end)) {
        if (w.source != 'live') continue;
        final a = st.fromTs(w.start), z = st.fromTs(w.end);
        final live = await db.hrLiveSince(a);
        if (live.any((h) => h.ts < w.end)) continue;
        final hrs = hrIn(a, z).whereType<int>().toList();
        if (hrs.isEmpty) continue;
        final t0 = trimpTo(a), t1 = trimpTo(z);
        await db.updateWorkout(
          w.id,
          st.WorkoutsCompanion(
            strain: Value(sc.strainFromTrimp(t1) - sc.strainFromTrimp(t0)),
            trimp: Value(t1 - t0),
            avgHr: Value((hrs.reduce((x, y) => x + y) / hrs.length).round()),
            maxHr: Value(hrs.reduce(math.max)),
            zones: Value(jsonEncode(sc.timeInZones(hrIn(a, z), s.hrMax))),
          ),
        );
      }
    }
    for (final b
        in source.isHealth
            ? const <st.BandWorkoutRow>[]
            : await db.bandWorkoutsBetween(day, end)) {
      if (dismissed.contains(b.start)) continue;
      final a = st.fromTs(b.start), z = st.fromTs(b.end);
      final hrs = hrIn(a, z).whereType<int>().toList();
      final t0 = trimpTo(a), t1 = trimpTo(z);
      final sport = sc.Sport.values.asNameMap()[bandSportNames[b.kind]];
      await db.upsertBandWorkout(
        st.WorkoutsCompanion.insert(
          start: b.start,
          end: b.end,
          sport: Value(sport?.name),
          title:
              bandSportTitles[b.kind] ??
              'Band workout (type ${b.kind.toRadixString(16)})',
          source: 'band',
          confirmed: const Value(true),
          strain: sc.strainFromTrimp(t1) - sc.strainFromTrimp(t0),
          trimp: t1 - t0,
          avgHr: Value(
            hrs.isEmpty
                ? null
                : (hrs.reduce((x, y) => x + y) / hrs.length).round(),
          ),
          maxHr: Value(hrs.isEmpty ? null : hrs.reduce(math.max)),
          zones: jsonEncode(sc.timeInZones(hrIn(a, z), s.hrMax)),
        ),
      );
    }

    final rows = <st.WorkoutsCompanion>[];
    for (final a in found) {
      final t0 = trimpTo(a.start), t1 = trimpTo(a.end);
      final inside = hrIn(a.start, a.end);
      rows.add(
        st.WorkoutsCompanion.insert(
          start: st.toTs(a.start),
          end: st.toTs(a.end),
          sport: Value(a.sport?.name),
          title: sportLabel(a.sport),
          source: 'auto',
          strain: sc.strainFromTrimp(t1) - sc.strainFromTrimp(t0),
          trimp: t1 - t0,
          avgHr: Value(a.avgHr),
          maxHr: Value(a.maxHr),
          zones: jsonEncode(sc.timeInZones(inside, s.hrMax)),
        ),
      );
    }
    await db.replaceAutoWorkouts(day, end, rows);
  }

  Future<void> _baselines(DateTime today, DataSource source) async {
    final recent = [
      for (final d in await db.scoresBefore(
        today.add(const Duration(days: 1)),
        limit: 90,
      ))
        if (!isPaused(_pauses, parseDateKey(d.date)) && d.source == source.key)
          d,
    ].take(30).toList();
    void put(String metric, Iterable<double?> xs) {
      final b = sc.Baseline.of(xs);
      if (b != null) db.putBaseline(metric, 30, b.mean, b.sd);
    }

    put('rhr', recent.map((d) => d.rhr));
    put('hrv_proxy', recent.map((d) => d.hrvProxy));
    put('hrv', recent.map((d) => d.hrv));
    put('sleep_perf', recent.map((d) => d.sleepPerf));
    put('strain', recent.map((d) => d.strain));
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// Saves how hard a workout felt. Coach reads it at the next morning
/// adaptation; a strength session's day is rescored since RPE sets its load.
Future<void> saveRpe(st.TempoDb db, int workoutId, int rpe) async {
  await db.updateWorkout(workoutId, st.WorkoutsCompanion(rpe: Value(rpe)));
  final w = await db.workout(workoutId);
  if (w != null && w.sport == sc.Sport.strength.name) {
    final t = st.fromTs(w.start);
    await ScoreService(db).recomputeFrom(DateTime(t.year, t.month, t.day));
  }
}

/// Band workout starts the user deleted; never re-derived.
Future<Set<int>> dismissedBandWorkouts(st.TempoDb db) async {
  try {
    final raw = await db.setting(Keys.bandDismissed);
    return {for (final v in jsonDecode(raw ?? '[]') as List) v as int};
  } catch (_) {
    return {};
  }
}

Future<void> dismissBandWorkout(st.TempoDb db, int start) async {
  final s = await dismissedBandWorkouts(db)
    ..add(start);
  await db.putSetting(Keys.bandDismissed, jsonEncode(s.toList()));
}

DateTime parseDateKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

sc.DailyScore toScoring(st.DailyScore d) => sc.DailyScore(
  date: parseDateKey(d.date),
  strain: d.strain,
  trimp: d.trimp,
  hrMax: d.hrMax,
  sleepStart: d.sleepStart == null ? null : st.fromTs(d.sleepStart!),
  sleepEnd: d.sleepEnd == null ? null : st.fromTs(d.sleepEnd!),
  sleptHours: d.sleptHours,
  needHours: d.needHours,
  napHours: d.napHours,
  baseNeedHours: d.baseNeed,
  sleepPerf: d.sleepPerf,
  rhr: d.rhr,
  hrvProxy: d.hrvProxy,
  recovery: d.recovery,
  calibrating: d.calibrating,
  algoVersion: d.algoVersion,
  source: d.source,
  hrv: d.hrv,
  hrvKind: d.hrvKind,
);

st.DailyScoresCompanion fromScoring(sc.DailyScore s) =>
    st.DailyScoresCompanion.insert(
      date: st.dateKey(s.date),
      strain: s.strain,
      trimp: s.trimp,
      hrMax: s.hrMax,
      sleepPerf: Value(s.sleepPerf),
      sleptHours: Value(s.sleptHours),
      needHours: Value(s.needHours),
      napHours: Value(s.napHours),
      baseNeed: Value(s.baseNeedHours),
      sleepStart: Value(s.sleepStart == null ? null : st.toTs(s.sleepStart!)),
      sleepEnd: Value(s.sleepEnd == null ? null : st.toTs(s.sleepEnd!)),
      recovery: Value(s.recovery),
      rhr: Value(s.rhr),
      hrvProxy: Value(s.hrvProxy),
      calibrating: s.calibrating,
      algoVersion: s.algoVersion,
      source: Value(s.source),
      hrv: Value(s.hrv),
      hrvKind: Value(s.hrvKind),
    );
