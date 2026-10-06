import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'profile.dart';

/// Ratings or recoveries needed in a week before they count toward its
/// outcome; with fewer, that signal is left out.
const outcomeMinDays = 3;

/// The training goal, or null when the plan is the same week every week.
Future<sc.TrainingBlock?> loadBlock(st.TempoDb db) async {
  final raw = await db.setting(Keys.coachBlock);
  if (raw == null || raw.isEmpty) return null;
  try {
    return sc.TrainingBlock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return null;
  }
}

/// Starts [goal] this week (an event on [event]), or clears it with null,
/// then rebuilds this week's plan from today.
Future<void> saveBlock(
  st.TempoDb db,
  sc.BlockGoal? goal, {
  DateTime? event,
  DateTime? now,
}) async {
  final today = dayOf(now ?? DateTime.now());
  await db.putSetting(
    Keys.coachBlock,
    goal == null
        ? ''
        : jsonEncode(
            sc.TrainingBlock(
              goal: goal,
              start: mondayOf(today),
              event: event,
            ).toJson(),
          ),
  );
  await CoachService(db).ensureWeek(today, rebuild: true);
}

/// How the week starting [monday] went: sessions done against the plan
/// (a session done easier counts half), mean recovery and mean feel.
Future<sc.WeekOutcome> weekOutcome(st.TempoDb db, DateTime monday) async {
  final sun = monday.add(const Duration(days: 6));
  final rows = await db.planBetween(monday, sun);
  var planned = 0;
  var done = 0.0;
  for (final r in rows) {
    final s = sc.Session.fromJson(
      jsonDecode(r.session) as Map<String, dynamic>,
    );
    if (s.isRest) continue;
    planned++;
    if (r.status == sc.Intent.done.name) {
      done += 1;
      continue;
    }
    final d = DateTime.parse(r.date);
    final ws = await db.workoutsBetween(d, d.add(const Duration(days: 1)));
    final m = sc.matchSession(s, [for (final w in ws) doneWorkout(w)]);
    done += switch (m.kind) {
      sc.MatchKind.done => 1,
      sc.MatchKind.doneEasier => .5,
      _ => 0,
    };
  }
  final scores = await db.scoresBetween(monday, sun);
  final recs = [
    for (final s in scores)
      if (!s.calibrating && s.recovery != null) s.recovery!,
  ];
  final feel = [
    for (final f in await db.feelSince(monday))
      if (DateTime.parse(f.date).isBefore(sun.add(const Duration(days: 1))))
        f.feel.toDouble(),
  ];
  double? mean(List<double> xs) => xs.length < outcomeMinDays
      ? null
      : xs.reduce((a, b) => a + b) / xs.length;
  return sc.WeekOutcome(
    planned: planned,
    done: done,
    recovery: mean(recs),
    feel: mean(feel),
  );
}

/// The block week for [monday], replaying every finished week since the
/// block began. Null with no goal, or outside the block.
Future<sc.BlockWeek?> blockWeekFor(st.TempoDb db, DateTime monday) async {
  final b = await loadBlock(db);
  if (b == null) return null;
  final past = <sc.WeekOutcome>[];
  for (
    var m = mondayOf(b.start);
    m.isBefore(monday);
    m = DateTime(m.year, m.month, m.day + 7)
  ) {
    past.add(await weekOutcome(db, m));
  }
  return sc.blockWeek(b, monday, past);
}
