import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'longevity_service.dart' show loadFocus;
import 'pause.dart';
import 'profile.dart';

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime mondayOf(DateTime t) =>
    dayOf(t).subtract(Duration(days: t.weekday - 1));

/// Daily TRIMP, newest first, for the last [days] days ending [day]. A day
/// is null when it has no data: paused, no score, or the band worn for
/// under [sc.loadMinWornMinutes] (off charging, not synced), so a gap
/// doesn't read as a rest day.
Future<List<double?>> dailyTrimp(
  st.TempoDb db,
  DateTime day, {
  int days = 28 * 4,
}) async {
  final from = day.subtract(Duration(days: days - 1));
  final rows = await db.scoresBetween(from, day);
  final byDate = {for (final r in rows) r.date: r.trimp};
  if (rows.isEmpty) return [];
  final first = DateTime.parse(rows.first.date);
  final pauses = await loadPauses(db);
  final out = <double?>[];
  for (
    var d = dayOf(day);
    !d.isBefore(first);
    d = DateTime(d.year, d.month, d.day - 1)
  ) {
    final t = byDate[st.dateKey(d)];
    final next = DateTime(d.year, d.month, d.day + 1);
    final known =
        t != null &&
        !isPaused(pauses, d) &&
        await db.hrMinutesBetween(d, next) >= sc.loadMinWornMinutes;
    out.add(known ? t : null);
  }
  return out;
}

Future<sc.CardioLoad> loadFor(st.TempoDb db, DateTime day) async =>
    sc.cardioLoad(await dailyTrimp(db, day));

/// A stored workout as the session matcher sees it.
sc.DoneWorkout doneWorkout(st.Workout w) {
  List<int> zones;
  try {
    zones = [for (final z in jsonDecode(w.zones) as List) (z as num).round()];
  } catch (_) {
    zones = const [];
  }
  return sc.DoneWorkout(
    start: st.fromTs(w.start),
    minutes: ((w.end - w.start) / 60).round(),
    sport: sc.Sport.values.asNameMap()[w.sport],
    zoneMinutes: zones,
    strain: w.strain,
  );
}

/// Owns the plan in `plan_days`: builds each week from the profile and runs
/// the morning adaptation once after the first sync of the day.
class CoachService {
  CoachService(this.db);
  final st.TempoDb db;

  /// Makes sure every day of [day]'s week has a plan row.
  Future<List<st.PlanDay>> ensureWeek(
    DateTime day, {
    bool rebuild = false,
  }) async {
    final mon = mondayOf(day);
    final sun = mon.add(const Duration(days: 6));
    final existing = await db.planBetween(mon, sun);
    if (existing.length == 7 && !rebuild) return existing;
    final profile = await loadAppProfile(db) ?? const Profile();
    final latest = await db.scoresBefore(
      dayOf(day).add(const Duration(days: 1)),
      limit: 1,
    );
    final general = latest.isEmpty || latest.first.calibrating;
    final focus = await loadFocus(db);
    final week = sc.weekPlan(
      profile.prefs,
      general: general,
      focus: focus != null && focus.activeOn(mon.add(const Duration(days: 6)))
          ? focus.lever
          : null,
    );
    final today = dayOf(DateTime.now());
    final have = {for (final e in existing) e.date: e};
    for (var i = 0; i < 7; i++) {
      final d = mon.add(Duration(days: i));
      // Never rewrite the past; keep adapted days unless rebuilding.
      if (d.isBefore(today) && have.containsKey(st.dateKey(d))) continue;
      if (!rebuild && have.containsKey(st.dateKey(d))) continue;
      await db.putPlanDay(
        st.PlanDaysCompanion.insert(
          date: st.dateKey(d),
          session: jsonEncode(week[i].toJson()),
          general: general,
          status: const Value('planned'),
          plannedMinute: const Value(null),
          statusSource: const Value(null),
          algoVersion: const Value('coach-1'),
        ),
      );
    }
    return db.planBetween(mon, sun);
  }

  /// Days since the last session with ≥ 5 min in Z4–Z5, or null.
  Future<int?> daysSinceHard(DateTime day) async {
    final ws = await db.workoutsBetween(
      day.subtract(const Duration(days: 14)),
      day,
    );
    for (final w in ws.reversed) {
      final z = (jsonDecode(w.zones) as List).cast<num>();
      if (z.length == 5 && z[3] + z[4] >= 5) {
        return dayOf(day).difference(dayOf(st.fromTs(w.start))).inDays;
      }
    }
    return null;
  }

  /// How the last rated sessions (7 days) felt against their plan. Guided
  /// sessions compare with the planned intensity; others with the
  /// intensity their strain implies.
  Future<sc.Effort> effort(DateTime day) async {
    final ws = await db.workoutsBetween(
      day.subtract(const Duration(days: 7)),
      day,
    );
    final rated = <(int, sc.Intensity)>[];
    for (final w in ws.reversed) {
      if (w.rpe == null) continue;
      sc.Intensity planned;
      try {
        planned = w.plan == null
            ? sc.intensityForStrain(w.strain)
            : sc.Session.fromJson(jsonDecode(w.plan!) as Map<String, dynamic>)
                  .intensity;
      } catch (_) {
        planned = sc.intensityForStrain(w.strain);
      }
      rated.add((w.rpe!, planned));
    }
    return sc.effortTrend(rated);
  }

  /// Records what the user decided for [day] (Tempo Coach intent):
  /// skipped, moved (with a new minute and optionally a new session),
  /// done, or back to planned.
  Future<void> setIntent(
    DateTime day,
    sc.Intent intent, {
    String source = 'user',
    int? minute,
    String? slot,
    sc.Session? session,
  }) async {
    await ensureWeek(day);
    if (session != null) {
      final row = await db.planDay(day);
      await db.putPlanDay(
        st.PlanDaysCompanion.insert(
          date: st.dateKey(day),
          session: jsonEncode(session.toJson()),
          original: Value(row?.original ?? row?.session),
          reason: Value('· Moved to later today'),
          adaptedAt: Value(st.toTs(DateTime.now())),
          general: row?.general ?? false,
          algoVersion: const Value(sc.coachDayAlgo),
        ),
      );
    }
    await db.setPlanIntent(
      day,
      intent.name,
      source: source,
      minute: minute,
      slot: slot,
    );
  }

  /// Swaps today's session (Easier, Rest today) and keeps the original.
  Future<void> swapToday(sc.Session to, String why) async {
    final day = dayOf(DateTime.now());
    await ensureWeek(day);
    final row = await db.planDay(day);
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: st.dateKey(day),
        session: jsonEncode(to.toJson()),
        original: Value(row?.original ?? row?.session),
        reason: Value('· $why'),
        adaptedAt: Value(st.toTs(DateTime.now())),
        general: row?.general ?? false,
      ),
    );
    await db.setPlanIntent(day, sc.Intent.planned.name, source: 'user');
  }

  /// Readiness for [day]: the day state from recovery and load, then the
  /// band's extra signals (resting HR against your baseline, a short night).
  Future<(sc.DayState, sc.RhrFlag, bool)> readinessFor(
    DateTime day,
    st.DailyScore? score,
    sc.CardioLoad load,
  ) async {
    final history = await db.scoresBefore(day, limit: 60);
    final pauses = await loadPauses(db);
    final flag = sc.rhrFlag([
      score?.rhr,
      for (final d in history)
        if (!isPaused(pauses, DateTime.parse(d.date))) d.rhr,
    ]);
    final short = sc.shortSleep(score?.sleptHours, score?.needHours);
    final base = sc.dayState(
      recovery: score?.recovery,
      calibrating: score?.calibrating ?? true,
      load: load.status,
      daysSinceHard: await daysSinceHard(day),
    );
    return (
      sc.readiness(
        base,
        rhr: flag,
        shortNight: short,
        overreaching: load.status == sc.LoadStatus.overreaching,
      ),
      flag,
      short,
    );
  }

  /// Yesterday's key session, if it was missed: carried (never stacked);
  /// missed easy sessions are dropped.
  Future<sc.Session?> missedKeyYesterday(DateTime today) async {
    final y = today.subtract(const Duration(days: 1));
    final row = await db.planDay(y);
    if (row == null || row.status == sc.Intent.skipped.name) return null;
    final s = sc.Session.fromJson(
      jsonDecode(row.session) as Map<String, dynamic>,
    );
    if (!sc.isKeySession(s)) return null;
    final ws = await db.workoutsBetween(y, today);
    final m = sc.matchSession(s, [for (final w in ws) doneWorkout(w)]);
    if (m.kind != sc.MatchKind.none || row.status == sc.Intent.done.name) {
      return null;
    }
    return s;
  }

  /// Accounts for workouts you did instead of the plan (after every sync).
  /// A different kind of workout that made today hard moves the planned
  /// session to a later easy day and puts what you did in its place; a
  /// hard day also eases tomorrow's hard session straight away. Safe to
  /// run repeatedly: once moved, today's plan is what you did.
  Future<sc.Swap> reconcileToday({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final today = dayOf(now);
    if (isPaused(await loadPauses(db), today)) {
      return const sc.Swap(sc.SwapKind.none);
    }
    final rows = await ensureWeek(today);
    final idx = today.weekday - 1;
    if (idx >= rows.length) return const sc.Swap(sc.SwapKind.none);
    final week = [
      for (final r in rows)
        sc.Session.fromJson(jsonDecode(r.session) as Map<String, dynamic>),
    ];
    final plan = week[idx];
    final ws = [
      for (final w in await db.workoutsBetween(
        today,
        today.add(const Duration(days: 1)),
      ))
        doneWorkout(w),
    ];
    final strain = (await db.scoreFor(today))?.strain ?? 0;
    final swap = sc.substitute(
      plan: plan,
      match: sc.matchSession(plan, ws),
      workouts: ws,
      dayStrain: strain,
    );
    final stamp = st.toTs(now);
    String day(int i) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][i];

    if (swap.kind == sc.SwapKind.moved && plan.key != 'done') {
      final by = swap.by!;
      final did = sc.sessionFromDone(by);
      final profile = await loadAppProfile(db) ?? const Profile();
      final j = sc.moveTarget(week, idx, plan, available: profile.days);
      final whereTo = j == null
          ? 'Not enough room left this week, so it’s skipped.'
          : '${plan.title} moves to ${day(j)}.';
      await db.putPlanDay(
        st.PlanDaysCompanion.insert(
          date: rows[idx].date,
          session: jsonEncode(did.toJson()),
          original: Value(rows[idx].original ?? rows[idx].session),
          reason: Value('· ${did.title} made today a hard day. $whereTo'),
          adaptedAt: Value(stamp),
          general: rows[idx].general,
          algoVersion: const Value(sc.coachDayAlgo),
        ),
      );
      await db.setPlanIntent(today, sc.Intent.done.name, source: 'coach');
      if (j != null) {
        await db.putPlanDay(
          st.PlanDaysCompanion.insert(
            date: rows[j].date,
            session: jsonEncode(plan.toJson()),
            original: Value(rows[j].original ?? rows[j].session),
            reason: Value(
              '· Moved from ${day(idx)}: you did ${did.title} instead.',
            ),
            adaptedAt: Value(stamp),
            general: rows[j].general,
            algoVersion: const Value(sc.coachDayAlgo),
          ),
        );
      }
    }

    // A hard day (planned or not) eases tomorrow's hard session now.
    if (swap.hardDay && idx < 6 && week[idx + 1].isHard) {
      final next = rows[idx + 1];
      final from = week[idx + 1];
      final to = sc.sessionTemplate(sc.easierKeyFor(from));
      await db.putPlanDay(
        st.PlanDaysCompanion.insert(
          date: next.date,
          session: jsonEncode(to.toJson()),
          original: Value(next.original ?? next.session),
          reason: Value(
            '■ Today was already hard — no two hard days in a row. ${from.title} carried forward.',
          ),
          adaptedAt: Value(stamp),
          general: next.general,
          algoVersion: const Value(sc.coachDayAlgo),
        ),
      );
      final carried = await db.setting(Keys.carried);
      if (carried == null || carried.isEmpty) {
        await db.putSetting(Keys.carried, jsonEncode(from.toJson()));
      }
    }
    return swap;
  }

  /// Morning adaptation (Flow · morning plan adaptation). Runs once per day,
  /// only when today's score has last night in it (fresh and complete).
  /// Looks three days ahead; holds off entirely while paused.
  Future<List<sc.PlanChange>> adaptToday() async {
    final today = dayOf(DateTime.now());
    final key = st.dateKey(today);
    if (await db.setting(Keys.planAdapted) == key) return const [];
    if (isPaused(await loadPauses(db), today)) return const [];
    final score = await db.scoreFor(today);
    if (score == null || score.sleepEnd == null) return const [];
    final rows = await ensureWeek(today);
    final week = [
      for (final r in rows)
        sc.Session.fromJson(jsonDecode(r.session) as Map<String, dynamic>),
    ];
    final load = await loadFor(db, today);
    final (state, flag, short) = await readinessFor(today, score, load);
    final carriedRaw = await db.setting(Keys.carried);
    final carried = carriedRaw == null || carriedRaw.isEmpty
        ? await missedKeyYesterday(today)
        : sc.Session.fromJson(jsonDecode(carriedRaw) as Map<String, dynamic>);
    final profile = await loadAppProfile(db) ?? const Profile();
    final a = sc.adaptWeek(
      week,
      today.weekday - 1,
      state,
      reason: _reason(score, load, flag, short),
      carried: carried,
      available: profile.days,
      effort: await effort(today),
    );
    final now = st.toTs(DateTime.now());
    for (final ch in a.changes) {
      final d = mondayOf(today).add(Duration(days: ch.dayIndex));
      final prev = rows[ch.dayIndex];
      await db.putPlanDay(
        st.PlanDaysCompanion.insert(
          date: st.dateKey(d),
          session: jsonEncode(ch.to.toJson()),
          original: Value(prev.original ?? prev.session),
          reason: Value('${_glyph(ch.state)} ${ch.reason}'),
          adaptedAt: Value(now),
          general: prev.general,
          algoVersion: const Value(sc.coachDayAlgo),
        ),
      );
    }
    await db.putSetting(
      Keys.carried,
      a.carried == null ? '' : jsonEncode(a.carried!.toJson()),
    );
    await db.putSetting(Keys.planAdapted, key);
    return a.changes;
  }

  static String _glyph(sc.DayState s) => switch (s) {
    sc.DayState.go => '▲',
    sc.DayState.easeOff => '■',
    sc.DayState.rest => '▼',
    sc.DayState.general => '·',
  };

  static String _reason(
    st.DailyScore s,
    sc.CardioLoad load, [
    sc.RhrFlag flag = sc.RhrFlag.none,
    bool short = false,
  ]) {
    if (s.calibrating || s.recovery == null) return 'Calibrating';
    final r = 'Recovery ${s.recovery!.round()}%';
    if (flag == sc.RhrFlag.illness) {
      return '$r and night heart rate well above usual';
    }
    if (flag == sc.RhrFlag.elevated) return '$r but resting HR above usual';
    if (short && s.sleptHours != null) {
      final m = (s.sleptHours! * 60).round();
      return '$r after a short night (${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m)';
    }
    if (load.status == sc.LoadStatus.overreaching) {
      return '$r and load overreaching';
    }
    if (s.sleptHours != null && s.recovery! < 50) {
      final m = (s.sleptHours! * 60).round();
      return '$r after ${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m sleep';
    }
    if (load.status == sc.LoadStatus.building && s.recovery! >= 67) {
      return '$r and load building';
    }
    return r;
  }
}
