import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'everyday.dart' show loadBodySignals;
import 'today.dart';

/// Today's three picks (scoring/picks.dart), from everything Tempo knows:
/// readiness and the day's state, body signals, today's strain so far,
/// the time to bed, the coach's plan for today and tomorrow, the last two
/// weeks of workouts and the profile (goal, sports, games, minutes).
Future<List<sc.Pick>> loadPicks(
  st.TempoDb db,
  TodayData t, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final signals = await loadBodySignals(db, day: t.day);
  final nowMin = at.hour * 60 + at.minute;
  var toBed = t.bedtimeMinute - nowMin;
  // A bedtime after midnight (00:30) is later tonight, not this morning.
  if (toBed < -6 * 60) toBed += 1440;
  final tomorrow = DateTime(t.day.year, t.day.month, t.day.day + 1);
  sc.Session? tomorrowPlan;
  for (final r in t.week) {
    if (r.date == st.dateKey(tomorrow)) tomorrowPlan = _session(r.session);
  }
  return sc.dailyPicks(
    sc.PickContext(
      today: t.day,
      state: t.state,
      targetHi: t.target.hi,
      strainSoFar: t.strain,
      unwell:
          t.rhrFlag == sc.RhrFlag.illness || signals.level == sc.BodyLevel.rest,
      shortNight: t.shortNight,
      goal: t.profile.goal,
      likes: t.profile.likes,
      games: t.profile.games,
      maxMinutes: t.profile.maxMinutes,
      minutesToBed: toBed,
      planned: t.plan == null || t.plan!.isRest ? null : t.plan,
      tomorrow: tomorrowPlan,
      recent: await recentSessions(db, t.day),
    ),
  );
}

sc.Session? _session(String json) {
  try {
    return sc.Session.fromJson(jsonDecode(json) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// The last 14 days of workouts as the picks need them. The plan for each
/// day names the run type or strength focus when the workout matched it;
/// the title names the game.
Future<List<sc.RecentSession>> recentSessions(
  st.TempoDb db,
  DateTime today,
) async {
  final from = today.subtract(const Duration(days: 14));
  final plans = {
    for (final p in await db.planBetween(from, today))
      p.date: _session(p.session),
  };
  final out = <sc.RecentSession>[];
  for (final w in await db.workoutsBetween(from, today)) {
    if (w.source == 'auto' && !w.confirmed && (w.end - w.start) < 600) {
      continue;
    }
    final d = doneWorkout(w);
    final day = dayOf(d.start);
    final plan = plans[st.dateKey(day)];
    final sameSport = plan != null && plan.sport == d.sport;
    final fromPlan = w.plan == null ? null : _session(w.plan!);
    final key = fromPlan?.key ?? (sameSport ? plan.key : null);
    out.add(
      sc.RecentSession(
        day: day,
        sport: d.sport,
        hard:
            d.hardMinutes >= sc.hardMinutesNeeded ||
            w.strain >= 12 ||
            (fromPlan?.isHard ?? false),
        minutes: d.minutes,
        key: key,
        focus: d.sport == sc.Sport.strength && key != null
            ? sc.focusForKey(key)
            : null,
        game: sc.gameInTitle(w.title),
      ),
    );
  }
  return out;
}
