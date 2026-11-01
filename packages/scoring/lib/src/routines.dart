/// Strength routines (U1, U3): a list of exercises with sets, reps and rest
/// you can start again. "Repeat last session" builds one from the newest
/// day's sets; saved routines are kept by name. Pure Dart.
library;

import 'coach.dart';
import 'picks.dart';
import 'strength.dart';

/// A strength session to start again. [items] use the library's names, so
/// the log and the progression find them like a pick's exercises.
final class Routine {
  const Routine(this.name, this.items);
  final String name;
  final List<Exercise> items;

  Map<String, Object?> toJson() => {
    'n': name,
    'x': [for (final e in items) e.toJson()],
  };

  static Routine fromJson(Map<String, dynamic> j) => Routine(j['n'] as String, [
    for (final e in (j['x'] as List? ?? const []))
      Exercise.fromJson((e as Map).cast<String, dynamic>()),
  ]);
}

/// The newest day in [sets] as a routine: its exercises in the order they
/// were first done, each with that day's number of sets and the reps of
/// its first set ("30 s" for a timed hold). Exercises not in the library
/// are left out. Null when there's nothing to repeat.
Routine? lastSessionRoutine(Iterable<SetLog> sets, {String? name}) {
  if (sets.isEmpty) return null;
  DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
  final last = sets
      .map((s) => dayOf(s.at))
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final day = [
    for (final s in sets)
      if (dayOf(s.at) == last) s,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final order = <String>[];
  final bySet = <String, List<SetLog>>{};
  for (final s in day) {
    if (exerciseById[s.exercise] == null) continue;
    if (!bySet.containsKey(s.exercise)) order.add(s.exercise);
    bySet.putIfAbsent(s.exercise, () => []).add(s);
  }
  if (order.isEmpty) return null;
  return Routine(name ?? 'Last session', [
    for (final id in order)
      () {
        final def = exerciseById[id]!;
        final xs = bySet[id]!;
        final first = xs.first;
        return Exercise(
          def.name,
          sets: xs.length,
          reps: def.kind == SetKind.timed
              ? '${first.seconds} s'
              : '${first.reps > 0 ? first.reps : 8}',
        );
      }(),
  ]);
}

/// Upper, lower, core or full body, from where the routine's working
/// muscles are: three quarters of the exercises on one side names it.
StrengthFocus routineFocus(Routine r) {
  final defs = [for (final x in r.items) ?exerciseByName(x.name)];
  if (defs.isEmpty) return StrengthFocus.full;
  final lower = defs.where((d) => d.lower).length;
  final upper = defs.where((d) => d.primary.any(upperMuscles.contains)).length;
  final core = defs.where((d) => d.primary.contains(Muscle.core)).length;
  final n = defs.length;
  if (lower >= .75 * n) return StrengthFocus.lower;
  if (upper >= .75 * n) return StrengthFocus.upper;
  if (core >= .75 * n) return StrengthFocus.core;
  return StrengthFocus.full;
}

/// The routine as a session the strength log can open: a moderate
/// strength session about as long as the plan's ([minutes]).
Session routineSession(Routine r, {int minutes = 45}) {
  final base = sessionTemplate('strength_full');
  return Session(
    key: base.key,
    title: r.name,
    sport: Sport.strength,
    segments: [Segment(minutes, 2)],
    strainLo: base.strainLo,
    strainHi: base.strainHi,
    intensity: base.intensity,
    detail: StrengthDetail(
      routineFocus(r),
      exercises: r.items,
      effort: 'Like last time; add weight where Tempo suggests it.',
      purpose: 'Your own routine, with the next weights from your history.',
    ),
  );
}
