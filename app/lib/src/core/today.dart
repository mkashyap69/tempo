import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'profile.dart';

/// Everything the Today and Coach screens, the widgets and the bedtime
/// nudge derive from the DB for one day.
class TodayData {
  TodayData({
    required this.day,
    required this.score,
    required this.history,
    required this.nights,
    required this.everSlept,
    required this.load,
    required this.target,
    required this.state,
    required this.plan,
    required this.planRow,
    required this.week,
    required this.needTonight,
    required this.debt,
    required this.baseNeed,
    required this.wakeMinute,
    required this.wakeFromUsual,
    required this.bedtimeMinute,
    required this.lastSync,
    required this.profile,
    required this.workouts,
    required this.rhrBase,
    required this.stressBase,
    required this.sleepBase,
    this.daysSinceHard,
  });

  final DateTime day;
  final st.DailyScore? score;

  /// Earlier days, newest first (up to 60).
  final List<st.DailyScore> history;

  /// Nights captured toward the 14-night baseline (0–14).
  final int nights;
  final bool everSlept;
  final sc.CardioLoad load;
  final sc.StrainTarget target;
  final sc.DayState state;
  final sc.Session? plan;
  final st.PlanDay? planRow;
  final List<st.PlanDay> week;
  final double needTonight, debt, baseNeed;
  final int wakeMinute, bedtimeMinute;
  final bool wakeFromUsual;
  final DateTime? lastSync;
  final Profile profile;
  final List<st.Workout> workouts;
  final sc.Baseline? rhrBase, stressBase, sleepBase;
  final int? daysSinceHard;

  bool get calibrating => score?.calibrating ?? (nights < 14);
  bool get firstDay => !everSlept;
  double? get recovery => calibrating ? null : score?.recovery;
  double get strain => score?.strain ?? 0;
  double? get sleepPerf => score?.sleepPerf;
  double? get slept => score?.sleptHours;
  double? get need => score?.needHours;
  bool get hasNight => score?.sleepEnd != null;
  bool get restDay => target.cap;
  int get hrMax => score?.hrMax ?? profile.effectiveMaxHr;

  Duration? get syncAge =>
      lastSync == null ? null : DateTime.now().difference(lastSync!);
  bool get stale => syncAge != null && syncAge! > const Duration(hours: 12);

  double? get rhrDelta => score?.rhr == null || rhrBase == null
      ? null
      : score!.rhr! - rhrBase!.mean;
  double? get stressDelta => score?.hrvProxy == null || stressBase == null
      ? null
      : score!.hrvProxy! - stressBase!.mean;

  /// Last 7 days of scores including today, oldest first.
  List<st.DailyScore> get last7 => [
    ...history.take(6).toList().reversed,
    ?score,
  ];
}

int _clock(DateTime t) => t.hour * 60 + t.minute;

int? parseHm(String? v) {
  if (v == null || !v.contains(':')) return null;
  final p = v.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String fmtHm(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

Future<TodayData> loadToday(st.TempoDb db, {DateTime? at}) async {
  final day = dayOf(at ?? DateTime.now());
  final score = await db.scoreFor(day);
  final history = await db.scoresBefore(day, limit: 90);
  final recent30 = [?score, ...history.take(29)];
  final nights = recent30
      .where((d) => d.sleptHours != null)
      .length
      .clamp(0, 14);
  final everSlept =
      recent30.any((d) => d.sleptHours != null) ||
      history.any((d) => d.sleptHours != null);
  final load = await loadFor(db, day);
  final profile = await loadAppProfile(db) ?? const Profile();
  final calibrating = score?.calibrating ?? nights < 14;
  final target = everSlept
      ? sc.strainTarget(
          recovery: calibrating ? null : score?.recovery,
          calibrating: calibrating,
          load: load.status,
        )
      : const sc.StrainTarget(8, 12, general: true);
  final coach = CoachService(db);
  final week = await coach.ensureWeek(day);
  final row = week.where((r) => r.date == st.dateKey(day)).firstOrNull;
  final plan = row == null
      ? null
      : sc.Session.fromJson(jsonDecode(row.session) as Map<String, dynamic>);
  final sinceHard = await coach.daysSinceHard(day);
  final state = sc.dayState(
    recovery: score?.recovery,
    calibrating: calibrating,
    load: load.status,
    daysSinceHard: sinceHard,
  );

  // Sleep need tonight: baseline + today's strain + a share of the debt.
  final nightsForDebt = [
    for (final d in [?score, ...history.take(6)])
      if (d.needHours != null && d.sleptHours != null)
        sc.NightRecord(needHours: d.needHours!, sleptHours: d.sleptHours!),
  ];
  const sleepParams = sc.SleepParams();
  final debt = sc.sleepDebtHours(nightsForDebt);
  final needTonight = sc.sleepNeedHours(
    debtHours: debt,
    strainYesterday: score?.strain ?? 0,
  );
  final set = parseHm(await db.setting(Keys.wakeTime));
  final ends = [
    for (final d in recent30.take(14))
      if (d.sleepEnd != null) _clock(st.fromTs(d.sleepEnd!)),
  ];
  final wake = set ?? (ends.isEmpty ? 7 * 60 : sc.medianClock(ends));
  final lastSyncRaw = await db.setting(Keys.lastSync);
  final rhrBase = sc.Baseline.of(history.take(30).map((d) => d.rhr));
  final stressBase = sc.Baseline.of(history.take(30).map((d) => d.hrvProxy));
  final sleepBase = sc.Baseline.of(history.take(30).map((d) => d.sleepPerf));
  return TodayData(
    day: day,
    score: score,
    history: history,
    nights: nights,
    everSlept: everSlept,
    load: load,
    target: target,
    state: state,
    plan: plan,
    planRow: row,
    week: week,
    needTonight: needTonight,
    debt: debt,
    baseNeed: sleepParams.baseNeedHours,
    wakeMinute: wake,
    wakeFromUsual: set == null,
    bedtimeMinute: sc.bedtimeMinute(needTonight, wake),
    lastSync: lastSyncRaw == null ? null : DateTime.tryParse(lastSyncRaw),
    profile: profile,
    workouts: await db.workoutsBetween(day, day.add(const Duration(days: 1))),
    rhrBase: rhrBase,
    stressBase: stressBase,
    sleepBase: sleepBase,
    daysSinceHard: sinceHard,
  );
}
