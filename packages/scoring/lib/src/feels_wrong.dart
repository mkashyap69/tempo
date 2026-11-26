/// v3 session page: "If it feels wrong", the mid-session calls a coach
/// would give before you start, so a bad day changes the session instead
/// of ending it (docs/research/v3 UI.md).
library;

import 'coach.dart';

/// One sign and what to do about it.
typedef FeelsWrong = ({String sign, String action});

/// The signs worth planning for in [s], most likely first. Rest days have
/// none. Every session ends with pain, which always means stop.
List<FeelsWrong> feelsWrong(Session s) {
  if (s.isRest) return const [];
  final out = <FeelsWrong>[];
  final work = [
    if (s.segments.length >= 3)
      for (final g in s.segments.sublist(1, s.segments.length - 1))
        if (g.zone >= 3) g,
  ];
  final blocks = work.length;
  final top = s.segments.isEmpty
      ? 1
      : s.segments.map((g) => g.zone).reduce((a, b) => a > b ? a : b);

  if (s.sport == Sport.strength) {
    out.add((
      sign: 'Form breaks down before the last reps',
      action: 'drop the weight about 10 % and finish the sets',
    ));
    out.add((
      sign: 'Everything feels heavy in the warm-up sets',
      action: 'keep the weight, do one set fewer of each',
    ));
  } else if (blocks >= 2) {
    out.add((
      sign: 'Heavy legs by the end of the warm-up',
      action:
          'do ${blocks - 1} ${blocks - 1 == 1 ? 'block' : 'blocks'}, not $blocks',
    ));
    out.add((
      sign: 'Heart rate above zone $top at the target effort',
      action: 'go by heart rate, not pace or power',
    ));
  } else if (top >= 3) {
    out.add((
      sign: 'Heart rate climbs above zone $top early',
      action: 'ease off until it settles, then hold it there',
    ));
  } else {
    out.add((
      sign: 'You can’t talk in full sentences',
      action: 'slow down; easy should feel easy',
    ));
  }
  if (s.isHard) {
    out.add((
      sign: 'Dizzy, sick or unusually breathless',
      action: 'stop and walk it off; make it an easy day',
    ));
  }
  out.add((
    sign: 'Sharp or growing pain',
    action: 'stop, and log it under Injury so the plan works around it',
  ));
  return out;
}
