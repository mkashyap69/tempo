/// Training blocks: a goal (an event on a date, or open-ended "get
/// fitter"), the phase each week is in, and how much it has grown.
///
/// Weekly volume steps up about 5 % each week you absorbed (enough of the
/// plan done, recovery and how you felt holding), holds when you didn't,
/// and steps back after a bad week. Every 4th week is lighter. An event
/// ends in a peak and a taper, with the race on the last day.
library;

import 'dart:math';

/// Version stamped on plan rows built from a block.
const blockAlgo = 'block-1';

enum BlockGoal { open, run5k, run10k, half, marathon }

enum Phase { base, build, peak, deload, taper, race }

/// One training block. [start] is the Monday it began; [event] is the
/// race day (null for an open-ended block).
final class TrainingBlock {
  const TrainingBlock({required this.goal, required this.start, this.event});
  final BlockGoal goal;
  final DateTime start;
  final DateTime? event;

  bool get isEvent => goal != BlockGoal.open && event != null;

  /// Weeks from [start] to the race week, inclusive.
  int get weeks => isEvent ? _weeksBetween(start, event!) + 1 : 0;

  Map<String, Object?> toJson() => {
    'goal': goal.name,
    'start': _ymd(start),
    'event': event == null ? null : _ymd(event!),
  };

  static TrainingBlock fromJson(Map<String, dynamic> j) => TrainingBlock(
    goal: BlockGoal.values.byName(j['goal'] as String),
    start: DateTime.parse(j['start'] as String),
    event: j['event'] == null ? null : DateTime.parse(j['event'] as String),
  );
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _monday(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Whole weeks from [a]'s Monday to [b]'s (UTC, so DST can't shift it).
int _weeksBetween(DateTime a, DateTime b) {
  DateTime utc(DateTime d) {
    final m = _monday(d);
    return DateTime.utc(m.year, m.month, m.day);
  }

  return (utc(b).difference(utc(a)).inDays / 7).round();
}

/// An event needs this much lead time; longer plans are capped.
const blockMinWeeks = 4, blockMaxWeeks = 24;

/// Every [deloadEvery]th week of base and build is lighter.
const deloadEvery = 4;

/// Volume grows [levelStep] per absorbed week, up to [levelMax] steps.
const levelStep = .05, levelMax = 8;

/// Weekly volume on a deload week, and in the taper weeks before the race
/// week (the race week itself runs at [raceWeekVolume]).
const deloadVolume = .65, taperVolume = .6, raceWeekVolume = .4;

/// Taper length (race week included) and the long-session cap, by goal.
int taperWeeks(BlockGoal g) => switch (g) {
  BlockGoal.half || BlockGoal.marathon => 2,
  _ => 1,
};

int longCapMinutes(BlockGoal g) => switch (g) {
  BlockGoal.run5k => 60,
  BlockGoal.run10k => 75,
  BlockGoal.half => 110,
  BlockGoal.marathon => 160,
  BlockGoal.open => 90,
};

/// The phase of week [i] (0-based) of an event block of [n] weeks.
Phase eventPhase(int i, int n, BlockGoal g) {
  final taper = taperWeeks(g);
  if (i >= n - 1) return Phase.race;
  if (i >= n - taper) return Phase.taper;
  final peak = n >= 8 ? 2 : 1;
  if (i >= n - taper - peak) return Phase.peak;
  final early = n - taper - peak;
  if ((i + 1) % deloadEvery == 0) return Phase.deload;
  return i < (early * .4).round().clamp(1, early) ? Phase.base : Phase.build;
}

/// The phase of week [i] of an open block: the first cycle is base, then
/// build, each 4th week lighter.
Phase openPhase(int i) => (i + 1) % deloadEvery == 0
    ? Phase.deload
    : i < deloadEvery
    ? Phase.base
    : Phase.build;

/// How a finished week went, for deciding the next one.
final class WeekOutcome {
  const WeekOutcome({
    required this.planned,
    required this.done,
    this.recovery,
    this.feel,
  });

  /// Sessions planned (rest days not counted) and how many were done; a
  /// session done easier counts half.
  final int planned;
  final double done;

  /// Mean recovery and mean morning feel (1–5) that week, if known.
  final double? recovery, feel;

  double get ratio => planned == 0 ? 1 : done / planned;
}

/// Absorbed: ≥ 2/3 of the plan done, recovery ≥ 50, feel ≥ 3.
/// A bad week (under 1/3 done, recovery under 40 or feel under 2.5)
/// steps back; anything else holds.
const absorbRatio = 2 / 3, absorbRecovery = 50.0, absorbFeel = 3.0;
const backRatio = 1 / 3, backRecovery = 40.0, backFeel = 2.5;

enum WeekCall { stepUp, hold, stepBack }

WeekCall weekCall(WeekOutcome w) {
  final r = w.recovery, f = w.feel;
  if (w.ratio < backRatio ||
      (r != null && r < backRecovery) ||
      (f != null && f < backFeel)) {
    return WeekCall.stepBack;
  }
  if (w.ratio >= absorbRatio &&
      (r == null || r >= absorbRecovery) &&
      (f == null || f >= absorbFeel)) {
    return WeekCall.stepUp;
  }
  return WeekCall.hold;
}

/// One week of a block, as the planner uses it.
final class BlockWeek {
  const BlockWeek({
    required this.goal,
    required this.index,
    required this.weeks,
    required this.phase,
    required this.level,
    required this.lastCall,
    this.raceDay,
  });
  final BlockGoal goal;

  /// 0-based week of the block; [weeks] is 0 for an open block.
  final int index, weeks;
  final Phase phase;

  /// Absorbed weeks so far (0..[levelMax]).
  final int level;

  /// What last week's outcome did to [level] (null in week 1).
  final WeekCall? lastCall;

  /// Race day, 1 = Monday … 7 = Sunday, in the race week.
  final int? raceDay;

  /// Multiplier on session length this week.
  double get volume {
    final grown = 1 + levelStep * level;
    return switch (phase) {
      Phase.deload => grown * deloadVolume,
      Phase.taper => grown * taperVolume,
      Phase.race => grown * raceWeekVolume,
      _ => grown,
    };
  }

  /// Multiplier on the long session, which grows twice as fast.
  double get longVolume {
    final grown = 1 + 2 * levelStep * level;
    return switch (phase) {
      Phase.deload => grown * deloadVolume,
      Phase.taper => grown * taperVolume,
      Phase.race => 0, // the race is the long session
      _ => grown,
    };
  }

  /// Hard sessions this week, given the goal's usual number.
  int hard(int usual) => switch (phase) {
    Phase.base || Phase.deload || Phase.taper => min(1, usual),
    Phase.race => 0,
    Phase.build || Phase.peak => max(1, usual),
  };
}

/// Week [monday] of [b], replaying [past] (oldest first, one per finished
/// week of the block) to set the level. Null before the block starts or
/// after its race week.
BlockWeek? blockWeek(TrainingBlock b, DateTime monday, List<WeekOutcome> past) {
  final i = _weeksBetween(b.start, monday);
  if (i < 0) return null;
  if (b.isEvent && i >= b.weeks) return null;
  var level = 0;
  WeekCall? last;
  for (final (k, w) in past.take(i).indexed) {
    final ph = b.isEvent ? eventPhase(k, b.weeks, b.goal) : openPhase(k);
    // Only base and build weeks move the level; peak holds it.
    if (ph != Phase.base && ph != Phase.build) continue;
    last = weekCall(w);
    level = switch (last) {
      WeekCall.stepUp => min(levelMax, level + 1),
      WeekCall.hold => level,
      WeekCall.stepBack => max(0, level - 1),
    };
  }
  final phase = b.isEvent ? eventPhase(i, b.weeks, b.goal) : openPhase(i);
  return BlockWeek(
    goal: b.goal,
    index: i,
    weeks: b.weeks,
    phase: phase,
    level: level,
    lastCall: last,
    raceDay: phase == Phase.race ? b.event!.weekday : null,
  );
}

String goalName(BlockGoal g) => switch (g) {
  BlockGoal.open => 'Get fitter',
  BlockGoal.run5k => '5K',
  BlockGoal.run10k => '10K',
  BlockGoal.half => 'Half marathon',
  BlockGoal.marathon => 'Marathon',
};

String phaseName(Phase p) => switch (p) {
  Phase.base => 'Base',
  Phase.build => 'Build',
  Phase.peak => 'Peak',
  Phase.deload => 'Lighter week',
  Phase.taper => 'Taper',
  Phase.race => 'Race week',
};
