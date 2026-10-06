import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'data_source.dart';
import 'pause.dart';
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
    this.hrvBase,
    this.source = sc.bandSource,
    this.daysSinceHard,
    this.pause,
    this.baseNeedLearned = false,
    this.smartAlarm,
    this.intent = sc.Intent.planned,
    this.plannedMinute,
    this.status = sc.DayStatus.pending,
    this.rescue = const sc.Rescue(sc.RescueTier.none),
    this.rhrFlag = sc.RhrFlag.none,
    this.shortNight = false,
    this.pmSlot = 18 * 60,
    this.amSlot = 7 * 60,
    this.swap = const sc.Swap(sc.SwapKind.none),
  });

  /// How today's unplanned workouts relate to the plan.
  final sc.Swap swap;

  /// What the user decided for today's session (Tempo Coach).
  final sc.Intent intent;

  /// Minute of day the session is planned for, or null (any time).
  final int? plannedMinute;

  /// Done / pending / missed…, derived from today's workouts.
  final sc.DayStatus status;

  /// What still fits today when the planned slot passed.
  final sc.Rescue rescue;
  final sc.RhrFlag rhrFlag;
  final bool shortNight;
  final int pmSlot, amSlot;

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

  /// Real HRV (ms) over the last 30 nights of the same kind, from a Health
  /// source; null with the band.
  final sc.Baseline? hrvBase;

  /// The data source today's numbers come from (`daily_scores.source`).
  final String source;

  /// The open ill/travel pause, if any.
  final Pause? pause;

  /// True once [baseNeed] comes from your own nights, not the 7.5 h default.
  final bool baseNeedLearned;

  /// Band smart alarm, minute of day, or null when off.
  final int? smartAlarm;

  /// Naps today (hours).
  double get napHours => score?.napHours ?? 0;
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
  final source = score?.source ?? (await loadDataSource(db)).key;
  final history = await db.scoresBefore(day, limit: 90);
  // Baselines and calibration compare only days of one source (scoring
  // does the same); a switch of source starts them fresh.
  final same = [
    for (final d in history)
      if (d.source == source) d,
  ];
  final recent30 = [?score, ...same.take(29)];
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
  final (state, rhrFlag, shortNight) = await coach.readinessFor(
    day,
    score?.copyWith(calibrating: calibrating),
    load,
  );

  // Sleep need tonight: your base + today's strain + a share of the debt.
  // Naps count against the debt. Paused nights don't teach the base.
  final pauses = await loadPauses(db);
  final nightsForDebt = [
    for (final d in [?score, ...history.take(6)])
      if (d.needHours != null && d.sleptHours != null)
        sc.NightRecord(
          needHours: d.needHours!,
          sleptHours: d.sleptHours! + d.napHours,
        ),
  ];
  const sleepParams = sc.SleepParams();
  final needSamples = [
    for (final d in [?score, ...same.take(59)])
      if (d.sleptHours != null &&
          d.recovery != null &&
          !d.calibrating &&
          !isPaused(pauses, DateTime.parse(d.date)))
        sc.NeedSample(sleptHours: d.sleptHours!, recovery: d.recovery!),
  ];
  final baseNeed = sc.learnedBaseNeed(needSamples);
  final debt = sc.sleepDebtHours(nightsForDebt);
  final needTonight = sc.sleepNeedHours(
    debtHours: debt,
    strainYesterday: score?.strain ?? 0,
    baseHours: baseNeed,
  );
  final set = parseHm(await db.setting(Keys.wakeTime));
  final ends = [
    for (final d in recent30.take(14))
      if (d.sleepEnd != null) _clock(st.fromTs(d.sleepEnd!)),
  ];
  final wake = set ?? (ends.isEmpty ? 7 * 60 : sc.medianClock(ends));
  final lastSyncRaw = await db.setting(Keys.lastSync);
  // Tempo Coach: when today's session is planned, whether it happened,
  // and what still fits if its slot passed.
  final slots = await loadSlots(db);
  final workouts = await db.workoutsBetween(
    day,
    day.add(const Duration(days: 1)),
  );
  final intent =
      sc.Intent.values.asNameMap()[row?.status ?? 'planned'] ??
      sc.Intent.planned;
  final planned = plan == null || plan.isRest
      ? null
      : row?.plannedMinute ?? slots.minuteFor(plan);
  final nowT = at ?? DateTime.now();
  final nowMin = dayOf(nowT) == day
      ? _clock(nowT)
      : (nowT.isAfter(day) ? 24 * 60 + 600 : 0);
  final bedtime = sc.bedtimeMinute(needTonight, wake);
  final match = plan == null
      ? const sc.SessionMatch(sc.MatchKind.none, 0)
      : sc.matchSession(plan, [for (final w in workouts) doneWorkout(w)]);
  final status = plan == null
      ? sc.DayStatus.rest
      : sc.deriveStatus(
          plan: plan,
          intent: intent,
          match: match,
          now: nowMin,
          bedtime: bedtime,
          plannedMinute: planned,
        );
  final done = [for (final w in workouts) doneWorkout(w)];
  final swap = plan == null
      ? const sc.Swap(sc.SwapKind.none)
      : sc.substitute(
          plan: plan,
          match: match,
          workouts: done,
          dayStrain: score?.strain ?? 0,
        );
  final strains = [
    for (final d in history.take(28))
      if (d.strain > 0) d.strain,
  ];
  final p75 = sc.quantile(strains, .75);
  final rescue = plan == null
      ? const sc.Rescue(sc.RescueTier.none)
      : sc.replanToday(
          plan: plan,
          status: status,
          now: nowMin,
          bedtime: bedtime,
          pmSlot: slots.pm,
          state: state,
          strainSoFar: score?.strain ?? 0,
          targetLo: target.general ? 0 : target.lo,
          hardFor4h:
              plan.intensity == sc.Intensity.moderate &&
              p75 != null &&
              plan.strainLo >= p75,
        );
  final rhrBase = sc.Baseline.of(same.take(30).map((d) => d.rhr));
  final stressBase = sc.Baseline.of(same.take(30).map((d) => d.hrvProxy));
  final sleepBase = sc.Baseline.of(same.take(30).map((d) => d.sleepPerf));
  final hrvBase = sc.Baseline.of([
    for (final d in same.take(30))
      if (d.hrv != null &&
          (score?.hrvKind == null || d.hrvKind == score!.hrvKind))
        d.hrv,
  ]);
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
    baseNeed: baseNeed,
    baseNeedLearned: needSamples.length >= sleepParams.learnNights,
    wakeMinute: wake,
    wakeFromUsual: set == null,
    bedtimeMinute: bedtime,
    lastSync: lastSyncRaw == null ? null : DateTime.tryParse(lastSyncRaw),
    profile: profile,
    workouts: workouts,
    rhrBase: rhrBase,
    stressBase: stressBase,
    sleepBase: sleepBase,
    hrvBase: hrvBase,
    source: source,
    daysSinceHard: sinceHard,
    pause: activePause(pauses),
    smartAlarm: parseHm(await db.setting(Keys.smartAlarm)),
    intent: intent,
    plannedMinute: planned,
    status: status,
    rescue: rescue,
    rhrFlag: rhrFlag,
    shortNight: shortNight,
    pmSlot: slots.pm,
    amSlot: slots.am,
    swap: swap,
  );
}

/// The user's training slots (Tempo Coach). [slot] is am, pm or flex; unset,
/// it's inferred from when your recorded workouts usually start.
final class Slots {
  const Slots(this.slot, this.am, this.pm);
  final String slot;
  final int am, pm;

  /// Minute of day a session is planned for, or null when flexible.
  int? minuteFor(sc.Session s) => switch (slot) {
    'am' => am,
    'pm' => pm,
    _ => null,
  };
}

Future<Slots> loadSlots(st.TempoDb db) async {
  final am = parseHm(await db.setting(Keys.coachSlotAm)) ?? 7 * 60;
  final pm = parseHm(await db.setting(Keys.coachSlotPm)) ?? 18 * 60;
  var slot = await db.setting(Keys.coachSlot);
  if (slot == null || slot.isEmpty) {
    final now = DateTime.now();
    final ws = await db.workoutsBetween(
      now.subtract(const Duration(days: 28)),
      now,
    );
    final starts = [
      for (final w in ws)
        if (w.source != 'auto' || w.confirmed) _clock(st.fromTs(w.start)),
    ];
    slot = starts.length >= 3 && sc.medianClock(starts) < 12 * 60 ? 'am' : 'pm';
  }
  return Slots(slot, am, pm);
}
