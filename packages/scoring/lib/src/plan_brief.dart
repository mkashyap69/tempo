import 'dart:math';

import 'block.dart';
import 'coach.dart';
import 'coach_day.dart' show isKeySession;

// ---- Plan: what to do, how, and why, in plain words -------------------------

/// How to do [s], in one line: an effort you can feel (the talk test)
/// rather than a zone number.
String effortCue(Session s) {
  if (s.isRest) return 'Rest. A walk is fine.';
  if (s.key == 'race') {
    return 'Start a little slower than goal pace, then settle in.';
  }
  if (s.sport == Sport.strength && s.key != 'strength_core') {
    return 'Controlled reps. End each set with 1–2 reps still in the tank.';
  }
  if (s.sport == Sport.yoga ||
      s.key == 'mobility' ||
      s.key == 'strength_core') {
    return 'Gentle. Move within a comfortable range and breathe slowly.';
  }
  if (s.key == 'strides_run') {
    return 'Easy, then short, fast but relaxed strides at the end.';
  }
  final top = s.segments.isEmpty ? 2 : s.zoneHi;
  if (s.isHard) {
    if (top >= 5) {
      return 'Work pieces hard: a word or two at most. Go easy between them.';
    }
    if (top == 4) {
      return 'Work pieces comfortably hard: a few words at a time. Easy '
          'between them.';
    }
    return 'Steady and strong: short phrases only, but in control.';
  }
  if (top >= 3) return 'Steady: you can talk, in shorter sentences.';
  return 'Slow enough to talk in full sentences. If you can’t, slow down '
      'or walk for a minute.';
}

/// Why [s] is in the plan, in one line.
String sessionPurpose(Session s) {
  if (s.isRest) return 'Rest is when the training sinks in.';
  if (s.key == 'race') return 'Race day. Everything has built to this.';
  if (s.key.startsWith('long_')) {
    return 'Long easy sessions build the endurance to go the distance.';
  }
  if (s.key == 'vo2_run' || s.key == 'hiit') {
    return 'Short, hard efforts raise your top-end fitness.';
  }
  if (s.isHard) {
    return 'Harder pieces raise the pace you can hold for longer.';
  }
  if (s.sport == Sport.strength && s.key != 'strength_core') {
    return 'Strength makes you more resilient and helps every other session.';
  }
  if (s.sport == Sport.yoga ||
      s.key == 'mobility' ||
      s.key == 'strength_core') {
    return 'Keeps you moving well and helps you recover.';
  }
  if (s.key == 'recovery_run' || s.key == 'easy_walk') {
    return 'Light movement that helps you recover.';
  }
  if (s.key == 'sport') return 'Play counts. It keeps training varied.';
  return 'Easy time builds your aerobic base without tiring you for the '
      'key sessions.';
}

/// The effort tag for a session card.
String effortTag(Session s) => switch (s.intensity) {
  Intensity.rest => 'Rest',
  Intensity.easy => 'Easy',
  Intensity.moderate => 'Moderate',
  Intensity.hard => 'Hard',
};

// ---- moving a session within the week -----------------------------------

bool _heavy(Session s) =>
    s.isHard || s.key.startsWith('long_') || s.key == 'race';

/// [week] with days [a] and [b] swapped.
List<Session> swapDays(List<Session> week, int a, int b) {
  final w = [...week];
  final t = w[a];
  w[a] = w[b];
  w[b] = t;
  return w;
}

/// Days (0 = Monday) the session on [from] can move to this week. It swaps
/// with a rest day or an easy session from [today] on, never onto or off a
/// race, and never leaves two heavy days (hard, long or race) back to
/// back. [available] uses 1 = Monday, like the profile.
List<int> moveTargets(
  List<Session> week,
  int from, {
  required int today,
  Set<int> available = const {1, 2, 3, 4, 5, 6, 7},
}) {
  final s = week[from];
  if (from < today || s.isRest || s.key == 'race') return const [];
  final out = <int>[];
  for (var j = max(today, 0); j < week.length; j++) {
    if (j == from) continue;
    final o = week[j];
    if (o.key == 'race' || _heavy(o) || isKeySession(o)) continue;
    // A session only lands on a day you train; a rest day can go anywhere.
    if (!available.contains(j + 1)) continue;
    final w = swapDays(week, from, j);
    var ok = true;
    for (var i = 0; i + 1 < w.length; i++) {
      if (_heavy(w[i]) && _heavy(w[i + 1]) && (i == j || i + 1 == j)) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(j);
  }
  return out;
}

// ---- the week's rule, in plain words -------------------------------------

String _n(int n) => n == 1 ? '1 more session' : '$n more sessions';

/// What the rest of this week means for next week, in one line. [phase] is
/// null without a goal; [left] counts sessions still to come.
String weekRuleLine({
  required Phase? phase,
  required WeekForecast? forecast,
  required int left,
}) {
  final rest = left == 0
      ? 'Nothing else planned this week.'
      : left == 1
      ? '1 session left this week.'
      : '$left sessions left this week.';
  if (phase == null || forecast == null) return rest;
  switch (phase) {
    case Phase.deload:
      return '$rest A lighter week: get them in easily.';
    case Phase.peak:
      return '$rest Peak week: the plan stays at its biggest.';
    case Phase.taper:
      return '$rest Tapering: don’t add extra.';
    case Phase.race:
      return 'Race week. Rest the day before the race.';
    case Phase.base || Phase.build:
      break;
  }
  final f = forecast;
  if (f.bodySaysBack) {
    return 'Recovery has been low, so next week eases off a little whatever '
        'you do. That’s the plan protecting you.';
  }
  if (f.now == WeekCall.stepUp) {
    return 'Enough done for next week to grow about 5%. Anything more is a '
        'bonus.';
  }
  final up = f.toStepUp;
  if (f.now == WeekCall.stepBack) {
    final hold = f.toHold;
    if (hold == null) {
      return 'Not enough of the week is left to hold, so next week eases off '
          'a little.';
    }
    return 'Do ${_n(hold)} and next week stays the same size'
        '${up != null && up != hold ? '; ${_n(up)} and it grows' : ''}.';
  }
  if (up != null) return 'Do ${_n(up)} and next week grows about 5%.';
  return 'Next week stays the same size.';
}
