import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'data_source.dart';
import 'longevity_service.dart';
import 'profile.dart';
import 'today.dart';

/// What Tempo Coach shows beyond today's session: the focus lever's
/// actions for today, how each day of the week went, and the week-level
/// checks (realign, WHO floor, monotony).
class CoachExtras {
  CoachExtras({
    required this.actions,
    required this.week,
    required this.realign,
    required this.floor,
    required this.monotony,
    required this.focus,
    required this.progress,
  });

  final List<sc.LeverAction> actions;

  /// Monday first; null for days still ahead.
  final List<sc.DayStatus?> week;
  final bool realign;
  final sc.FloorGap? floor;
  final bool monotony;
  final LongevityFocus? focus;
  final (double, double)? progress;
}

/// End of a past day, in "minutes since that midnight", so anything not
/// done counts as missed.
const _endOfDay = 24 * 60 + 600;

/// How a planned day went. Past days are judged at their end; [at] on
/// the same day judges it as of that moment.
Future<sc.DayStatus?> statusOf(
  st.TempoDb db,
  st.PlanDay row,
  DateTime day, {
  DateTime? at,
}) async {
  final s = sc.Session.fromJson(
    jsonDecode(row.session) as Map<String, dynamic>,
  );
  if (s.isRest) return sc.DayStatus.rest;
  final ws = await db.workoutsBetween(day, day.add(const Duration(days: 1)));
  return sc.deriveStatus(
    plan: s,
    intent: sc.Intent.values.asNameMap()[row.status] ?? sc.Intent.planned,
    match: sc.matchSession(s, [for (final w in ws) doneWorkout(w)]),
    now: at != null && dayOf(at) == day ? at.hour * 60 + at.minute : _endOfDay,
    bedtime: 23 * 60,
    plannedMinute: row.plannedMinute,
  );
}

Future<CoachExtras> loadCoachExtras(st.TempoDb db, TodayData t) async {
  final today = t.day;
  final mon = mondayOf(today);
  final coach = CoachService(db);
  final rows = await coach.ensureWeek(today);
  final todayIdx = today.weekday - 1;

  final week = <sc.DayStatus?>[];
  for (var i = 0; i < 7; i++) {
    final d = mon.add(Duration(days: i));
    if (i < todayIdx && i < rows.length) {
      week.add(await statusOf(db, rows[i], d));
    } else if (i == todayIdx) {
      week.add(t.status);
    } else {
      week.add(null);
    }
  }

  // The trailing 7 days (yesterday back), for the realign prompt.
  final back = await db.planBetween(
    today.subtract(const Duration(days: 7)),
    today.subtract(const Duration(days: 1)),
  );
  final trailing = [
    for (final r in back) await statusOf(db, r, parseKey(r.date)),
  ];

  // WHO floor: Z2+ minutes and strength days this week, plus what's planned.
  final ws = await db.workoutsBetween(mon, today.add(const Duration(days: 1)));
  var moderate = 0;
  final strengthDays = <String>{};
  for (final w in ws) {
    final d = doneWorkout(w);
    if (d.zoneMinutes.length == 5) {
      moderate += d.zoneMinutes.skip(1).fold<int>(0, (a, z) => a + z);
    }
    if (d.sport == sc.Sport.strength) {
      strengthDays.add(st.dateKey(st.fromTs(w.start)));
    }
  }
  var minutesLeft = 0, strengthLeft = 0;
  for (var i = todayIdx; i < rows.length; i++) {
    if (i == todayIdx &&
        t.status != sc.DayStatus.pending &&
        t.status != sc.DayStatus.moved) {
      continue;
    }
    final s = sc.Session.fromJson(
      jsonDecode(rows[i].session) as Map<String, dynamic>,
    );
    if (s.isRest) continue;
    if (s.sport == sc.Sport.strength) {
      strengthLeft++;
    } else if (s.sport != sc.Sport.yoga) {
      minutesLeft += s.minutes;
    }
  }
  final floor = sc.weeklyFloor(
    moderateMinutes: moderate,
    strengthDays: strengthDays.length,
    plannedMinutesLeft: minutesLeft,
    plannedStrengthLeft: strengthLeft,
  );

  // Days without data are left out, not counted as rest.
  final trimp = await dailyTrimp(db, today, days: 35);
  final last7 = trimp.take(7).whereType<double>().toList();
  final known28 = trimp.take(28).whereType<double>().toList();
  final mean28 = known28.length >= sc.loadMinDays
      ? 7 * known28.fold<double>(0, (a, v) => a + v) / known28.length
      : double.infinity;

  var focus = await loadFocus(db);
  if (focus != null && !focus.activeOn(today)) focus = null;
  final progress = focus == null
      ? null
      : await focusProgress(db, focus, t.profile);
  final steps = await stepsToday(db, DateTime.now());
  final plan = t.plan;
  final daysLeft = 7 - todayIdx;
  final actions = sc.leverActions(
    focus: focus?.lever,
    nowMinute: DateTime.now().hour * 60 + DateTime.now().minute,
    wakeMinute: t.wakeMinute,
    bedtime: t.bedtimeMinute,
    stepsToday: steps,
    stepTarget: focus?.lever == sc.Lever.steps && progress != null
        ? progress.$2
        : 10000,
    activeWeek: focus?.lever == sc.Lever.activeMinutes && progress != null
        ? progress.$1
        : 0,
    activeTarget: focus?.lever == sc.Lever.activeMinutes && progress != null
        ? progress.$2
        : 150,
    daysLeft: daysLeft,
    strengthWeek: focus?.lever == sc.Lever.strength && progress != null
        ? progress.$1.round()
        : strengthDays.length,
    hardToday: plan?.isHard ?? false,
    strengthToday: plan?.sport == sc.Sport.strength,
  );
  final dismissed = DateTime.tryParse(
    await db.setting(Keys.realignDismissed) ?? '',
  );
  final recentlyDismissed =
      dismissed != null && today.difference(dismissed).inDays < 7;
  return CoachExtras(
    actions: actions,
    week: week,
    realign:
        !recentlyDismissed && sc.needsRealign([for (final s in trailing) ?s]),
    floor: daysLeft <= 3 ? floor : null,
    monotony: sc.monotonyHigh(last7, mean28),
    focus: focus,
    progress: progress,
  );
}

DateTime parseKey(String k) => DateTime.parse(k);

/// Today's steps: the band's own running total when it was read today
/// (current to the minute of the last sync), else the synced minutes. A
/// Health source has only the synced minutes.
Future<int> stepsToday(st.TempoDb db, DateTime now) async {
  final day = DateTime(now.year, now.month, now.day);
  if ((await loadDataSource(db)).isHealth) {
    return db.stepsBetween(day, now, health: true);
  }
  final synced = await db.stepsBetween(day, now);
  final raw = await db.setting(Keys.stepsNow);
  if (raw == null || !raw.contains('|')) return synced;
  final at = DateTime.tryParse(raw.split('|').first);
  final n = int.tryParse(raw.split('|').last);
  if (at == null || n == null || at.isBefore(day) || at.isAfter(now)) {
    return synced;
  }
  return n > synced ? n : synced;
}
