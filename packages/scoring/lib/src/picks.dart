/// Today's picks: three workouts to choose from — a run, a strength session
/// and a game (or another sport you like) — each sized to today's
/// readiness, what you did this week and the time left before bed, with
/// exactly what to do in it. One is marked as Tempo's pick.
///
/// Rules, in order of precedence (decisions.md, 2026-10-16):
/// * **How hard.** Unwell signals, a rest day, under an hour to bed, or
///   today's strain target already reached → easy only (level 0). Ease
///   off, a short night, calibrating, or under 4 h to bed → moderate at
///   most (level 1). A go day → hard allowed (level 2).
/// * **No stacking.** No hard run within 48 h of a hard day, and at most
///   two hard days a week (the polarised split most coaches use).
/// * **Strength rotates** lower / upper / full by what was trained least
///   recently; never lower body the day before a hard or long run.
/// * **Games** rotate through the ones you play, least recent first.
/// * **The coach's plan wins.** If today's plan is a run, strength or a
///   game and fits the level, that pick is the plan (with details), and
///   it's the recommended one.
library;

import 'dart:math';

import 'coach.dart';
import 'recovery.dart' show RecoveryColor;
import 'strength.dart';

enum PickKind { run, strength, play }

/// What kind of run, and why you'd do it.
enum RunType {
  recovery,
  easy,
  strides,
  long,
  tempo,
  threshold,
  vo2,
  hills,
  fartlek,
}

enum StrengthFocus { lower, upper, full, core }

/// Games and sports Tempo can suggest. Stored by name.
enum Game {
  badminton,
  tableTennis,
  tennis,
  squash,
  pickleball,
  football,
  basketball,
  volleyball,
  cricket,
  swimming,
}

String gameName(Game g) => switch (g) {
  Game.badminton => 'Badminton',
  Game.tableTennis => 'Table tennis',
  Game.tennis => 'Tennis',
  Game.squash => 'Squash',
  Game.pickleball => 'Pickleball',
  Game.football => 'Football',
  Game.basketball => 'Basketball',
  Game.volleyball => 'Volleyball',
  Game.cricket => 'Cricket',
  Game.swimming => 'Swimming',
};

/// The game a workout title names, if any ("Badminton", "Table tennis").
Game? gameInTitle(String title) {
  final t = title.toLowerCase().replaceAll('_', ' ');
  for (final g in Game.values) {
    if (t.contains(gameName(g).toLowerCase())) return g;
  }
  return null;
}

String runTypeName(RunType r) => switch (r) {
  RunType.recovery => 'Recovery run',
  RunType.easy => 'Easy run',
  RunType.strides => 'Easy run + strides',
  RunType.long => 'Long run',
  RunType.tempo => 'Tempo run',
  RunType.threshold => 'Threshold intervals',
  RunType.vo2 => 'VO₂ max intervals',
  RunType.hills => 'Hill repeats',
  RunType.fartlek => 'Fartlek',
};

String focusName(StrengthFocus f) => switch (f) {
  StrengthFocus.lower => 'Lower body',
  StrengthFocus.upper => 'Upper body',
  StrengthFocus.full => 'Full body',
  StrengthFocus.core => 'Core and mobility',
};

// ---- details --------------------------------------------------------------

/// One exercise: the gym version, and what to do at home instead.
final class Exercise {
  const Exercise(
    this.name, {
    required this.sets,
    required this.reps,
    this.home,
    this.restSeconds = 90,
    this.cue = '',
    this.kg,
    this.target,
  });
  final String name;
  final String? home;
  final int sets;

  /// Suggested load from your history (strength.dart → nextTarget), and
  /// why; null without logged sets.
  final double? kg;
  final String? target;

  Exercise withTarget(double kg, int sets, String reps, String why) => Exercise(
    name,
    home: home,
    sets: sets,
    reps: reps,
    restSeconds: restSeconds,
    cue: cue,
    kg: kg,
    target: why,
  );

  /// "8–10", "5", "30 s", "10 each side".
  final String reps;
  final int restSeconds;
  final String cue;

  Map<String, Object?> toJson() => {
    'n': name,
    'h': home,
    's': sets,
    'r': reps,
    'rest': restSeconds,
    'c': cue,
    if (kg != null) 'kg': kg,
    if (target != null) 'tw': target,
  };
  static Exercise fromJson(Map<String, dynamic> j) => Exercise(
    j['n'] as String,
    home: j['h'] as String?,
    sets: j['s'] as int,
    reps: j['r'] as String,
    restSeconds: j['rest'] as int? ?? 90,
    cue: j['c'] as String? ?? '',
    kg: (j['kg'] as num?)?.toDouble(),
    target: j['tw'] as String?,
  );
}

/// What to do in a picked session. Stored inside the plan's session JSON.
sealed class PickDetail {
  const PickDetail();
  PickKind get kind;

  /// How it should feel, in one line.
  String get effort;

  /// What it's for.
  String get purpose;
  Map<String, Object?> toJson();

  static PickDetail? fromJson(Map<String, dynamic> j) {
    try {
      return switch (j['t']) {
        'run' => RunDetail(
          RunType.values.byName(j['run'] as String),
          effort: j['e'] as String,
          purpose: j['p'] as String,
          cues: [for (final c in j['c'] as List) c as String],
        ),
        'strength' => StrengthDetail(
          StrengthFocus.values.byName(j['f'] as String),
          exercises: [
            for (final e in j['x'] as List)
              Exercise.fromJson((e as Map).cast<String, dynamic>()),
          ],
          effort: j['e'] as String,
          purpose: j['p'] as String,
          circuit: j['circ'] as bool? ?? false,
          warmup: j['w'] as String? ?? '',
        ),
        'play' => PlayDetail(
          game: j['g'] == null ? null : Game.values.byName(j['g'] as String),
          format: j['fmt'] as String,
          effort: j['e'] as String,
          purpose: j['p'] as String,
          cues: [for (final c in j['c'] as List) c as String],
        ),
        _ => null,
      };
    } catch (_) {
      return null; // an older or damaged detail: the session still works
    }
  }
}

final class RunDetail extends PickDetail {
  const RunDetail(
    this.type, {
    required this.effort,
    required this.purpose,
    this.cues = const [],
  });
  final RunType type;
  @override
  final String effort, purpose;
  final List<String> cues;
  @override
  PickKind get kind => PickKind.run;
  @override
  Map<String, Object?> toJson() => {
    't': 'run',
    'run': type.name,
    'e': effort,
    'p': purpose,
    'c': cues,
  };
}

final class StrengthDetail extends PickDetail {
  const StrengthDetail(
    this.focus, {
    required this.exercises,
    required this.effort,
    required this.purpose,
    this.circuit = false,
    this.warmup = '',
  });
  final StrengthFocus focus;
  final List<Exercise> exercises;
  @override
  final String effort, purpose;

  /// Done as rounds (one set of each in turn) rather than set by set.
  final bool circuit;
  final String warmup;
  @override
  PickKind get kind => PickKind.strength;
  @override
  Map<String, Object?> toJson() => {
    't': 'strength',
    'f': focus.name,
    'x': [for (final e in exercises) e.toJson()],
    'e': effort,
    'p': purpose,
    'circ': circuit,
    'w': warmup,
  };
}

final class PlayDetail extends PickDetail {
  const PlayDetail({
    required this.game,
    required this.format,
    required this.effort,
    required this.purpose,
    this.cues = const [],
  });

  /// null when the pick is another sport you like (a ride, yoga, a walk).
  final Game? game;
  final String format;
  @override
  final String effort, purpose;
  final List<String> cues;
  @override
  PickKind get kind => PickKind.play;
  @override
  Map<String, Object?> toJson() => {
    't': 'play',
    'g': game?.name,
    'fmt': format,
    'e': effort,
    'p': purpose,
    'c': cues,
  };
}

// ---- inputs ---------------------------------------------------------------

/// One thing done on a recent day, as the picks need it.
final class RecentSession {
  const RecentSession({
    required this.day,
    required this.sport,
    this.hard = false,
    this.minutes = 0,
    this.key,
    this.focus,
    this.game,
  });
  final DateTime day; // local midnight
  final Sport? sport;
  final bool hard;
  final int minutes;

  /// Plan template key when known (e.g. `tempo_run`).
  final String? key;
  final StrengthFocus? focus;
  final Game? game;
}

final class PickContext {
  const PickContext({
    required this.today,
    required this.state,
    this.recoveryColor,
    this.targetHi = 21,
    this.strainSoFar = 0,
    this.unwell = false,
    this.shortNight = false,
    this.goal = Goal.fitness,
    this.likes = const {},
    this.games = const {},
    this.maxMinutes = 60,
    this.minutesToBed,
    this.planned,
    this.tomorrow,
    this.recent = const [],
    this.freshness,
  });

  final DateTime today; // local midnight
  final DayState state;
  final RecoveryColor? recoveryColor;

  /// Top of today's strain target, and what's done so far.
  final double targetHi, strainSoFar;

  /// Body signals off together, or the illness flag on resting HR.
  final bool unwell;
  final bool shortNight;
  final Goal goal;
  final Set<Sport> likes;
  final Set<Game> games;
  final int maxMinutes;

  /// Minutes until tonight's bedtime; null when unknown.
  final int? minutesToBed;

  /// Today's plan from the coach (null or rest when none).
  final Session? planned;
  final Session? tomorrow;

  /// The last 14 days or so, any order.
  final List<RecentSession> recent;

  /// Muscle freshness from logged sets (strength.dart); null when nothing
  /// was logged lately, and focus falls back to days since.
  final Map<Muscle, double>? freshness;
}

final class Pick {
  const Pick({
    required this.kind,
    required this.session,
    required this.why,
    this.recommended = false,
  });
  final PickKind kind;

  /// Carries its [PickDetail] in [Session.detail].
  final Session session;

  /// Why this, today, in one sentence.
  final String why;
  final bool recommended;

  PickDetail get detail => session.detail!;

  Pick withRecommended(bool r) =>
      Pick(kind: kind, session: session, why: why, recommended: r);

  /// The same pick with a new detail (e.g. your weights filled in).
  Pick withDetail(PickDetail d) => Pick(
    kind: kind,
    session: _withDetail(session, d),
    why: why,
    recommended: recommended,
  );
}

/// The level today allows: 0 easy only, 1 moderate at most, 2 hard.
int pickLevel(PickContext c) {
  if (c.unwell || c.state == DayState.rest) return 0;
  if (c.minutesToBed != null && c.minutesToBed! < 60) return 0;
  if (c.strainSoFar >= c.targetHi) return 0;
  if (c.state == DayState.easeOff ||
      c.state == DayState.general ||
      c.shortNight ||
      (c.minutesToBed != null && c.minutesToBed! < 240)) {
    return 1;
  }
  return 2;
}

/// Why the level is what it is, for the lead line.
String levelReason(PickContext c) {
  if (c.unwell) return 'Your body signals say take it easy';
  if (c.state == DayState.rest) return 'A rest day';
  if (c.minutesToBed != null && c.minutesToBed! < 60) {
    return 'Under an hour to bedtime';
  }
  if (c.strainSoFar >= c.targetHi) return 'You’ve reached today’s target';
  if (c.shortNight) return 'After a short night';
  if (c.state == DayState.easeOff) return 'Recovery says ease off';
  if (c.state == DayState.general) return 'While Tempo learns your baseline';
  if (c.minutesToBed != null && c.minutesToBed! < 240) {
    return 'Late in the day: nothing hard within 4 h of bed';
  }
  return 'You’re recovered';
}

int _daysSince(PickContext c, bool Function(RecentSession) test) {
  var best = 99;
  for (final r in c.recent) {
    if (!test(r)) continue;
    final d = c.today.difference(r.day).inDays;
    if (d >= 0 && d < best) best = d;
  }
  return best;
}

DateTime _monday(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

int _hardThisWeek(PickContext c) {
  final mon = _monday(c.today);
  return {
    for (final r in c.recent)
      if (r.hard && !r.day.isBefore(mon) && r.day.isBefore(c.today)) r.day,
  }.length;
}

/// Three picks, Tempo's recommended one marked. Always a run, a strength
/// session and a game or other sport, in that order.
List<Pick> dailyPicks(PickContext c) {
  final level = pickLevel(c);
  final picks = [
    _runPick(c, level),
    _strengthPick(c, level),
    _playPick(c, level),
  ];
  final rec = _recommend(c, level, picks);
  return [for (final (i, p) in picks.indexed) p.withRecommended(i == rec)];
}

int _recommend(PickContext c, int level, List<Pick> picks) {
  final plan = c.planned;
  if (plan != null && !plan.isRest) {
    final kind = switch (plan.sport) {
      Sport.running => PickKind.run,
      Sport.strength => PickKind.strength,
      Sport.sport => PickKind.play,
      _ => null,
    };
    final i = picks.indexWhere(
      (p) => p.kind == kind && p.session.key == plan.key,
    );
    if (i >= 0) return i;
  }
  if (level == 0) return 1; // core and mobility is the gentlest
  final mon = _monday(c.today);
  final strengthDays = {
    for (final r in c.recent)
      if (r.sport == Sport.strength && !r.day.isBefore(mon)) r.day,
  }.length;
  // WHO: two strength days a week. Behind with three or fewer days left
  // in the week → strength first.
  if (strengthDays < 2 && c.today.weekday >= 5 - strengthDays) return 1;
  if (picks[0].session.isHard || picks[0].session.key == 'long_run') {
    return 0;
  }
  if (c.games.isNotEmpty && _daysSince(c, (r) => r.game != null) >= 4) {
    return 2;
  }
  if (strengthDays < 2 &&
      _daysSince(c, (r) => r.sport == Sport.strength) >= 2) {
    return 1;
  }
  return c.likes.contains(Sport.running) || c.likes.isEmpty ? 0 : 2;
}

// ---- run ------------------------------------------------------------------

const _runKey = {
  RunType.recovery: 'recovery_run',
  RunType.easy: 'easy_run',
  RunType.strides: 'strides_run',
  RunType.long: 'long_run',
  RunType.tempo: 'tempo_run',
  RunType.threshold: 'threshold_run',
  RunType.vo2: 'vo2_run',
  RunType.hills: 'hill_run',
  RunType.fartlek: 'fartlek_run',
};

RunType? runTypeForKey(String key) {
  for (final e in _runKey.entries) {
    if (e.value == key) return e.key;
  }
  if (key == 'aerobic_run' || key == 'steady_run') return RunType.easy;
  return null;
}

RunDetail runDetail(RunType t) => switch (t) {
  RunType.recovery => const RunDetail(
    RunType.recovery,
    effort:
        'Very easy (Z1–Z2): slower than feels natural, nose-breathing pace.',
    purpose: 'Gets blood moving without adding fatigue.',
    cues: ['Walk breaks are fine', 'Stop early if your legs feel heavy'],
  ),
  RunType.easy => const RunDetail(
    RunType.easy,
    effort: 'Easy (Z2): you could talk in full sentences.',
    purpose: 'Builds your aerobic base — most of your running should feel like this.',
    cues: ['Keep heart rate in Z2 even on hills; walk them if needed'],
  ),
  RunType.strides => const RunDetail(
    RunType.strides,
    effort: 'Easy (Z2), with 6 short fast-but-relaxed strides near the end.',
    purpose:
        'Keeps speed and running form sharp without the cost of a hard day.',
    cues: [
      'In the last 10 minutes: 6 × 20 s strides, building to about 90 % of top speed',
      'Walk or jog 60 s between strides',
      'Smooth and tall, never a sprint',
    ],
  ),
  RunType.long => const RunDetail(
    RunType.long,
    effort: 'Steady and easy (Z2) the whole way.',
    purpose: 'Endurance: more time on your feet makes every other run easier.',
    cues: [
      'Start slower than you want to',
      'Over 75 minutes: take water and some carbs',
    ],
  ),
  RunType.tempo => const RunDetail(
    RunType.tempo,
    effort: 'Middle block comfortably hard (Z3): a few words at a time.',
    purpose: 'Raises the pace you can hold for a long time.',
    cues: [
      '10 min easy, 20 min steady-hard, 10 min easy',
      'Even effort; finish feeling you could do 10 more minutes',
    ],
  ),
  RunType.threshold => const RunDetail(
    RunType.threshold,
    effort: 'Work reps hard but controlled (Z4): a pace you could hold ~45 minutes.',
    purpose: 'Lifts your lactate threshold — the biggest lever for 5K to half marathon.',
    cues: [
      'Recoveries are a slow jog, not a stop',
      'Last rep should feel as controlled as the first',
    ],
  ),
  RunType.vo2 => const RunDetail(
    RunType.vo2,
    effort: 'Work reps hard (Z5): heavy breathing, can’t talk.',
    purpose: 'Raises VO₂ max, your aerobic ceiling.',
    cues: [
      'Run the first rep slightly slower than you think',
      'Full recovery jogs: quality over quantity',
      'Stop the set if pace falls apart',
    ],
  ),
  RunType.hills => const RunDetail(
    RunType.hills,
    effort: 'Strong uphill efforts (Z4–Z5), very easy back down.',
    purpose:
        'Leg strength and power, easier on the joints than flat speedwork.',
    cues: [
      'Find a moderate slope you can run up for 60 s',
      'Drive the arms, short quick steps, look ahead',
      'Walk or jog slowly back down',
    ],
  ),
  RunType.fartlek => const RunDetail(
    RunType.fartlek,
    effort: 'Alternate 2 min quicker (Z4) and 2 min easy (Z2).',
    purpose: 'Speed play: works pace changes without the pressure of a track.',
    cues: [
      'Use landmarks if you like: lamppost to lamppost',
      'Quick, not all-out',
    ],
  ),
};

Session runSession(RunType t, int maxMinutes, {double volume = 1}) {
  var s = sessionTemplate(_runKey[t]!);
  if (volume != 1) s = scaled(s, volume);
  s = fitMinutes(s, maxMinutes);
  return _withDetail(s, runDetail(t));
}

Session _withDetail(Session s, PickDetail d, {String? title, Sport? sport}) =>
    Session(
      key: s.key,
      title: title ?? s.title,
      sport: sport ?? s.sport,
      segments: s.segments,
      strainLo: s.strainLo,
      strainHi: s.strainHi,
      intensity: s.intensity,
      note: s.note,
      detail: d,
    );

RunType _qualityRun(PickContext c) {
  final options = switch (c.goal) {
    Goal.performance => [RunType.threshold, RunType.vo2, RunType.hills],
    Goal.fitness => [
      RunType.threshold,
      RunType.fartlek,
      RunType.vo2,
      RunType.hills,
    ],
    Goal.fatLoss => [RunType.fartlek, RunType.hills, RunType.tempo],
    Goal.wellbeing => [RunType.fartlek, RunType.tempo],
  };
  // The type done least recently (never done counts as longest ago).
  RunType best = options.first;
  var bestDays = -1;
  for (final t in options) {
    final d = _daysSince(c, (r) => r.key == _runKey[t]);
    if (d > bestDays) {
      best = t;
      bestDays = d;
    }
  }
  return best;
}

Pick _runPick(PickContext c, int level) {
  final plan = c.planned;
  final planRun = plan != null && plan.sport == Sport.running
      ? runTypeForKey(plan.key)
      : null;
  final hardRecent = _daysSince(c, (r) => r.hard) < 2;
  final weekHard = _hardThisWeek(c);
  // The coach's run, when today allows it.
  if (planRun != null && (level == 2 || !plan!.isHard) && level > 0) {
    return Pick(
      kind: PickKind.run,
      session: _withDetail(plan!, runDetail(planRun)),
      why:
          'Today’s planned run${plan.isHard ? ': your legs are ready for it' : ''}.',
    );
  }
  if (level == 0) {
    return Pick(
      kind: PickKind.run,
      session: runSession(RunType.recovery, min(c.maxMinutes, 25)),
      why: '${levelReason(c)}: if you run, keep it short and very easy.',
    );
  }
  if (level == 2 && !hardRecent && weekHard < 2) {
    final t = _qualityRun(c);
    return Pick(
      kind: PickKind.run,
      session: runSession(t, c.maxMinutes),
      why:
          '${levelReason(c)} and your last hard day was ${_daysSince(c, (r) => r.hard) >= 99 ? 'a while ago' : '${_daysSince(c, (r) => r.hard)} days ago'}: a good day for quality.',
    );
  }
  final sinceLong = _daysSince(
    c,
    (r) => r.key == 'long_run' || (r.sport == Sport.running && r.minutes >= 60),
  );
  if (sinceLong >= 6 && c.maxMinutes >= 50 && level >= 1 && !hardRecent) {
    return Pick(
      kind: PickKind.run,
      session: runSession(RunType.long, c.maxMinutes),
      why:
          'No long run for ${sinceLong >= 99 ? 'a while' : '$sinceLong days'}: time on your feet builds endurance.',
    );
  }
  final sinceStrides = _daysSince(c, (r) => r.key == 'strides_run');
  final t = sinceStrides >= 4 && level == 2 ? RunType.strides : RunType.easy;
  return Pick(
    kind: PickKind.run,
    session: runSession(t, c.maxMinutes),
    why: hardRecent
        ? 'A hard day was less than 48 h ago: easy running lets it pay off.'
        : weekHard >= 2
        ? 'Two hard days already this week: keep the rest easy.'
        : '${levelReason(c)}: easy aerobic running.',
  );
}

// ---- strength -------------------------------------------------------------

const _focusKey = {
  StrengthFocus.lower: 'strength_lower',
  StrengthFocus.upper: 'strength_upper',
  StrengthFocus.full: 'strength_full',
  StrengthFocus.core: 'strength_core',
};

StrengthFocus? focusForKey(String key) {
  for (final e in _focusKey.entries) {
    if (e.value == key) return e.key;
  }
  return null;
}

/// Sets, reps, rest and effort for today: easier days do less and stop
/// further from failure (RIR = reps in reserve).
({
  int sets,
  String reps,
  String heavyReps,
  int rest,
  String effort,
  bool circuit,
})
_dose(Goal goal, int level) {
  if (level == 0) {
    return (
      sets: 2,
      reps: '10',
      heavyReps: '10',
      rest: 60,
      effort: 'Light: stop with 4 or more reps left in the tank.',
      circuit: false,
    );
  }
  if (level == 1) {
    return (
      sets: 3,
      reps: '8–12',
      heavyReps: '8–10',
      rest: 75,
      effort: 'Moderate: finish each set with 2–3 good reps left.',
      circuit: goal == Goal.fatLoss,
    );
  }
  return switch (goal) {
    Goal.performance => (
      sets: 4,
      reps: '8–10',
      heavyReps: '5',
      rest: 120,
      effort: 'Hard: heavy first two lifts, 1–2 reps left; accessories 2 left.',
      circuit: false,
    ),
    Goal.fatLoss => (
      sets: 3,
      reps: '40 s',
      heavyReps: '40 s',
      rest: 20,
      effort: 'Circuit: 40 s work, 20 s to switch, 90 s between rounds.',
      circuit: true,
    ),
    Goal.wellbeing => (
      sets: 3,
      reps: '10–12',
      heavyReps: '10',
      rest: 75,
      effort: 'Moderate: 2–3 reps left on every set.',
      circuit: false,
    ),
    Goal.fitness => (
      sets: 4,
      reps: '8–12',
      heavyReps: '6–8',
      rest: 90,
      effort: 'Hard but clean: 1–2 reps left on the main lifts.',
      circuit: false,
    ),
  };
}

List<Exercise> strengthExercises(StrengthFocus f, Goal goal, int level) {
  final d = _dose(goal, level);
  Exercise main(String n, String home, String cue) => Exercise(
    n,
    home: home,
    sets: d.sets,
    reps: d.heavyReps,
    restSeconds: d.circuit ? d.rest : max(d.rest, 90),
    cue: cue,
  );
  Exercise acc(String n, String home, String cue, {String? reps}) => Exercise(
    n,
    home: home,
    sets: max(2, d.sets - 1),
    reps: reps ?? d.reps,
    restSeconds: d.circuit ? d.rest : 60,
    cue: cue,
  );
  return switch (f) {
    StrengthFocus.lower => [
      main(
        'Back squat',
        'Goblet squat holding a backpack',
        'Hips back and down, knees track over toes',
      ),
      main(
        'Romanian deadlift',
        'Single-leg RDL',
        'Soft knees, push the hips back, flat back',
      ),
      acc(
        'Bulgarian split squat',
        'Same, bodyweight',
        'Front knee over mid-foot',
        reps: '8 each side',
      ),
      acc('Hip thrust', 'Glute bridge', 'Squeeze at the top for a second'),
      acc(
        'Calf raise',
        'Single-leg calf raise on a step',
        'Slow down, full stretch',
        reps: '15',
      ),
      acc('Plank', 'Plank', 'Ribs down, glutes tight', reps: '30–45 s'),
    ],
    StrengthFocus.upper => [
      main(
        'Bench press',
        'Push-up (feet raised if easy)',
        'Shoulder blades back, elbows ~45°',
      ),
      main(
        'Bent-over row',
        'Backpack row',
        'Pull to the lower ribs, no swinging',
      ),
      acc('Overhead press', 'Pike push-up', 'Brace the core, don’t arch'),
      acc(
        'Lat pulldown or pull-up',
        'Towel row on a door',
        'Chest up, lead with the elbows',
      ),
      acc(
        'Face pull',
        'Band pull-apart or reverse fly',
        'For shoulder health',
        reps: '15',
      ),
      acc(
        'Dead bug',
        'Dead bug',
        'Lower back stays on the floor',
        reps: '8 each side',
      ),
    ],
    StrengthFocus.full => [
      main(
        'Goblet squat',
        'Bodyweight squat, slow down',
        'Sit between the heels',
      ),
      main('Romanian deadlift', 'Single-leg RDL', 'Hinge, don’t squat'),
      acc('Push-up or bench press', 'Push-up', 'Body in one line'),
      acc('One-arm dumbbell row', 'Backpack row', 'Pull to the hip'),
      acc(
        'Farmer carry',
        'Carry two heavy bags',
        'Tall posture, slow steps',
        reps: '40 m',
      ),
      acc('Side plank', 'Side plank', 'Hips high', reps: '30 s each side'),
    ],
    StrengthFocus.core => const [
      Exercise(
        'Dead bug',
        sets: 2,
        reps: '8 each side',
        restSeconds: 30,
        cue: 'Slow, lower back down',
      ),
      Exercise('Side plank', sets: 2, reps: '30 s each side', restSeconds: 30),
      Exercise(
        'Bird dog',
        sets: 2,
        reps: '8 each side',
        restSeconds: 30,
        cue: 'Reach long, hips level',
      ),
      Exercise('Glute bridge', sets: 2, reps: '12', restSeconds: 30),
      Exercise(
        'Hip flexor stretch',
        sets: 1,
        reps: '45 s each side',
        restSeconds: 0,
      ),
      Exercise(
        'Thoracic rotation',
        sets: 1,
        reps: '8 each side',
        restSeconds: 0,
      ),
    ],
  };
}

StrengthDetail strengthDetail(StrengthFocus f, Goal goal, int level) {
  final d = _dose(goal, level);
  return StrengthDetail(
    f,
    exercises: strengthExercises(f, goal, level),
    effort: f == StrengthFocus.core
        ? 'Easy and controlled: quality over load.'
        : d.effort,
    purpose: switch (f) {
      StrengthFocus.lower =>
        'Leg and hip strength: protects knees and makes running stronger.',
      StrengthFocus.upper =>
        'Push and pull balance for posture and shoulder health.',
      StrengthFocus.full =>
        'Every major muscle in one go: the most for your time.',
      StrengthFocus.core => 'Trunk stability and mobility; fine on any day.',
    },
    circuit: d.circuit && f != StrengthFocus.core,
    warmup: f == StrengthFocus.core
        ? ''
        : '5 min easy cardio, then one light set of the first two lifts.',
  );
}

Pick _strengthPick(PickContext c, int level) {
  final plan = c.planned;
  final planFocus = plan != null && plan.sport == Sport.strength
      ? focusForKey(plan.key)
      : null;
  if (planFocus != null && level > 0) {
    return Pick(
      kind: PickKind.strength,
      session: _withDetail(
        plan!,
        strengthDetail(planFocus, c.goal, level),
        title: focusName(planFocus),
      ),
      why: 'Today’s planned strength session.',
    );
  }
  if (level == 0) {
    return Pick(
      kind: PickKind.strength,
      session: _withDetail(
        fitMinutes(sessionTemplate('strength_core'), c.maxMinutes),
        strengthDetail(StrengthFocus.core, c.goal, 0),
        title: focusName(StrengthFocus.core),
      ),
      why:
          '${levelReason(c)}: gentle core and mobility helps without adding strain.',
    );
  }
  int since(StrengthFocus f) => _daysSince(
    c,
    (r) =>
        r.sport == Sport.strength &&
        (r.focus == f || r.focus == StrengthFocus.full || r.focus == null),
  );
  // Never legs the day before a hard or long run.
  final legsTomorrow =
      c.tomorrow != null &&
      c.tomorrow!.sport == Sport.running &&
      (c.tomorrow!.isHard || c.tomorrow!.key == 'long_run');
  final legsYesterday = c.recent.any(
    (r) =>
        c.today.difference(r.day).inDays == 1 &&
        r.sport == Sport.running &&
        (r.hard || r.minutes >= 60),
  );
  final candidates =
      [StrengthFocus.lower, StrengthFocus.upper, StrengthFocus.full].where(
        (f) => !((legsTomorrow || legsYesterday) && f != StrengthFocus.upper),
      );
  StrengthFocus focus = StrengthFocus.upper;
  var best = -1;
  final fr = c.freshness;
  String? freshWhy;
  if (fr != null) {
    // Freshest half first; full body only when both are fresh.
    final lo = lowerFreshness(fr), up = upperFreshness(fr);
    var score = -1.0;
    for (final f in candidates) {
      final v = switch (f) {
        StrengthFocus.lower => lo,
        StrengthFocus.upper => up,
        _ => min(lo, up) >= 80 ? min(lo, up) + 1 : -1.0,
      };
      if (v > score) {
        score = v;
        focus = f;
      }
    }
    best = 0;
    freshWhy =
        'Legs ${lo.round()} % fresh, upper body ${up.round()} %: ${focusName(focus).toLowerCase()} today.';
  } else {
    for (final f in candidates) {
      // Full body is the default only when both halves are equally due.
      final d = f == StrengthFocus.full
          ? min(since(StrengthFocus.lower), since(StrengthFocus.upper)) - 1
          : since(f);
      if (d > best) {
        best = d;
        focus = f;
      }
    }
  }
  final minutes = min(c.maxMinutes, level == 2 ? 50 : 40);
  final base = fitMinutes(sessionTemplate(_focusKey[focus]!), minutes);
  final s = level == 1 ? scaled(base, .85, cap: minutes) : base;
  final why = legsTomorrow
      ? 'Upper body today, so your legs are fresh for tomorrow’s run.'
      : legsYesterday
      ? 'Upper body today: your legs worked hard yesterday.'
      : freshWhy != null
      ? freshWhy
      : best >= 99
      ? '${focusName(focus)}: not trained recently.'
      : '${focusName(focus)} last trained $best days ago.';
  return Pick(
    kind: PickKind.strength,
    session: _withDetail(
      s,
      strengthDetail(focus, c.goal, level),
      title: focusName(focus),
    ),
    why: why,
  );
}

// ---- play -----------------------------------------------------------------

PlayDetail playDetail(Game g, int level) {
  final swim = g == Game.swimming;
  return switch (level) {
    0 => PlayDetail(
      game: g,
      format: swim
          ? 'Easy laps, any stroke, rest whenever you like'
          : 'Easy hit or casual knock-about, no scoring',
      effort: 'Relaxed (Z1–Z2). Stop before you tire.',
      purpose: 'Moving and enjoying it, without adding strain.',
      cues: ['20–30 minutes is plenty'],
    ),
    1 => PlayDetail(
      game: g,
      format: swim
          ? '10 × 50 m steady, 20 s rest'
          : 'Drills and rallies, no competitive matches',
      effort: 'Steady (Z2–Z3): you could still chat between points.',
      purpose: 'Skill and fitness at a sustainable effort.',
      cues: [
        'Warm up 10 minutes before going harder',
        'Keep rallies long rather than fast',
      ],
    ),
    _ => PlayDetail(
      game: g,
      format: swim
          ? '8 × 100 m strong, 30 s rest, then easy laps'
          : 'Warm up, then match play',
      effort: 'Hard in bursts (Z3–Z4) with recovery between points.',
      purpose: 'High-intensity intervals that don’t feel like training.',
      cues: [
        '10 minutes of easy rallies and dynamic stretches first',
        'Cool down and stretch calves and hips after',
      ],
    ),
  };
}

Pick _playPick(PickContext c, int level) {
  final plan = c.planned;
  // Games, least recently played first.
  if (c.games.isNotEmpty) {
    final ordered = [...c.games]..sort((a, b) => a.index.compareTo(b.index));
    var g = ordered.first;
    var best = -1;
    for (final x in ordered) {
      final d = _daysSince(c, (r) => r.game == x);
      if (d > best) {
        best = d;
        g = x;
      }
    }
    if (plan != null &&
        plan.sport == Sport.sport &&
        plan.detail is PlayDetail) {
      final pg = (plan.detail! as PlayDetail).game;
      if (pg != null) g = pg;
    }
    final minutes = switch (level) {
      0 => min(c.maxMinutes, 30),
      1 => min(c.maxMinutes, 45),
      _ => min(c.maxMinutes, 60),
    };
    final base = level == 0
        ? Session(
            key: 'sport',
            title: gameName(g),
            sport: Sport.sport,
            segments: [Segment(minutes, 2)],
            strainLo: 3,
            strainHi: 6,
            intensity: Intensity.easy,
          )
        : level == 1
        ? Session(
            key: 'sport',
            title: gameName(g),
            sport: Sport.sport,
            segments: [
              const Segment(10, 2),
              Segment(max(10, minutes - 15), 3),
              const Segment(5, 1),
            ],
            strainLo: 7,
            strainHi: 10,
            intensity: Intensity.moderate,
          )
        : fitMinutes(sessionTemplate('sport'), minutes);
    return Pick(
      kind: PickKind.play,
      session: _withDetail(base, playDetail(g, level), title: gameName(g)),
      why: level == 2
          ? '${gameName(g)}${best >= 99 ? '' : ' (last played ${best == 0 ? 'today' : '$best days ago'})'}: intervals that feel like play.'
          : '${gameName(g)} at an easy pace: ${levelReason(c).toLowerCase()}.',
    );
  }
  // No games set: another sport you like, or a brisk walk.
  Pick other(String key, String title, PlayDetail d, String why) => Pick(
    kind: PickKind.play,
    session: _withDetail(
      fitMinutes(sessionTemplate(key), c.maxMinutes),
      d,
      title: title,
    ),
    why: why,
  );
  if (c.likes.contains(Sport.cycling)) {
    final hard = level == 2 && _daysSince(c, (r) => r.hard) >= 2;
    return other(
      hard ? 'tempo_ride' : 'easy_ride',
      hard ? 'Tempo ride' : 'Easy ride',
      PlayDetail(
        game: null,
        format: hard
            ? '2 × 12 min steady-hard, 4 min easy between'
            : 'Steady, flat or rolling route',
        effort: hard ? 'Tempo blocks in Z3.' : 'Easy (Z2): conversational.',
        purpose: hard
            ? 'Threshold fitness with no impact on the legs.'
            : 'Aerobic base, easy on the joints.',
      ),
      'A change from running: same engine, no impact.',
    );
  }
  if (level < 2 && c.likes.contains(Sport.yoga)) {
    return other(
      'yoga',
      'Yoga',
      const PlayDetail(
        game: null,
        format: 'A flowing session, holds of 30–60 s',
        effort: 'Easy: breathe through every pose.',
        purpose: 'Mobility and recovery.',
      ),
      'Mobility work that helps recovery.',
    );
  }
  if (level == 2 && c.likes.contains(Sport.hiit)) {
    return other(
      'hiit',
      'HIIT',
      const PlayDetail(
        game: null,
        format: '8 × 1 min hard / 1 min easy',
        effort: 'Hard bursts (Z5), full easy minute between.',
        purpose: 'A short, potent fitness boost.',
      ),
      'Short and intense: the most fitness for the time.',
    );
  }
  return Pick(
    kind: PickKind.play,
    session: _withDetail(
      Session(
        key: 'easy_walk',
        title: 'Brisk walk',
        sport: Sport.walking,
        segments: [Segment(min(c.maxMinutes, level == 0 ? 25 : 40), 2)],
        strainLo: 3,
        strainHi: 6,
        intensity: Intensity.easy,
      ),
      const PlayDetail(
        game: null,
        format: 'A purposeful walk, 100+ steps a minute',
        effort: 'Brisk (Z2): warm, a little out of breath.',
        purpose: 'Brisk minutes count most for long-term health.',
      ),
      title: 'Brisk walk',
    ),
    why: 'Add the games you play in Profile → Workouts and Tempo will suggest them here.',
  );
}
