/// Training blocks: a goal (an event on a date, or open-ended "get
/// fitter"), the phase each week is in, and how much it has grown.
///
/// Weekly volume steps up about 5 % each week you absorbed (enough of the
/// plan done, recovery and how you felt holding), holds when you didn't,
/// and steps back after a bad week. Every 4th week is lighter. An event
/// ends in a peak and a taper, with the race on the last day.
///
/// One goal leads the plan. Shorter tune-up races sit inside it (each
/// replaces that week's hard session), and the next goal waits until a
/// recovery week after this one's race.
library;

import 'dart:math';

/// Version stamped on plan rows built from a block.
const blockAlgo = 'block-2';

enum BlockGoal { open, run5k, run10k, half, marathon }

enum Phase { base, build, peak, deload, taper, race }

/// A shorter race inside a block, run as that week's hard session.
final class TuneUp {
  const TuneUp({required this.goal, required this.date});

  /// The distance (never [BlockGoal.open]).
  final BlockGoal goal;
  final DateTime date;

  Map<String, Object?> toJson() => {'goal': goal.name, 'date': _ymd(date)};

  static TuneUp fromJson(Map<String, dynamic> j) => TuneUp(
    goal: BlockGoal.values.byName(j['goal'] as String),
    date: DateTime.parse(j['date'] as String),
  );
}

/// One training block. [start] is the Monday it began; [event] is the
/// race day (null for an open-ended block).
final class TrainingBlock {
  const TrainingBlock({
    required this.goal,
    required this.start,
    this.event,
    this.tuneUps = const [],
  });
  final BlockGoal goal;
  final DateTime start;
  final DateTime? event;

  /// Tune-up races, oldest first.
  final List<TuneUp> tuneUps;

  bool get isEvent => goal != BlockGoal.open && event != null;

  /// Weeks from [start] to the race week, inclusive.
  int get weeks => isEvent ? _weeksBetween(start, event!) + 1 : 0;

  /// 0-based week of the block that [day] falls in.
  int weekOf(DateTime day) => _weeksBetween(start, day);

  TrainingBlock withTuneUps(List<TuneUp> t) => TrainingBlock(
    goal: goal,
    start: start,
    event: event,
    tuneUps: [...t]..sort((a, b) => a.date.compareTo(b.date)),
  );

  Map<String, Object?> toJson() => {
    'goal': goal.name,
    'start': _ymd(start),
    'event': event == null ? null : _ymd(event!),
    if (tuneUps.isNotEmpty) 'tune_ups': [for (final t in tuneUps) t.toJson()],
  };

  static TrainingBlock fromJson(Map<String, dynamic> j) => TrainingBlock(
    goal: BlockGoal.values.byName(j['goal'] as String),
    start: DateTime.parse(j['start'] as String),
    event: j['event'] == null ? null : DateTime.parse(j['event'] as String),
    tuneUps: [
      for (final t in (j['tune_ups'] as List?) ?? const [])
        TuneUp.fromJson(t as Map<String, dynamic>),
    ],
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

/// Lead time that leaves room for a full base, build, peak and taper.
/// Shorter is allowed (down to [blockMinWeeks]) with a warning.
int recommendedWeeks(BlockGoal g) => switch (g) {
  BlockGoal.run5k => 6,
  BlockGoal.run10k => 8,
  BlockGoal.half => 10,
  BlockGoal.marathon => 16,
  BlockGoal.open => 0,
};

/// Weeks an event block on [event] would have if it started the week of
/// [from].
int eventWeeks(DateTime from, DateTime event) => _weeksBetween(from, event) + 1;

/// At most this many tune-up races in one block, at least
/// [tuneUpGapDays] before the goal race and one a week at most.
const tuneUpMax = 3, tuneUpGapDays = 14;

enum TuneUpProblem { tooMany, beforeStart, tooLate, sameWeek }

/// Why a tune-up on [date] doesn't fit [b] (null when it does). It must
/// fall inside the block, at least [tuneUpGapDays] before the race (so
/// never in the taper), and not in a week that already has one.
TuneUpProblem? tuneUpProblem(TrainingBlock b, DateTime date) {
  if (b.tuneUps.length >= tuneUpMax) return TuneUpProblem.tooMany;
  if (b.weekOf(date) < 0) return TuneUpProblem.beforeStart;
  if (b.isEvent) {
    final last = b.event!.subtract(const Duration(days: tuneUpGapDays));
    if (_dayKey(date) > _dayKey(last)) return TuneUpProblem.tooLate;
  }
  if (b.tuneUps.any((t) => b.weekOf(t.date) == b.weekOf(date))) {
    return TuneUpProblem.sameWeek;
  }
  return null;
}

/// The Monday the next goal starts after [b]: one easy recovery week after
/// the race week. Null for an open block (switch goal instead).
DateTime? nextBlockStart(TrainingBlock b) {
  if (!b.isEvent) return null;
  final m = _monday(b.event!);
  return DateTime(m.year, m.month, m.day + 14);
}

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

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
    this.prevPhase,
    this.raceDay,
    this.tuneUp,
  });
  final BlockGoal goal;

  /// 0-based week of the block; [weeks] is 0 for an open block.
  final int index, weeks;
  final Phase phase;

  /// Absorbed weeks so far (0..[levelMax]).
  final int level;

  /// What last week's outcome did to [level]. Null in week 1 and after a
  /// week that doesn't move the level (lighter, peak, taper).
  final WeekCall? lastCall;

  /// Last week's phase (null in week 1).
  final Phase? prevPhase;

  /// Race day, 1 = Monday … 7 = Sunday, in the race week.
  final int? raceDay;

  /// A tune-up race this week (never in the race week).
  final TuneUp? tuneUp;

  /// The tune-up's day, 1 = Monday … 7 = Sunday.
  int? get tuneUpDay => tuneUp?.date.weekday;

  /// First week of its phase (a phase change worth explaining).
  bool get newPhase => prevPhase != phase;

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

/// The phase of week [i] of [b].
Phase phaseOf(TrainingBlock b, int i) =>
    b.isEvent ? eventPhase(i, b.weeks, b.goal) : openPhase(i);

/// Only base and build weeks move the level; the rest hold it.
bool movesLevel(Phase p) => p == Phase.base || p == Phase.build;

int _next(int level, WeekCall c) => switch (c) {
  WeekCall.stepUp => min(levelMax, level + 1),
  WeekCall.hold => level,
  WeekCall.stepBack => max(0, level - 1),
};

/// Week [i] of [b] given each earlier week's call (index-aligned; missing
/// entries are treated as unknown and hold).
BlockWeek _weekAt(TrainingBlock b, int i, List<WeekCall?> calls) {
  var level = 0;
  WeekCall? last;
  for (var k = 0; k < i; k++) {
    final c = k < calls.length ? calls[k] : null;
    final moves = movesLevel(phaseOf(b, k)) && c != null;
    if (moves) level = _next(level, c);
    if (k == i - 1) last = moves ? c : null;
  }
  final phase = phaseOf(b, i);
  TuneUp? tune;
  if (phase != Phase.race) {
    for (final t in b.tuneUps) {
      if (b.weekOf(t.date) == i) tune = t;
    }
  }
  return BlockWeek(
    goal: b.goal,
    index: i,
    weeks: b.weeks,
    phase: phase,
    level: level,
    lastCall: last,
    prevPhase: i == 0 ? null : phaseOf(b, i - 1),
    raceDay: phase == Phase.race ? b.event!.weekday : null,
    tuneUp: tune,
  );
}

/// Week [monday] of [b], replaying [past] (oldest first, one per finished
/// week of the block) to set the level. Null before the block starts or
/// after its race week.
BlockWeek? blockWeek(TrainingBlock b, DateTime monday, List<WeekOutcome> past) {
  final i = _weeksBetween(b.start, monday);
  if (i < 0) return null;
  if (b.isEvent && i >= b.weeks) return null;
  return _weekAt(b, i, [for (final w in past.take(i)) weekCall(w)]);
}

/// One finished week, for the history list.
final class WeekRecord {
  const WeekRecord({
    required this.index,
    required this.phase,
    required this.outcome,
    required this.call,
    required this.level,
  });
  final int index;
  final Phase phase;
  final WeekOutcome outcome;

  /// What it did to the level; null for weeks that don't move it.
  final WeekCall? call;

  /// Level after this week.
  final int level;
}

/// Every finished week of [b] in [past] (oldest first), with its call.
List<WeekRecord> blockHistory(TrainingBlock b, List<WeekOutcome> past) {
  final out = <WeekRecord>[];
  var level = 0;
  for (final (k, w) in past.indexed) {
    if (b.isEvent && k >= b.weeks) break;
    final ph = phaseOf(b, k);
    final c = movesLevel(ph) ? weekCall(w) : null;
    if (c != null) level = _next(level, c);
    out.add(WeekRecord(index: k, phase: ph, outcome: w, call: c, level: level));
  }
  return out;
}

/// The whole block as it stands in week [current]: finished weeks as they
/// went (from [past]), this week, and every later week projected as if it
/// steps up. An open block shows [ahead] weeks past this one.
List<BlockWeek> projectBlock(
  TrainingBlock b,
  int current,
  List<WeekOutcome> past, {
  int ahead = 8,
}) {
  final n = b.isEvent ? b.weeks : max(current + 1 + ahead, deloadEvery * 2);
  final calls = <WeekCall?>[
    for (var k = 0; k < n; k++)
      k < current && k < past.length ? weekCall(past[k]) : WeekCall.stepUp,
  ];
  return [for (var i = 0; i < n; i++) _weekAt(b, i, calls)];
}

/// Where this week is heading, from what's done so far.
final class WeekForecast {
  const WeekForecast({
    required this.now,
    required this.best,
    required this.toStepUp,
    required this.toHold,
    required this.bodySaysBack,
  });

  /// The call if the week ended now, and with every session left done.
  final WeekCall now, best;

  /// More sessions needed for a step up / to avoid a step back; null when
  /// no number of sessions gets there this week.
  final int? toStepUp, toHold;

  /// Recovery or feel alone already means a step back, whatever is done.
  final bool bodySaysBack;
}

/// Forecast for a week with [soFar] (planned is the whole week's count,
/// done what's done so far) and [left] sessions still to come.
WeekForecast forecastWeek(WeekOutcome soFar, {required int left}) {
  WeekCall withMore(int k) => weekCall(
    WeekOutcome(
      planned: soFar.planned,
      done: soFar.done + k,
      recovery: soFar.recovery,
      feel: soFar.feel,
    ),
  );
  int? first(bool Function(WeekCall) ok) {
    for (var k = 0; k <= left; k++) {
      if (ok(withMore(k))) return k;
    }
    return null;
  }

  final r = soFar.recovery, f = soFar.feel;
  return WeekForecast(
    now: withMore(0),
    best: withMore(left),
    toStepUp: first((c) => c == WeekCall.stepUp),
    toHold: first((c) => c != WeekCall.stepBack),
    bodySaysBack:
        (r != null && r < backRecovery) || (f != null && f < backFeel),
  );
}

String goalName(BlockGoal g) => switch (g) {
  BlockGoal.open => 'Get fitter',
  BlockGoal.run5k => '5K',
  BlockGoal.run10k => '10K',
  BlockGoal.half => 'Half marathon',
  BlockGoal.marathon => 'Marathon',
};

/// What a phase is for, in a sentence.
String phaseSay(Phase p) => switch (p) {
  Phase.base =>
    'Easy aerobic running to build the engine, with one hard session.',
  Phase.build =>
    'Longer sessions and two hard ones. It grows each week you handle well.',
  Phase.peak =>
    'The hardest weeks, at race effort. The size holds steady; no step-ups.',
  Phase.deload =>
    'About a third shorter with one hard session, so the last weeks sink in. '
        "It doesn't count for or against you.",
  Phase.taper =>
    'About 40 % less, keeping a little speed, so you arrive fresh.',
  Phase.race => 'Very light. Rest the day before, then race.',
};

String phaseName(Phase p) => switch (p) {
  Phase.base => 'Base',
  Phase.build => 'Build',
  Phase.peak => 'Peak',
  Phase.deload => 'Lighter week',
  Phase.taper => 'Taper',
  Phase.race => 'Race week',
};
