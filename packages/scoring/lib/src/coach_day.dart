/// Tempo Coach, within the day: did today's session happen, what to offer
/// when the planned slot passed, and readiness overrides the band can see.
///
/// Everything here is stateless: the app stores only what the user (or
/// coach) decided — skipped, moved, done — and derives the rest on every
/// evaluation, because auto-detected workouts are rebuilt on each rescore.
/// Thresholds are named so a change bumps [coachDayAlgo].
library;

import 'dart:math';

import 'coach.dart';
import 'longevity.dart';

/// Version stamped on plan rows and decisions made by these rules.
const coachDayAlgo = 'coach-day-2';

/// A finished workout, as the matcher sees it.
final class DoneWorkout {
  const DoneWorkout({
    required this.start,
    required this.minutes,
    required this.sport,
    required this.zoneMinutes,
    this.strain = 0,
  });
  final DateTime start;
  final int minutes;

  /// null = unknown sport (counts as general cardio).
  final Sport? sport;

  /// Minutes per zone, Z1..Z5.
  final List<int> zoneMinutes;

  /// Day strain this workout added.
  final double strain;

  int get hardMinutes =>
      zoneMinutes.length == 5 ? zoneMinutes[3] + zoneMinutes[4] : 0;
}

enum MatchKind { done, partial, doneEasier, none }

final class SessionMatch {
  const SessionMatch(this.kind, this.minutes);
  final MatchKind kind;

  /// Compatible minutes found.
  final int minutes;
}

/// Thresholds for [matchSession] (TrainingPeaks-style compliance bands).
const matchDone = .8, matchPartial = .5, hardMinutesNeeded = 5;

const _cardio = {
  Sport.running,
  Sport.cycling,
  Sport.hiit,
  Sport.sport,
  Sport.walking,
};

/// Whether [w] counts toward [planned].
bool compatible(Session planned, Sport? w) {
  final p = planned.sport;
  if (p == null) return false;
  switch (p) {
    case Sport.strength:
      return w == Sport.strength;
    case Sport.yoga:
      return w == Sport.yoga || w == Sport.walking;
    case Sport.walking:
      return w != Sport.strength;
    case Sport.running || Sport.cycling || Sport.hiit || Sport.sport:
      if (w == null) return planned.intensity != Intensity.hard;
      if (w == Sport.walking) return planned.intensity == Intensity.easy;
      return _cardio.contains(w);
  }
}

/// How today's workouts cover [planned]. Done at ≥ 80 % of the planned
/// minutes (or its strain floor reached); partial at ≥ 50 %. A hard
/// session also needs ≥ 5 min in Z4–Z5, else it was done easier.
SessionMatch matchSession(Session planned, List<DoneWorkout> workouts) {
  if (planned.isRest) return const SessionMatch(MatchKind.none, 0);
  final ws = [
    for (final w in workouts)
      if (compatible(planned, w.sport)) w,
  ];
  final minutes = ws.fold<int>(0, (a, w) => a + w.minutes);
  final strain = ws.fold<double>(0, (a, w) => a + w.strain);
  final need = max(1, planned.minutes);
  final ratio = minutes / need;
  final enough =
      ratio >= matchDone ||
      (planned.strainLo > 0 && strain >= planned.strainLo);
  if (enough) {
    if (planned.isHard &&
        ws.fold<int>(0, (a, w) => a + w.hardMinutes) < hardMinutesNeeded) {
      return SessionMatch(MatchKind.doneEasier, minutes);
    }
    return SessionMatch(MatchKind.done, minutes);
  }
  if (ratio >= matchPartial) return SessionMatch(MatchKind.partial, minutes);
  return SessionMatch(MatchKind.none, minutes);
}

/// What the user or coach decided for a day (stored on the plan row).
enum Intent { planned, skipped, moved, done }

enum DayStatus {
  rest,
  done,
  doneEasier,
  partial,
  pending,
  moved,
  missedSlot,
  missedDay,
  skipped,
}

/// Minutes after a slot's planned end before it counts as missed.
const missedGrace = 120;

/// Bedtime on the same scale as minutes after midnight today: a bedtime
/// before noon is after midnight.
int bedScale(int bedtime) => bedtime < 12 * 60 ? bedtime + 1440 : bedtime;

/// Today's status from the plan, the user's intent and what happened.
/// [now] and [plannedMinute] are minutes since today's midnight.
DayStatus deriveStatus({
  required Session plan,
  required Intent intent,
  required SessionMatch match,
  required int now,
  required int bedtime,
  int? plannedMinute,
}) {
  if (plan.isRest) return DayStatus.rest;
  switch (match.kind) {
    case MatchKind.done:
      return DayStatus.done;
    case MatchKind.doneEasier:
      return DayStatus.doneEasier;
    case _:
  }
  if (intent == Intent.done) return DayStatus.done;
  if (intent == Intent.skipped) return DayStatus.skipped;
  if (match.kind == MatchKind.partial) return DayStatus.partial;
  if (now >= bedScale(bedtime) - 60) return DayStatus.missedDay;
  if (plannedMinute != null &&
      now > plannedMinute + plan.minutes + missedGrace) {
    return intent == Intent.moved ? DayStatus.missedDay : DayStatus.missedSlot;
  }
  return intent == Intent.moved ? DayStatus.moved : DayStatus.pending;
}

// ---- readiness overrides ----------------------------------------------------

enum RhrFlag { none, elevated, illness }

/// Resting-HR thresholds. Practitioner rules, not trials (no HRV on the
/// Band 6): +5 bpm or 7-day mean > baseline + 0.5 SD → elevated;
/// ≥ 110 % of baseline or 3 nights in a row at +5 → illness.
const rhrElevatedBpm = 5.0, rhrIllnessRatio = 1.10, rhrBaselineMin = 21;

/// [nightly] is resting HR per night, newest (today) first. The baseline
/// is days 8–60, so a bad week doesn't move its own yardstick.
RhrFlag rhrFlag(List<double?> nightly) {
  if (nightly.isEmpty || nightly.first == null) return RhrFlag.none;
  final base = [
    for (final v in nightly.skip(7).take(53))
      if (v != null) v,
  ];
  if (base.length < rhrBaselineMin) return RhrFlag.none;
  final m = base.reduce((a, b) => a + b) / base.length;
  final sd = sqrt(
    base.fold<double>(0, (a, v) => a + (v - m) * (v - m)) / base.length,
  );
  final today = nightly.first!;
  final run = nightly.take(3).toList();
  if (today >= rhrIllnessRatio * m ||
      (run.length == 3 &&
          run.every((v) => v != null && v >= m + rhrElevatedBpm))) {
    return RhrFlag.illness;
  }
  final week = [
    for (final v in nightly.take(7))
      if (v != null) v,
  ];
  final wMean = week.reduce((a, b) => a + b) / week.length;
  if (today >= m + rhrElevatedBpm ||
      (week.length >= 4 && wMean > m + .5 * sd)) {
    return RhrFlag.elevated;
  }
  return RhrFlag.none;
}

/// Short night: under 6 h, or under 75 % of the need.
bool shortSleep(double? slept, double? need) =>
    slept != null && (slept < 6 || (need != null && slept < .75 * need));

/// [dayState] with the band's extra signals: illness → rest; elevated RHR
/// or a short night caps a Go day at Ease off. With an [overreaching]
/// load, either of those is the second sign that makes it a rest day.
DayState readiness(
  DayState base, {
  RhrFlag rhr = RhrFlag.none,
  bool shortNight = false,
  bool overreaching = false,
}) {
  if (base == DayState.general) return base;
  if (rhr == RhrFlag.illness) return DayState.rest;
  if (overreaching && (rhr == RhrFlag.elevated || shortNight)) {
    return DayState.rest;
  }
  if (base == DayState.go && (rhr == RhrFlag.elevated || shortNight)) {
    return DayState.easeOff;
  }
  return base;
}

/// Foster's monotony: mean / SD of the last 7 days' load. A flat week
/// returns a large number (10), an empty one 0.
double monotony(List<double> daily7) {
  if (daily7.isEmpty) return 0;
  final m = daily7.reduce((a, b) => a + b) / daily7.length;
  if (m == 0) return 0;
  final sd = sqrt(
    daily7.fold<double>(0, (a, v) => a + (v - m) * (v - m)) / daily7.length,
  );
  return sd < 1e-9 ? 10 : m / sd;
}

/// Monotony over 2 with the week above the 4-week weekly average.
bool monotonyHigh(List<double> daily7, double weeklyMean28) =>
    monotony(daily7) > 2 &&
    daily7.fold<double>(0, (a, v) => a + v) > weeklyMean28;

// ---- same-day rescue --------------------------------------------------------

enum RescueTier { full, easier, walk, none, alreadyCovered }

final class Rescue {
  const Rescue(this.tier, {this.session, this.start});
  final RescueTier tier;
  final Session? session;

  /// Minute of day to start.
  final int? start;

  bool get offered => session != null;
}

/// Hard work ends ≥ 4 h before bed (Leota 2025); anything else ≥ 1 h
/// (Stutz 2019); a walk or mobility ≥ 30 min.
const hardBedGap = 240, easyBedGap = 60, walkBedGap = 30, rescueMin = 20;

/// When the planned slot passed with nothing done: what still fits today.
/// [hardFor4h] treats a moderate session as hard when it's big for you.
Rescue replanToday({
  required Session plan,
  required DayStatus status,
  required int now,
  required int bedtime,
  required int pmSlot,
  required DayState state,
  double strainSoFar = 0,
  double targetLo = 0,
  bool hardFor4h = false,
}) {
  if (status != DayStatus.missedSlot || plan.isRest) {
    return const Rescue(RescueTier.none);
  }
  if (state == DayState.rest) return const Rescue(RescueTier.none);
  if (targetLo > 0 && strainSoFar >= targetLo) {
    return const Rescue(RescueTier.alreadyCovered);
  }
  final bed = bedScale(bedtime);
  // Next quarter hour, at least 15 minutes out, not before the evening slot.
  final soon = ((now + 15 + 14) ~/ 15) * 15;
  final start = max(pmSlot, soon);
  final hard = plan.isHard || hardFor4h;
  final full = hard && state != DayState.go
      ? sessionTemplate(easierKeyFor(plan))
      : plan;
  final limit = bed - (full.isHard || hardFor4h ? hardBedGap : easyBedGap);
  if (start + full.minutes <= limit) {
    return Rescue(RescueTier.full, session: full, start: start);
  }
  final easyRoom = bed - easyBedGap - start;
  if (easyRoom >= rescueMin) {
    final base = hard ? sessionTemplate(easierKeyFor(plan)) : plan;
    final fit = fitMinutes(base, min(45, easyRoom));
    if (fit.minutes <= easyRoom) {
      return Rescue(RescueTier.easier, session: fit, start: start);
    }
  }
  if (bed - walkBedGap - start >= rescueMin) {
    final walk = plan.sport == Sport.strength || plan.sport == Sport.yoga
        ? sessionTemplate('mobility')
        : fitMinutes(sessionTemplate('easy_walk'), 20);
    return Rescue(RescueTier.walk, session: walk, start: start);
  }
  return const Rescue(RescueTier.none);
}

// ---- missed days and the week -----------------------------------------------

/// Key sessions carry when missed; easy ones are dropped (never stacked).
bool isKeySession(Session s) =>
    s.key != 'race' && (s.isHard || s.key.startsWith('long_'));

/// Three or more missed days in the trailing week: offer to realign.
bool needsRealign(List<DayStatus> last7) =>
    last7.where((s) => s == DayStatus.missedDay).length >= 3;

final class FloorGap {
  const FloorGap({required this.minutesShort, required this.strengthShort});
  final int minutesShort;
  final int strengthShort;
}

/// WHO 2020 minimums: 150 moderate minutes and 2 strength days a week.
const whoMinutes = 150, whoStrength = 2;

/// What the week still lacks for the WHO floor, counting what's planned
/// for the days left. null when on track.
FloorGap? weeklyFloor({
  required int moderateMinutes,
  required int strengthDays,
  required int plannedMinutesLeft,
  required int plannedStrengthLeft,
}) {
  final m = whoMinutes - moderateMinutes - plannedMinutesLeft;
  final s = whoStrength - strengthDays - plannedStrengthLeft;
  if (m <= 0 && s <= 0) return null;
  return FloorGap(minutesShort: max(0, m), strengthShort: max(0, s));
}

// ---- longevity actions ------------------------------------------------------

/// One thing to do today for the focus lever (or sleep).
final class LeverAction {
  const LeverAction(this.lever, this.title, this.detail, {this.done = false});
  final Lever lever;
  final String title, detail;
  final bool done;
}

/// Turns the focus lever into at most two actions for today, plus tonight's
/// bedtime. [nowMinute], [wakeMinute], [bedtime] are minutes of day.
List<LeverAction> leverActions({
  Lever? focus,
  required int nowMinute,
  required int wakeMinute,
  required int bedtime,
  int stepsToday = 0,
  double stepTarget = 10000,
  double activeWeek = 0,
  double activeTarget = 150,
  int daysLeft = 1,
  int strengthWeek = 0,
  double strengthTarget = 2,
  bool hardToday = false,
  bool strengthToday = false,
}) {
  String hm(int m) {
    final x = m % 1440;
    return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
  }

  final out = <LeverAction>[];
  switch (focus) {
    case Lever.steps:
      final bed = bedScale(bedtime);
      final span = max(1, bed - wakeMinute);
      final frac = ((nowMinute - wakeMinute) / span).clamp(0.0, 1.0);
      final behind = stepsToday < .6 * stepTarget * frac && frac > .3;
      out.add(
        LeverAction(
          Lever.steps,
          '${_k(stepTarget)} steps',
          stepsToday >= stepTarget
              ? '${_k(stepsToday.toDouble())} today — done'
              : behind
              ? '${_k(stepsToday.toDouble())} so far · a 10′ walk after a meal helps'
              : '${_k(stepsToday.toDouble())} so far',
          done: stepsToday >= stepTarget,
        ),
      );
    case Lever.activeMinutes:
      final left = max(0.0, activeTarget - activeWeek);
      final perDay = (left / max(1, daysLeft)).ceil();
      out.add(
        LeverAction(
          Lever.activeMinutes,
          left <= 0 ? 'Zone 2+ week done' : '$perDay′ in Zone 2+ today',
          '${activeWeek.round()} of ${activeTarget.round()} min this week',
          done: left <= 0,
        ),
      );
    case Lever.strength:
      final n = strengthWeek + 1;
      out.add(
        LeverAction(
          Lever.strength,
          strengthWeek >= strengthTarget
              ? 'Strength week done'
              : hardToday
              ? 'Strength another day'
              : 'Strength session $n of ${strengthTarget.round()}',
          strengthWeek >= strengthTarget
              ? '${strengthWeek} sessions this week'
              : hardToday
              ? 'Not on a hard cardio day'
              : strengthToday
              ? 'It’s today’s plan'
              : '20–30′ full body counts',
          done: strengthWeek >= strengthTarget,
        ),
      );
    case Lever.sleepRegularity:
      out.add(
        LeverAction(
          Lever.sleepRegularity,
          'Lights out ${hm(bedtime - 15)}–${hm(bedtime + 15)}',
          'Same 30-minute window every night, weekends too',
        ),
      );
    case _:
  }
  out.add(
    LeverAction(
      Lever.sleepDuration,
      'In bed by ${hm(bedtime)}',
      'Covers tonight’s sleep need',
    ),
  );
  return out;
}

String _k(double v) => v >= 1000
    ? '${(v / 1000).toStringAsFixed(1).replaceAll('.0', '')}k'
    : '${v.round()}';

// ---- unplanned workouts -----------------------------------------------------

/// How an unplanned workout relates to today's planned session.
enum SwapKind {
  /// Nothing unplanned to account for.
  none,

  /// It covered the session (same family, enough of it).
  counted,

  /// Different kind, but it made today a hard day: the planned session
  /// moves to a later easy day.
  moved,

  /// Different kind and light: credited, the session still stands.
  stands,
}

final class Swap {
  const Swap(this.kind, {this.by, this.hardDay = false});
  final SwapKind kind;

  /// The workout that counted, moved or was credited.
  final DoneWorkout? by;

  /// Today ended up hard (from any workout), whatever was planned.
  final bool hardDay;
}

/// Unplanned work shorter than this is ignored.
const swapMinMinutes = 10;

/// Today was hard: any workout with ≥ 5 min in Z4–Z5, or the day's strain
/// past what [plan] would have added at most.
bool madeHard(List<DoneWorkout> ws, double dayStrain, Session plan) =>
    ws.any((w) => w.hardMinutes >= hardMinutesNeeded) ||
    (!plan.isRest && plan.strainHi > 0 && dayStrain >= plan.strainHi);

/// What today's workouts mean for today's [plan], given how it matched.
Swap substitute({
  required Session plan,
  required SessionMatch match,
  required List<DoneWorkout> workouts,
  double dayStrain = 0,
}) {
  final ws = [
    for (final w in workouts)
      if (w.minutes >= swapMinMinutes) w,
  ]..sort((a, b) => b.minutes.compareTo(a.minutes));
  final hard = madeHard(ws, dayStrain, plan);
  if (ws.isEmpty || plan.isRest) return Swap(SwapKind.none, hardDay: hard);
  if (match.kind == MatchKind.done || match.kind == MatchKind.doneEasier) {
    final by = ws.where((w) => compatible(plan, w.sport)).firstOrNull;
    return Swap(SwapKind.counted, by: by ?? ws.first, hardDay: hard);
  }
  final other = ws.where((w) => !compatible(plan, w.sport)).firstOrNull;
  if (other == null) return Swap(SwapKind.none, hardDay: hard);
  return Swap(
    hard ? SwapKind.moved : SwapKind.stands,
    by: other,
    hardDay: hard,
  );
}

/// The next day this week that can take [s]: available, planned easy (not
/// strength, not rest), and with no hard or strength day either side.
/// [week] is Monday first; [available] uses 1 = Monday.
int? moveTarget(
  List<Session> week,
  int today,
  Session s, {
  Set<int> available = const {1, 2, 3, 4, 5, 6, 7},
}) {
  bool heavy(int i) =>
      i >= 0 &&
      i < week.length &&
      (week[i].isHard || week[i].sport == Sport.strength);
  for (var j = today + 1; j < week.length; j++) {
    final d = week[j];
    if (!available.contains(j + 1)) continue;
    if (d.isRest || d.isHard || d.sport == Sport.strength) continue;
    if (d.intensity != Intensity.easy) continue;
    if (j == today + 1) continue; // today was hard: not tomorrow
    if (heavy(j - 1) || heavy(j + 1)) continue;
    return j;
  }
  return null;
}

String sportName(Sport? s) => switch (s) {
  Sport.running => 'Run',
  Sport.cycling => 'Ride',
  Sport.walking => 'Walk',
  Sport.strength => 'Strength',
  Sport.yoga => 'Yoga',
  Sport.hiit => 'HIIT',
  Sport.sport => 'Sport',
  null => 'Workout',
};

/// What you did, as a plan session, so today's plan shows it.
Session sessionFromDone(DoneWorkout w) {
  var zone = 1, best = -1;
  for (var z = 0; z < w.zoneMinutes.length; z++) {
    if (w.zoneMinutes[z] > best) {
      best = w.zoneMinutes[z];
      zone = z + 1;
    }
  }
  final intensity = w.hardMinutes >= hardMinutesNeeded
      ? Intensity.hard
      : zone >= 3
      ? Intensity.moderate
      : Intensity.easy;
  return Session(
    key: 'done',
    title: '${sportName(w.sport)} ${w.minutes}′',
    sport: w.sport,
    segments: [Segment(max(1, w.minutes), zone.clamp(1, 5))],
    strainLo: 0,
    strainHi: w.strain,
    intensity: intensity,
    note: 'what you did',
  );
}
