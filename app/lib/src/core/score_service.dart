import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'pause.dart';
import 'profile.dart' show sportLabel;
import 'stages.dart';

const hrMaxKey = 'hr_max';

/// Minutes between all-day HR samples. 1, 10 or 30. See [SettingsCommands].
const hrIntervalKey = 'hr_interval';

/// Derives sleep sessions, daily scores and baselines from raw samples.
class ScoreService {
  ScoreService(this.db);
  final st.TempoDb db;

  /// Recomputes every day from [from] (local date) to today, in order, since
  /// each day's history feeds the next.
  Future<int> recomputeFrom(DateTime from) async {
    final params = sc.ScoringParams(
      defaultHrMax: int.tryParse(await db.setting(hrMaxKey) ?? '') ?? 190,
    );
    final today = _day(DateTime.now());
    _pauses = await loadPauses(db);
    var day = _day(from);
    var n = 0;
    while (!day.isAfter(today)) {
      await _scoreOne(day, params);
      n++;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    await _baselines(today);
    return n;
  }

  /// Full recompute when the algorithm version changed.
  Future<void> recomputeIfStale() async {
    final stale = await db.staleScores(sc.algoVersion);
    if (stale.isEmpty) return;
    final first = await db.firstMinute();
    if (first != null) await recomputeFrom(first);
  }

  List<Pause> _pauses = const [];

  Future<void> _scoreOne(DateTime day, sc.ScoringParams p) async {
    final from = day.subtract(const Duration(hours: 12));
    final to = day.add(const Duration(hours: 36));
    final raw = await db.minutesBetween(from, to);
    final minutes = [
      for (final m in raw)
        sc.Minute(
          st.fromTs(m.ts),
          hr: m.hr,
          steps: m.steps,
          stage: stageForKind(m.kind),
        ),
    ];
    final stress = [
      for (final s in await db.stressBetween(from, to))
        sc.StressReading(st.fromTs(s.ts), s.value),
    ];
    // Paused days (ill, travelling) don't shape baselines or calibration.
    final history = [
      for (final d in await db.scoresBefore(day, limit: 90))
        if (!isPaused(_pauses, parseDateKey(d.date))) toScoring(d),
    ];
    final s = sc.scoreDay(
      date: day,
      minutes: minutes,
      stress: stress,
      history: history,
      p: p,
      extraTrimp: await _strengthExtra(day),
    );
    await db.upsertScore(fromScoring(s));
    await _activities(day, s, minutes);

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
    List<sc.Minute> all,
  ) async {
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
    final rows = <st.WorkoutsCompanion>[];
    for (final a in found) {
      final t0 = trimpTo(a.start), t1 = trimpTo(a.end);
      final inside = [
        for (final m in mins)
          if (!m.ts.isBefore(a.start) && m.ts.isBefore(a.end)) m.hr,
      ];
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

  Future<void> _baselines(DateTime today) async {
    final recent = [
      for (final d in await db.scoresBefore(
        today.add(const Duration(days: 1)),
        limit: 60,
      ))
        if (!isPaused(_pauses, parseDateKey(d.date))) d,
    ].take(30).toList();
    void put(String metric, Iterable<double?> xs) {
      final b = sc.Baseline.of(xs);
      if (b != null) db.putBaseline(metric, 30, b.mean, b.sd);
    }

    put('rhr', recent.map((d) => d.rhr));
    put('hrv_proxy', recent.map((d) => d.hrvProxy));
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
    );
