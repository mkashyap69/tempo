/// Coach: strain targets, the weekly plan and its morning adaptation.
///
/// Branch rules (design → Flow · morning plan adaptation):
/// Go: recovery ≥ 67 and load not overreaching. Ease off: 34–66, or less
/// than 48 h since the last hard day. Rest: ≤ 33 or overreaching. In
/// calibration everything stays General and moderate.
library;

import 'dart:math';

import 'load.dart';
import 'longevity.dart';
import 'strain.dart';

enum Sport { running, cycling, walking, strength, yoga, hiit, sport }

enum Goal { fitness, fatLoss, performance, wellbeing }

enum Intensity { rest, easy, moderate, hard }

enum DayState { go, easeOff, rest, general }

/// How recent sessions felt against what was planned, from logged RPE.
enum Effort { heavy, onTrack, light, unknown }

/// The RPE a session of [i] should feel like.
int expectedRpe(Intensity i) => switch (i) {
  Intensity.rest => 1,
  Intensity.easy => 3,
  Intensity.moderate => 5,
  Intensity.hard => 7,
};

/// Intensity of an unplanned workout, from the strain it added.
Intensity intensityForStrain(double strain) => strain < 8
    ? Intensity.easy
    : strain < 14
    ? Intensity.moderate
    : Intensity.hard;

/// Mean of (RPE − expected) over the newest [n] rated sessions, newest
/// first. ≥ 1.5 points over → heavy; ≥ 1.5 under → light. Needs 2.
Effort effortTrend(List<(int, Intensity)> recent, {int n = 3}) {
  final r = recent.take(n).toList();
  if (r.length < 2) return Effort.unknown;
  final d = r.fold<int>(0, (a, e) => a + e.$1 - expectedRpe(e.$2)) / r.length;
  if (d >= 1.5) return Effort.heavy;
  if (d <= -1.5) return Effort.light;
  return Effort.onTrack;
}

final class Segment {
  const Segment(this.minutes, this.zone);
  final int minutes;

  /// 1..5
  final int zone;

  List<int> toJson() => [minutes, zone];
  static Segment fromJson(List<dynamic> j) => Segment(j[0] as int, j[1] as int);
}

/// One planned session (or a rest day).
final class Session {
  const Session({
    required this.key,
    required this.title,
    required this.sport,
    required this.segments,
    required this.strainLo,
    required this.strainHi,
    required this.intensity,
    this.note = '',
  });

  /// Template key, see [sessionTemplate].
  final String key;
  final String title;

  /// null for a rest day.
  final Sport? sport;
  final List<Segment> segments;
  final double strainLo, strainHi;
  final Intensity intensity;

  /// Short descriptor, e.g. "full body".
  final String note;

  bool get isRest => intensity == Intensity.rest;
  bool get isHard => intensity == Intensity.hard;
  int get minutes => segments.fold(0, (a, s) => a + s.minutes);
  int get zoneLo =>
      segments.isEmpty ? 1 : segments.map((s) => s.zone).reduce(min);
  int get zoneHi =>
      segments.isEmpty ? 1 : segments.map((s) => s.zone).reduce(max);
  String get zones => zoneLo == zoneHi ? 'Z$zoneLo' : 'Z$zoneLo–Z$zoneHi';

  /// "10′ Z2 · 5 × (3′ Z4 / 2′ Z1) · 8′ Z2"
  String get structure {
    final parts = <String>[];
    var i = 0;
    while (i < segments.length) {
      // Collapse a repeating (work, recover) pair.
      if (i + 3 < segments.length) {
        final a = segments[i], b = segments[i + 1];
        var reps = 1;
        while (i + reps * 2 + 1 < segments.length &&
            _same(segments[i + reps * 2], a) &&
            _same(segments[i + reps * 2 + 1], b)) {
          reps++;
        }
        if (reps > 1) {
          parts.add(
            '$reps × (${a.minutes}′ Z${a.zone} / ${b.minutes}′ Z${b.zone})',
          );
          i += reps * 2;
          continue;
        }
      }
      final s = segments[i];
      parts.add('${s.minutes}′ Z${s.zone}');
      i++;
    }
    return parts.join(' · ');
  }

  static bool _same(Segment x, Segment y) =>
      x.minutes == y.minutes && x.zone == y.zone;

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'sport': sport?.name,
    'segments': [for (final s in segments) s.toJson()],
    'lo': strainLo,
    'hi': strainHi,
    'intensity': intensity.name,
    'note': note,
  };

  static Session fromJson(Map<String, dynamic> j) => Session(
    key: j['key'] as String,
    title: j['title'] as String,
    sport: j['sport'] == null
        ? null
        : Sport.values.byName(j['sport'] as String),
    segments: [
      for (final s in j['segments'] as List) Segment.fromJson(s as List),
    ],
    strainLo: (j['lo'] as num).toDouble(),
    strainHi: (j['hi'] as num).toDouble(),
    intensity: Intensity.values.byName(j['intensity'] as String),
    note: j['note'] as String? ?? '',
  );
}

List<Segment> _reps(int n, Segment work, Segment rest) => [
  for (var i = 0; i < n; i++) ...[work, rest],
];

/// Session library. Every session the coach can suggest comes from here.
Session sessionTemplate(String key) => switch (key) {
  'rest' => const Session(
    key: 'rest',
    title: 'Rest',
    sport: null,
    segments: [],
    strainLo: 0,
    strainHi: 7,
    intensity: Intensity.rest,
    note: 'Walk if you like',
  ),
  'easy_walk' => const Session(
    key: 'easy_walk',
    title: 'Easy walk',
    sport: Sport.walking,
    segments: [Segment(25, 1)],
    strainLo: 2,
    strainHi: 5,
    intensity: Intensity.easy,
  ),
  'mobility' => const Session(
    key: 'mobility',
    title: 'Mobility flow',
    sport: Sport.yoga,
    segments: [Segment(15, 1)],
    strainLo: 1,
    strainHi: 4,
    intensity: Intensity.easy,
  ),
  'easy_run' => const Session(
    key: 'easy_run',
    title: 'Easy run',
    sport: Sport.running,
    segments: [Segment(5, 1), Segment(25, 2), Segment(5, 1)],
    strainLo: 5,
    strainHi: 8,
    intensity: Intensity.easy,
  ),
  'aerobic_run' => const Session(
    key: 'aerobic_run',
    title: 'Easy aerobic run',
    sport: Sport.running,
    segments: [Segment(5, 1), Segment(25, 2), Segment(5, 1)],
    strainLo: 5,
    strainHi: 8,
    intensity: Intensity.moderate,
  ),
  'steady_run' => const Session(
    key: 'steady_run',
    title: 'Steady Z2 run',
    sport: Sport.running,
    segments: [Segment(5, 1), Segment(30, 2), Segment(5, 1)],
    strainLo: 6,
    strainHi: 9,
    intensity: Intensity.moderate,
  ),
  'threshold_run' => Session(
    key: 'threshold_run',
    title: 'Threshold intervals',
    sport: Sport.running,
    segments: [
      const Segment(10, 2),
      ..._reps(5, const Segment(3, 4), const Segment(2, 1)),
      const Segment(8, 2),
    ],
    strainLo: 12,
    strainHi: 15,
    intensity: Intensity.hard,
  ),
  'vo2_run' => Session(
    key: 'vo2_run',
    title: 'VO₂ intervals',
    sport: Sport.running,
    segments: [
      const Segment(10, 2),
      ..._reps(5, const Segment(3, 5), const Segment(3, 1)),
      const Segment(8, 2),
    ],
    strainLo: 14,
    strainHi: 17,
    intensity: Intensity.hard,
  ),
  'long_run' => const Session(
    key: 'long_run',
    title: 'Long run',
    sport: Sport.running,
    segments: [Segment(5, 1), Segment(50, 2), Segment(5, 1)],
    strainLo: 8,
    strainHi: 11,
    intensity: Intensity.moderate,
  ),
  'easy_ride' => const Session(
    key: 'easy_ride',
    title: 'Easy ride',
    sport: Sport.cycling,
    segments: [Segment(5, 1), Segment(35, 2), Segment(5, 1)],
    strainLo: 6,
    strainHi: 9,
    intensity: Intensity.easy,
  ),
  'long_ride' => const Session(
    key: 'long_ride',
    title: 'Long ride',
    sport: Sport.cycling,
    segments: [Segment(5, 1), Segment(65, 2), Segment(5, 1)],
    strainLo: 9,
    strainHi: 12,
    intensity: Intensity.moderate,
  ),
  'tempo_ride' => Session(
    key: 'tempo_ride',
    title: 'Tempo ride',
    sport: Sport.cycling,
    segments: [
      const Segment(10, 2),
      ..._reps(2, const Segment(12, 3), const Segment(4, 1)),
      const Segment(8, 2),
    ],
    strainLo: 11,
    strainHi: 14,
    intensity: Intensity.hard,
  ),
  'strength_full' => const Session(
    key: 'strength_full',
    title: 'Strength',
    sport: Sport.strength,
    segments: [Segment(45, 2)],
    strainLo: 9,
    strainHi: 12,
    intensity: Intensity.moderate,
    note: 'full body',
  ),
  'strength_lower' => const Session(
    key: 'strength_lower',
    title: 'Strength',
    sport: Sport.strength,
    segments: [Segment(45, 2)],
    strainLo: 9,
    strainHi: 12,
    intensity: Intensity.moderate,
    note: 'lower body',
  ),
  'yoga' => const Session(
    key: 'yoga',
    title: 'Yoga',
    sport: Sport.yoga,
    segments: [Segment(40, 1)],
    strainLo: 3,
    strainHi: 6,
    intensity: Intensity.easy,
  ),
  'hiit' => Session(
    key: 'hiit',
    title: 'HIIT',
    sport: Sport.hiit,
    segments: [
      const Segment(8, 2),
      ..._reps(8, const Segment(1, 5), const Segment(1, 1)),
      const Segment(6, 2),
    ],
    strainLo: 11,
    strainHi: 14,
    intensity: Intensity.hard,
  ),
  'sport' => const Session(
    key: 'sport',
    title: 'Sport session',
    sport: Sport.sport,
    segments: [Segment(10, 2), Segment(40, 3), Segment(10, 1)],
    strainLo: 12,
    strainHi: 15,
    intensity: Intensity.moderate,
  ),
  _ => throw ArgumentError('unknown session $key'),
};

/// Hard session for a sport, or null if that sport has none.
String? hardKeyFor(Sport s) => switch (s) {
  Sport.running => 'threshold_run',
  Sport.cycling => 'tempo_ride',
  Sport.hiit => 'hiit',
  _ => null,
};

/// The Z2 version used when easing off a hard day.
String easierKeyFor(Session s) => switch (s.sport) {
  Sport.running =>
    s.key == 'threshold_run' || s.key == 'vo2_run' ? 'steady_run' : 'easy_run',
  Sport.cycling => 'easy_ride',
  Sport.hiit => 'easy_walk',
  Sport.strength => 'mobility',
  Sport.sport => 'easy_walk',
  _ => 'easy_walk',
};

/// A harder alternative for the same sport, or null.
String? harderKeyFor(Session s) => switch (s.key) {
  'threshold_run' ||
  'steady_run' ||
  'easy_run' ||
  'aerobic_run' ||
  'long_run' => 'vo2_run',
  'easy_ride' || 'long_ride' => 'tempo_ride',
  _ => s.sport == null ? null : hardKeyFor(s.sport!),
};

String _easyKey(Sport s) => switch (s) {
  Sport.running => 'easy_run',
  Sport.cycling => 'easy_ride',
  Sport.walking => 'easy_walk',
  Sport.strength => 'strength_full',
  Sport.yoga => 'yoga',
  Sport.hiit => 'easy_walk',
  Sport.sport => 'sport',
};

String? _longKey(Set<Sport> likes) => likes.contains(Sport.cycling)
    ? 'long_ride'
    : likes.contains(Sport.running)
    ? 'long_run'
    : null;

/// Fits [s] into [maxMinutes] by trimming the longest block (never below 10′).
Session fitMinutes(Session s, int maxMinutes) {
  if (s.minutes <= maxMinutes || s.segments.isEmpty) return s;
  final segs = [...s.segments];
  var over = s.minutes - maxMinutes;
  while (over > 0) {
    var iMax = 0;
    for (var i = 1; i < segs.length; i++) {
      if (segs[i].minutes > segs[iMax].minutes) iMax = i;
    }
    final cut = min(over, segs[iMax].minutes - 10);
    if (cut <= 0) break;
    segs[iMax] = Segment(segs[iMax].minutes - cut, segs[iMax].zone);
    over -= cut;
  }
  return Session(
    key: s.key,
    title: s.title,
    sport: s.sport,
    segments: segs,
    strainLo: s.strainLo,
    strainHi: s.strainHi,
    intensity: s.intensity,
    note: s.note,
  );
}

final class CoachPrefs {
  const CoachPrefs({
    required this.goal,
    required this.likes,
    required this.days,
    required this.maxMinutes,
  });
  final Goal goal;
  final Set<Sport> likes;

  /// Available weekdays, 1 = Monday … 7 = Sunday.
  final Set<int> days;
  final int maxMinutes;

  int get hardPerWeek => switch (goal) {
    Goal.fitness || Goal.performance => 2,
    Goal.fatLoss || Goal.wellbeing => 1,
  };
}

/// Seven sessions, Monday first. Unavailable days are rest; with every day
/// available one still becomes rest. At most [CoachPrefs.hardPerWeek] hard
/// sessions, never on consecutive days. [general] (calibration) has none.
///
/// [focus] (a Tempo Age lever the user is working on) tilts the week:
/// active minutes turns up to two short easy sessions into longer Zone 2
/// ones; strength makes sure there are two strength sessions.
List<Session> weekPlan(CoachPrefs p, {bool general = false, Lever? focus}) {
  final likes = p.likes.isEmpty ? {Sport.walking} : p.likes;
  final avail = [
    for (var d = 1; d <= 7; d++)
      if (p.days.contains(d)) d,
  ];
  if (avail.length == 7) avail.remove(3); // Wednesday off
  final plan = List<String>.filled(7, 'rest');

  final hardSports = [
    for (final s in likes)
      if (hardKeyFor(s) != null) s,
  ];
  final hard = <int>[];
  if (!general && hardSports.isNotEmpty) {
    // Latest days first so the week ends on quality; ≥ 2 days apart.
    for (final d in avail.reversed) {
      if (hard.length >= p.hardPerWeek) break;
      if (hard.every((h) => (h - d).abs() >= 2)) hard.add(d);
    }
    for (final (i, d) in hard.indexed) {
      plan[d - 1] = hardKeyFor(hardSports[i % hardSports.length])!;
    }
  }

  final long = _longKey(likes);
  final rest = [
    for (final d in avail)
      if (!hard.contains(d)) d,
  ];
  if (long != null && rest.isNotEmpty && p.goal != Goal.wellbeing) {
    final weekend = rest.where((d) => d >= 6).toList();
    final d = weekend.isNotEmpty ? weekend.first : rest.last;
    plan[d - 1] = long;
    rest.remove(d);
  }
  final easy = [for (final s in likes) _easyKey(s)].toSet().toList();
  var strength = 0;
  for (final (i, d) in rest.indexed) {
    var k = easy[i % easy.length];
    if (k == 'strength_full') {
      if (strength >= 2)
        k = easy.firstWhere((e) => e != k, orElse: () => 'easy_walk');
      if (k.startsWith('strength')) {
        k = strength.isEven ? 'strength_full' : 'strength_lower';
        strength++;
      }
    }
    if (general && k == 'easy_run') k = 'aerobic_run';
    plan[d - 1] = k;
  }
  _applyFocus(plan, focus, likes, hard: hard);
  return [for (final k in plan) fitMinutes(sessionTemplate(k), p.maxMinutes)];
}

void _applyFocus(
  List<String> plan,
  Lever? focus,
  Set<Sport> likes, {
  required List<int> hard,
}) {
  bool free(int i) =>
      plan[i] != 'rest' &&
      !hard.contains(i + 1) &&
      !plan[i].startsWith('long_') &&
      !plan[i].startsWith('strength');
  if (focus == Lever.activeMinutes) {
    final z2 = likes.contains(Sport.running)
        ? 'aerobic_run'
        : likes.contains(Sport.cycling)
        ? 'easy_ride'
        : 'easy_walk';
    const longer = {'easy_run': 'long_run', 'easy_ride': 'long_ride'};
    var changed = 0;
    for (var i = 0; i < 7 && changed < 2; i++) {
      if (!free(i)) continue;
      final k = plan[i];
      if (const {'easy_walk', 'mobility', 'yoga'}.contains(k) && k != z2) {
        plan[i] = z2;
        changed++;
      } else if (longer.containsKey(k) && changed == 0) {
        plan[i] = longer[k]!;
        changed++;
      }
    }
  } else if (focus == Lever.strength) {
    var n = plan.where((k) => k.startsWith('strength')).length;
    for (var i = 0; i < 7 && n < 2; i++) {
      if (!free(i)) continue;
      // Not the day after another strength day.
      if (i > 0 && plan[i - 1].startsWith('strength')) continue;
      plan[i] = n.isEven ? 'strength_full' : 'strength_lower';
      n++;
    }
  }
}

/// Today's strain range. [cap] true = a ceiling on a rest day, not a target.
final class StrainTarget {
  const StrainTarget(
    this.lo,
    this.hi, {
    this.cap = false,
    this.general = false,
  });
  final double lo, hi;
  final bool cap;
  final bool general;

  bool contains(double s) => s >= lo && s <= hi;
}

StrainTarget strainTarget({
  double? recovery,
  bool calibrating = false,
  LoadStatus load = LoadStatus.learning,
}) {
  if (recovery == null && !calibrating)
    return const StrainTarget(8, 12, general: true);
  if (calibrating || recovery == null)
    return const StrainTarget(10, 14, general: true);
  if (recovery <= 33 || load == LoadStatus.overreaching) {
    return const StrainTarget(0, 8, cap: true);
  }
  if (recovery < 50) return const StrainTarget(8, 12);
  if (recovery < 67) return const StrainTarget(10, 13);
  if (recovery < 80) return const StrainTarget(13, 16);
  if (recovery < 90) return const StrainTarget(14, 17);
  return const StrainTarget(15, 18);
}

DayState dayState({
  double? recovery,
  bool calibrating = false,
  LoadStatus load = LoadStatus.learning,
  int? daysSinceHard,
}) {
  if (calibrating || recovery == null) return DayState.general;
  if (recovery <= 33 || load == LoadStatus.overreaching) return DayState.rest;
  if (recovery < 67 || (daysSinceHard != null && daysSinceHard < 2)) {
    return DayState.easeOff;
  }
  return DayState.go;
}

final class PlanChange {
  const PlanChange(this.dayIndex, this.from, this.to, this.reason, this.state);
  final int dayIndex;
  final Session from, to;
  final String reason;
  final DayState state;
}

final class Adaptation {
  const Adaptation(this.week, this.changes, this.carried);
  final List<Session> week;
  final List<PlanChange> changes;

  /// Hard session waiting for a good morning, or null.
  final Session? carried;
}

/// Adjusts [week] for today ([today], 0 = Monday) from [state].
/// [reason] is the one-line why ("Recovery 32% after 5 h 40 m sleep").
Adaptation adaptWeek(
  List<Session> week,
  int today,
  DayState state, {
  required String reason,
  Session? carried,
  Set<int> available = const {1, 2, 3, 4, 5, 6, 7},
  Effort effort = Effort.unknown,
}) {
  final w = [...week];
  final changes = <PlanChange>[];
  final now = w[today];
  Session? pending = carried;

  bool canTakeHard(int i) =>
      !w[i].isHard &&
      !w[i].isRest &&
      (i == 0 || !w[i - 1].isHard) &&
      (i == 6 || !w[i + 1].isHard) &&
      w.where((s) => s.isHard).length < 2;

  switch (state) {
    case DayState.go:
      if (pending != null && !now.isRest && canTakeHard(today)) {
        w[today] = pending;
        changes.add(
          PlanChange(
            today,
            now,
            pending,
            '$reason — the carried-over session fits.',
            state,
          ),
        );
        pending = null;
      } else if (effort == Effort.heavy && now.isHard && pending == null) {
        final to = sessionTemplate(easierKeyFor(now));
        w[today] = to;
        changes.add(
          PlanChange(
            today,
            now,
            to,
            'Your last sessions felt harder than planned. '
            '${now.title} carried forward.',
            state,
          ),
        );
        pending = now;
      } else if (effort == Effort.light &&
          pending == null &&
          now.intensity == Intensity.easy &&
          canTakeHard(today)) {
        final k = harderKeyFor(now);
        if (k != null) {
          final to = sessionTemplate(k);
          w[today] = to;
          changes.add(
            PlanChange(
              today,
              now,
              to,
              '$reason and your last sessions felt easy — today steps up.',
              state,
            ),
          );
        }
      }
    case DayState.easeOff:
      if (now.isHard) {
        final to = sessionTemplate(easierKeyFor(now));
        w[today] = to;
        changes.add(
          PlanChange(
            today,
            now,
            to,
            '$reason. ${now.title} carried forward.',
            state,
          ),
        );
        pending = now;
      }
    case DayState.rest:
      if (!now.isRest) {
        final target = sessionTemplate('rest');
        w[today] = target;
        changes.add(
          PlanChange(
            today,
            now,
            target,
            '$reason.${now.isHard ? ' ${now.title} carried forward.' : ''}',
            state,
          ),
        );
        if (now.isHard) pending = now;
      }
    case DayState.general:
      if (now.isHard) {
        final to = sessionTemplate(easierKeyFor(now));
        w[today] = to;
        changes.add(
          PlanChange(
            today,
            now,
            to,
            'Still learning your baseline — sessions stay moderate.',
            state,
          ),
        );
      }
  }
  // Look three days ahead (today … today+2).
  if (state == DayState.rest && today < 6 && w[today + 1].isHard) {
    // Tomorrow starts easy after a rest day.
    final from = w[today + 1], to = sessionTemplate(easierKeyFor(from));
    w[today + 1] = to;
    changes.add(
      PlanChange(
        today + 1,
        from,
        to,
        'After a rest day, tomorrow starts easy. ${from.title} moves later.',
        state,
      ),
    );
    pending ??= from;
  }
  for (var i = today; i < 6 && i <= today + 2; i++) {
    if (w[i].isHard && w[i + 1].isHard) {
      final from = w[i + 1], to = sessionTemplate(easierKeyFor(from));
      w[i + 1] = to;
      changes.add(
        PlanChange(
          i + 1,
          from,
          to,
          'No two hard days in a row — this one eases.',
          state,
        ),
      );
    }
  }
  // Try to place a carried session later this week.
  if (pending != null) {
    // At least 48 h away; easy days first so long and strength days stay.
    for (final easyOnly in [true, false]) {
      for (var i = today + 2; i < 7 && pending != null; i++) {
        if (available.contains(i + 1) &&
            canTakeHard(i) &&
            (!easyOnly || w[i].intensity == Intensity.easy)) {
          final from = w[i];
          w[i] = pending;
          changes.add(
            PlanChange(
              i,
              from,
              pending,
              'Carried forward, if recovery is back above 50%.',
              state,
            ),
          );
          pending = null;
        }
      }
    }
  }
  return Adaptation(w, changes, pending);
}

/// TRIMP a planned session should add, at the middle of each zone.
double sessionTrimp(Session s, {required int hrMax, required double hrRest}) {
  const mid = [0.55, 0.65, 0.75, 0.85, 0.93];
  return s.segments.fold(
    0.0,
    (a, seg) =>
        a +
        seg.minutes *
            minuteTrimp(
              (mid[seg.zone - 1] * hrMax).round(),
              hrRest: hrRest,
              hrMax: hrMax.toDouble(),
            ),
  );
}

/// Day strain added by [s] on top of [dayTrimp] already accumulated.
double sessionStrain(
  Session s, {
  required int hrMax,
  required double hrRest,
  double dayTrimp = 0,
  StrainParams p = const StrainParams(),
}) =>
    strainFromTrimp(
      dayTrimp + sessionTrimp(s, hrMax: hrMax, hrRest: hrRest),
      p,
    ) -
    strainFromTrimp(dayTrimp, p);
