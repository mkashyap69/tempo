import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'profile.dart';

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime mondayOf(DateTime t) =>
    dayOf(t).subtract(Duration(days: t.weekday - 1));

/// Daily TRIMP, newest first, for the last [days] days ending [day]
/// (missing days count as 0).
Future<List<double>> dailyTrimp(
  st.TempoDb db,
  DateTime day, {
  int days = 28 * 4,
}) async {
  final from = day.subtract(Duration(days: days - 1));
  final rows = await db.scoresBetween(from, day);
  final byDate = {for (final r in rows) r.date: r.trimp};
  if (rows.isEmpty) return [];
  final first = DateTime.parse(rows.first.date);
  return [
    for (
      var d = dayOf(day);
      !d.isBefore(first);
      d = DateTime(d.year, d.month, d.day - 1)
    )
      byDate[st.dateKey(d)] ?? 0,
  ];
}

Future<sc.CardioLoad> loadFor(st.TempoDb db, DateTime day) async =>
    sc.cardioLoad(await dailyTrimp(db, day));

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
    final week = sc.weekPlan(profile.prefs, general: general);
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

  /// Morning adaptation (Flow · morning plan adaptation). Runs once per day,
  /// only when today's score has last night in it (fresh and complete).
  Future<List<sc.PlanChange>> adaptToday() async {
    final today = dayOf(DateTime.now());
    final key = st.dateKey(today);
    if (await db.setting(Keys.planAdapted) == key) return const [];
    final score = await db.scoreFor(today);
    if (score == null || score.sleepEnd == null) return const [];
    final rows = await ensureWeek(today);
    final week = [
      for (final r in rows)
        sc.Session.fromJson(jsonDecode(r.session) as Map<String, dynamic>),
    ];
    final load = await loadFor(db, today);
    final state = sc.dayState(
      recovery: score.recovery,
      calibrating: score.calibrating,
      load: load.status,
      daysSinceHard: await daysSinceHard(today),
    );
    final carriedRaw = await db.setting(Keys.carried);
    final carried = carriedRaw == null || carriedRaw.isEmpty
        ? null
        : sc.Session.fromJson(jsonDecode(carriedRaw) as Map<String, dynamic>);
    final profile = await loadAppProfile(db) ?? const Profile();
    final a = sc.adaptWeek(
      week,
      today.weekday - 1,
      state,
      reason: _reason(score, load),
      carried: carried,
      available: profile.days,
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

  static String _reason(st.DailyScore s, sc.CardioLoad load) {
    if (s.calibrating || s.recovery == null) return 'Calibrating';
    final r = 'Recovery ${s.recovery!.round()}%';
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
