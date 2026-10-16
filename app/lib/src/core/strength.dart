import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'block_service.dart' show loadBlock;
import 'coach_service.dart' show dayOf;

/// Strength log, progression and muscle freshness (decisions.md,
/// 2026-10-16). Sets live in `strength_sets` and belong to a workout by
/// time.

sc.SetLog setLog(st.StrengthSetRow r) => sc.SetLog(
  exercise: r.exercise,
  at: st.fromTs(r.ts),
  kg: r.kg,
  reps: r.reps,
  seconds: r.seconds,
  rir: r.rir,
);

/// Saves a ticked set now. Returns its row id.
Future<int> logSet(
  st.TempoDb db, {
  required String exercise,
  required int setNo,
  double kg = 0,
  int reps = 0,
  int seconds = 0,
  int? rir,
  String? superset,
  DateTime? at,
}) => db.addStrengthSet(
  st.StrengthSetsCompanion.insert(
    ts: st.toTs(at ?? DateTime.now()),
    exercise: exercise,
    setNo: setNo,
    kg: Value(kg),
    reps: Value(reps),
    seconds: Value(seconds),
    rir: Value(rir),
    superset: Value(superset),
  ),
);

/// Every past session of [exercise], before today, oldest first.
Future<List<sc.ExerciseSession>> exerciseHistory(
  st.TempoDb db,
  String exercise, {
  DateTime? before,
}) async {
  final cut = dayOf(before ?? DateTime.now());
  return sc.sessionsOf(exercise, [
    for (final r in await db.strengthHistory(exercise))
      if (st.fromTs(r.ts).isBefore(cut)) setLog(r),
  ]);
}

/// Today's readiness as the progression needs it: hold on a low day,
/// fewer sets in the block's lighter week.
Future<sc.LiftDay> liftDay(st.TempoDb db, sc.DayState state) async {
  final b = await loadBlock(db);
  if (b != null) {
    final i = b.weekOf(DateTime.now());
    if (i >= 0 && sc.phaseOf(b, i) == sc.Phase.deload) {
      return sc.LiftDay.lighter;
    }
  }
  return state == sc.DayState.go ? sc.LiftDay.normal : sc.LiftDay.hold;
}

/// The pick's exercises with your next weights filled in where you have
/// history (double progression on the pick's rep range).
Future<List<sc.Exercise>> withTargets(
  st.TempoDb db,
  List<sc.Exercise> xs,
  sc.LiftDay day,
) async {
  final out = <sc.Exercise>[];
  for (final x in xs) {
    final def = sc.exerciseByName(x.name);
    final range = sc.parseRepRange(x.reps);
    if (def == null || range == null) {
      out.add(x);
      continue;
    }
    final t = sc.nextTarget(
      def,
      await exerciseHistory(db, def.id),
      range: range,
      sets: x.sets,
      day: day,
    );
    out.add(t == null ? x : x.withTarget(t.kg, t.sets, '${t.reps}', t.why));
  }
  return out;
}

/// Muscle freshness now from the last week of sets and runs/rides; null
/// when nothing was lifted in the last 14 days (picks then fall back to
/// days since each focus).
Future<Map<sc.Muscle, double>?> loadFreshness(
  st.TempoDb db, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final recent = await db.strengthSetsBetween(
    at.subtract(const Duration(days: 14)),
    at,
  );
  if (recent.isEmpty) return null;
  final week = at.subtract(const Duration(days: 7));
  final cardio = [
    for (final w in await db.workoutsBetween(week, at))
      if ((w.sport == sc.Sport.running.name ||
              w.sport == sc.Sport.cycling.name) &&
          (w.source != 'auto' || w.confirmed))
        sc.LegCardio(
          at: st.fromTs(w.end),
          minutes: ((w.end - w.start) / 60).round(),
          hard: (w.rpe ?? 0) >= 7 || w.strain >= 10,
          running: w.sport == sc.Sport.running.name,
        ),
  ];
  return sc.freshness(
    sc.muscleLoad(
      [
        for (final r in recent)
          if (!st.fromTs(r.ts).isBefore(week)) setLog(r),
      ],
      at,
      cardio: cardio,
    ),
  );
}

/// TRIMP to add on [day] for lifting HR misses: each strength workout
/// counts as at least its session RPE or its logged sets, and sets logged
/// outside any workout count on their own.
Future<double> strengthExtraTrimp(st.TempoDb db, DateTime day) async {
  final end = day.add(const Duration(days: 1));
  final ws = await db.workoutsBetween(day, end);
  final sets = await db.strengthSetsBetween(day, end);
  final used = <int>{};
  var extra = 0.0;
  for (final w in ws) {
    if (w.source == 'auto' && !w.confirmed) continue;
    final inside = [
      for (final s in sets)
        // A minute's grace either side for ticks around start and finish.
        if (s.ts >= w.start - 60 && s.ts <= w.end + 60) s,
    ];
    if (w.sport != sc.Sport.strength.name && inside.isEmpty) continue;
    used.addAll(inside.map((s) => s.id));
    extra += sc.strengthCorrection(
      hrTrimp: w.trimp,
      rpe: w.rpe,
      minutes: ((w.end - w.start) / 60).round(),
      setsTrimp: sc.trimpFromSets(inside.map(setLog)),
    );
  }
  extra += sc.trimpFromSets([
    for (final s in sets)
      if (!used.contains(s.id)) setLog(s),
  ]);
  return extra;
}
