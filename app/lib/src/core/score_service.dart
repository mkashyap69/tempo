import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'stages.dart';

const hrMaxKey = 'hr_max';

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
    final history = (await db.scoresBefore(day)).map(toScoring).toList();
    final s = sc.scoreDay(
      date: day,
      minutes: minutes,
      stress: stress,
      history: history,
      p: p,
    );
    await db.upsertScore(fromScoring(s));

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

  Future<void> _baselines(DateTime today) async {
    final recent = await db.scoresBefore(
      today.add(const Duration(days: 1)),
      limit: 30,
    );
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
      sleepStart: Value(s.sleepStart == null ? null : st.toTs(s.sleepStart!)),
      sleepEnd: Value(s.sleepEnd == null ? null : st.toTs(s.sleepEnd!)),
      recovery: Value(s.recovery),
      rhr: Value(s.rhr),
      hrvProxy: Value(s.hrvProxy),
      calibrating: s.calibrating,
      algoVersion: s.algoVersion,
    );
