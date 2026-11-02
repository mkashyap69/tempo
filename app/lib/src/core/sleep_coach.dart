import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'everyday.dart' show loadRhythm;
import 'profile.dart';
import 'score_service.dart' show parseDateKey;

/// Main sleeps (start, end) from scores between [from] and [to] (mornings).
Future<List<st.DailyScore>> _nights(
  st.TempoDb db,
  DateTime from,
  DateTime to,
) async => [
  for (final s in await db.scoresBetween(from, to))
    if (s.sleepStart != null && s.sleepEnd != null) s,
];

sc.NightSpan _span(st.DailyScore s) =>
    (start: st.fromTs(s.sleepStart!), end: st.fromTs(s.sleepEnd!));

int _clock(DateTime t) => t.hour * 60 + t.minute;

/// Your sleep type from the last 14 nights, or null under a week of them.
Future<sc.SleepType?> loadSleepType(st.TempoDb db, {DateTime? now}) async {
  final today = dayOf(now ?? DateTime.now());
  final nights = await _nights(
    db,
    today.subtract(const Duration(days: 13)),
    today,
  );
  final rhythm = await loadRhythm(db, now: now);
  return sc.sleepType([for (final n in nights) _span(n)], sri: rhythm.sri);
}

/// The area a plan would start on, from the last 14 nights.
Future<sc.SleepFocus> suggestedFocus(st.TempoDb db, {DateTime? now}) async {
  final today = dayOf(now ?? DateTime.now());
  final nights = await _nights(
    db,
    today.subtract(const Duration(days: 13)),
    today,
  );
  final rhythm = await loadRhythm(db, now: now);
  double? mean(Iterable<double?> xs) {
    final v = [for (final x in xs) ?x];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  return sc.weakestSleepArea(
    sri: rhythm.sri,
    bedtimeConsistency: nights.length < 3
        ? null
        : sc.consistency([for (final n in nights) _clock(_span(n).start)]),
    hours: mean([for (final n in nights) n.sleptHours]),
    needHours: mean([for (final n in nights) n.needHours]),
    latencyMin: mean([for (final n in nights) n.latencyMin?.toDouble()]),
  );
}

/// The stored plan.
final class SleepPlan {
  const SleepPlan({
    required this.focus,
    required this.start,
    required this.wake,
    required this.bed,
    this.fromWake,
    this.fromBed,
  });
  final sc.SleepFocus focus;
  final DateTime start;

  /// Wake and lights-out goals, minutes of day.
  final int wake, bed;

  /// Usual wake and bedtime when the plan started; each week's targets
  /// step 15 min from them toward the goals (V1). Null = the goals at once.
  final int? fromWake, fromBed;

  /// Targets on plan day [d] (0-based): week 1 one step from the usual
  /// time, week 2 two, week 3 three, never past the goal.
  int wakeOn(int d) => sc.stepToward(fromWake, wake, d ~/ 7 + 1);
  int bedOn(int d) => sc.stepToward(fromBed, bed, d ~/ 7 + 1);

  /// The weeks with day [d]'s targets in their titles.
  List<sc.SleepWeek> weeksOn(int d) =>
      sc.sleepWeeks(focus, wakeMinute: wakeOn(d), bedMinute: bedOn(d));

  List<sc.SleepWeek> get weeks => weeksOn(0);

  SleepPlan withFrom(int? wake, int? bed) => SleepPlan(
    focus: focus,
    start: start,
    wake: this.wake,
    bed: this.bed,
    fromWake: fromWake ?? wake,
    fromBed: fromBed ?? bed,
  );

  Map<String, Object> toJson() => {
    'focus': focus.name,
    'start': st.dateKey(start),
    'wake': wake,
    'bed': bed,
    'fromWake': ?fromWake,
    'fromBed': ?fromBed,
  };

  static SleepPlan? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SleepPlan(
        focus: sc.SleepFocus.values.byName(j['focus'] as String),
        start: parseDateKey(j['start'] as String),
        wake: j['wake'] as int,
        bed: j['bed'] as int,
        fromWake: j['fromWake'] as int?,
        fromBed: j['fromBed'] as int?,
      );
    } on Object {
      return null;
    }
  }
}

Future<Map<String, Set<String>>> _ticks(st.TempoDb db) async {
  final raw = await db.setting(Keys.sleepPlanTicks);
  if (raw == null || raw.isEmpty) return {};
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in j.entries)
        e.key: {for (final x in e.value as List) x as String},
    };
  } on Object {
    return {};
  }
}

Future<void> startSleepPlan(
  st.TempoDb db,
  sc.SleepFocus focus, {
  required int wake,
  required int bed,
  int? fromWake,
  int? fromBed,
  DateTime? now,
}) async {
  final plan = SleepPlan(
    focus: focus,
    start: dayOf(now ?? DateTime.now()),
    wake: wake,
    bed: bed,
    fromWake: fromWake,
    fromBed: fromBed,
  );
  await db.putSetting(Keys.sleepPlan, jsonEncode(plan.toJson()));
  await db.putSetting(Keys.sleepPlanTicks, '{}');
}

Future<void> endSleepPlan(st.TempoDb db) async {
  await db.deleteSetting(Keys.sleepPlan);
  await db.deleteSetting(Keys.sleepPlanTicks);
}

/// Ticks or unticks a hand-checked habit on [day].
Future<void> tickHabit(
  st.TempoDb db,
  DateTime day,
  String id,
  bool done,
) async {
  final t = await _ticks(db);
  final k = st.dateKey(day);
  final s = t.putIfAbsent(k, () => {});
  done ? s.add(id) : s.remove(id);
  await db.putSetting(
    Keys.sleepPlanTicks,
    jsonEncode({for (final e in t.entries) e.key: e.value.toList()}),
  );
}

/// A habit on a day: done, missed (auto, the night says no) or open.
enum HabitState { done, missed, open }

final class HabitToday {
  const HabitToday(this.habit, this.state, this.note);
  final sc.SleepHabit habit;
  final HabitState state;

  /// "Woke 9:09", "Tonight", or null.
  final String? note;
}

/// One of the 21 days.
enum PlanDayState { kept, missed, today, ahead }

/// The plan as screens show it.
final class SleepPlanView {
  const SleepPlanView({
    required this.plan,
    required this.day,
    required this.today,
    required this.days,
    required this.before,
    required this.since,
    required this.sinceNights,
  });
  final SleepPlan plan;

  /// 0-based plan day; 21 or more once it has ended.
  final int day;
  final List<HabitToday> today;
  final List<PlanDayState> days;

  /// The focus metric over the 14 nights before the start and since it
  /// (null when there aren't enough nights).
  final double? before, since;
  final int sinceNights;

  bool get finished => day >= sc.sleepPlanDays;
  int get kept => days.where((d) => d == PlanDayState.kept).length;
  int get week => (day ~/ 7).clamp(0, 2);
}

String _hm(int m) {
  final x = ((m % 1440) + 1440) % 1440;
  return '${x ~/ 60}:${(x % 60).toString().padLeft(2, '0')}';
}

/// The focus metric over [nights]: bedtime consistency (%), hours asleep or
/// minutes to fall asleep.
double? focusMetric(sc.SleepFocus f, List<st.DailyScore> nights) {
  if (nights.length < 3) return null;
  switch (f) {
    case sc.SleepFocus.regularity:
      return sc.consistency([
            for (final n in nights) _clock(st.fromTs(n.sleepStart!)),
          ]) *
          100;
    case sc.SleepFocus.duration:
      final h = [for (final n in nights) ?n.sleptHours];
      return h.isEmpty ? null : h.reduce((a, b) => a + b) / h.length;
    case sc.SleepFocus.fallingAsleep:
      final l = [for (final n in nights) ?n.latencyMin];
      return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }
}

Future<SleepPlanView?> loadSleepPlan(st.TempoDb db, {DateTime? now}) async {
  final stored = SleepPlan.fromJson(await db.setting(Keys.sleepPlan));
  if (stored == null) return null;
  final before = await _nights(
    db,
    stored.start.subtract(const Duration(days: 14)),
    stored.start,
  );
  // Plans started before V1 kept no usual times: take them from the 14
  // nights before the start.
  final plan = stored.withFrom(
    sc.usualClock([for (final n in before) _clock(st.fromTs(n.sleepEnd!))]),
    sc.usualClock([for (final n in before) _clock(st.fromTs(n.sleepStart!))]),
  );
  final today = dayOf(now ?? DateTime.now());
  final day = today.difference(plan.start).inDays;
  final ticks = await _ticks(db);
  final scores = {
    for (final s in await _nights(
      db,
      plan.start,
      plan.start.add(const Duration(days: sc.sleepPlanDays)),
    ))
      s.date: s,
  };

  List<HabitToday> on(int d) {
    final date = plan.start.add(Duration(days: d));
    final morning = scores[st.dateKey(date)];
    final next = scores[st.dateKey(date.add(const Duration(days: 1)))];
    final hand = ticks[st.dateKey(date)] ?? const <String>{};
    return [
      for (final h in sc.habitsOn(plan.weeksOn(d), d))
        switch (h.id) {
          'wake' when morning != null => HabitToday(
            h,
            sc.keptTime(_clock(st.fromTs(morning.sleepEnd!)), plan.wakeOn(d))
                ? HabitState.done
                : HabitState.missed,
            'Woke ${_hm(_clock(st.fromTs(morning.sleepEnd!)))}',
          ),
          'wake' => HabitToday(h, HabitState.open, 'No sleep recorded yet'),
          'bed' when next != null => HabitToday(
            h,
            sc.keptTime(_clock(st.fromTs(next.sleepStart!)), plan.bedOn(d))
                ? HabitState.done
                : HabitState.missed,
            'Asleep ${_hm(_clock(st.fromTs(next.sleepStart!)))}',
          ),
          'bed' => HabitToday(h, HabitState.open, 'Tonight'),
          _ => HabitToday(
            h,
            hand.contains(h.id) ? HabitState.done : HabitState.open,
            null,
          ),
        },
    ];
  }

  final days = <PlanDayState>[
    for (var d = 0; d < sc.sleepPlanDays; d++)
      if (d > day)
        PlanDayState.ahead
      else if (d == day)
        PlanDayState.today
      else
        sc.dayKept(
              on(d).where((x) => x.state == HabitState.done).length,
              on(d).length,
            )
            ? PlanDayState.kept
            : PlanDayState.missed,
  ];
  final since = [
    for (final s in scores.values)
      if (s.date.compareTo(st.dateKey(plan.start)) > 0) s,
  ];
  return SleepPlanView(
    plan: plan,
    day: day,
    today: day < sc.sleepPlanDays ? on(day) : const [],
    days: days,
    before: focusMetric(plan.focus, before),
    since: focusMetric(plan.focus, since),
    sinceNights: since.length,
  );
}
