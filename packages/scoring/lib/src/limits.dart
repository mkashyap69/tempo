/// Training around an injury (U3). Not a pause: you're well, baselines keep
/// learning and the plan keeps going with what you can still do. Pure Dart.
library;

import 'coach.dart';

enum TrainingLimit {
  none,

  /// No running or jumping: rides, walks and strength instead.
  noRunning,

  /// Upper body only: upper-body strength, everything else rest.
  upperOnly,
}

String limitName(TrainingLimit l) => switch (l) {
  TrainingLimit.none => 'No limits',
  TrainingLimit.noRunning => 'No running',
  TrainingLimit.upperOnly => 'Upper body only',
};

String limitDetail(TrainingLimit l) => switch (l) {
  TrainingLimit.none => 'The plan uses everything you like.',
  TrainingLimit.noRunning =>
    'Runs and jumping become rides (if you ride) or walks; hard days keep '
        'their effort on the bike or turn into upper-body strength.',
  TrainingLimit.upperOnly =>
    'Strength days become upper body; other sessions become rest days.',
};

bool _impact(Session s) =>
    s.sport == Sport.running || s.sport == Sport.hiit || s.sport == Sport.sport;

/// [s] as [l] allows it, no longer than it was (at least 20′), keeping a
/// race on race day. Unchanged when the limit doesn't touch it.
Session limited(Session s, TrainingLimit l, {required Set<Sport> likes}) {
  if (l == TrainingLimit.none || s.isRest || s.key == 'race') return s;
  final ride = likes.contains(Sport.cycling);
  final String? key = switch (l) {
    TrainingLimit.none => null,
    TrainingLimit.noRunning when !_impact(s) => null,
    TrainingLimit.noRunning when s.key.startsWith('long_') =>
      ride ? 'long_ride' : 'easy_walk',
    TrainingLimit.noRunning when s.isHard =>
      ride ? 'tempo_ride' : 'strength_upper',
    TrainingLimit.noRunning => ride ? 'easy_ride' : 'easy_walk',
    TrainingLimit.upperOnly when s.key == 'strength_upper' => null,
    TrainingLimit.upperOnly when s.sport == Sport.strength || s.isHard =>
      'strength_upper',
    TrainingLimit.upperOnly => 'rest',
  };
  if (key == null) return s;
  final t = sessionTemplate(key);
  return t.isRest ? t : fitMinutes(t, s.minutes < 20 ? 20 : s.minutes);
}

/// Every day of [week] as [l] allows it.
List<Session> limitedWeek(
  List<Session> week,
  TrainingLimit l, {
  required Set<Sport> likes,
}) => [for (final s in week) limited(s, l, likes: likes)];
