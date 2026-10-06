import 'package:scoring/scoring.dart';

import 'record.dart';

/// A workout another app wrote to Health (Apple Watch Workout, Strava,
/// Fitbit, Samsung Health, …).
final class HealthWorkout {
  const HealthWorkout({
    required this.start,
    required this.end,
    required this.type,
    required this.sourceApp,
  });
  final DateTime start, end;

  /// The `health` plugin's activity type name, e.g. `RUNNING`.
  final String type;
  final String sourceApp;

  Sport? get sport => sportForHealthType(type);
  String get title => healthWorkoutTitle(type);
}

/// Workouts in [records], oldest first. Tempo's own exports, zero-length
/// and longer-than-a-day ones are left out, and two apps logging the same
/// session (start within 2 min, most of it overlapping) count once.
List<HealthWorkout> healthWorkouts(Iterable<HealthRecord> records) {
  final all = [
    for (final r in records)
      if (r.kind == HealthKind.workout &&
          !r.fromTempo &&
          r.end.isAfter(r.start) &&
          r.end.difference(r.start) <= const Duration(hours: 24))
        HealthWorkout(
          start: r.start,
          end: r.end,
          type: r.extra ?? 'OTHER',
          sourceApp: r.sourceApp,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final out = <HealthWorkout>[];
  for (final w in all) {
    final dup = out.any((o) {
      final overlap = (w.end.isBefore(o.end) ? w.end : o.end).difference(
        w.start.isAfter(o.start) ? w.start : o.start,
      );
      final shorter = w.end.difference(w.start) < o.end.difference(o.start)
          ? w.end.difference(w.start)
          : o.end.difference(o.start);
      return w.start.difference(o.start).abs() <= const Duration(minutes: 2) &&
          overlap.inSeconds >= shorter.inSeconds * .5;
    });
    if (!dup) out.add(w);
  }
  return out;
}

Sport? sportForHealthType(String type) => switch (type) {
  'RUNNING' ||
  'RUNNING_TREADMILL' ||
  'TRACK_AND_FIELD' ||
  'WHEELCHAIR_RUN_PACE' => Sport.running,
  'BIKING' || 'BIKING_STATIONARY' || 'HAND_CYCLING' => Sport.cycling,
  'WALKING' ||
  'WALKING_TREADMILL' ||
  'HIKING' ||
  'WHEELCHAIR_WALK_PACE' ||
  'SNOWSHOEING' => Sport.walking,
  'TRADITIONAL_STRENGTH_TRAINING' ||
  'FUNCTIONAL_STRENGTH_TRAINING' ||
  'STRENGTH_TRAINING' ||
  'WEIGHTLIFTING' ||
  'CORE_TRAINING' ||
  'CALISTHENICS' => Sport.strength,
  'HIGH_INTENSITY_INTERVAL_TRAINING' ||
  'CROSS_TRAINING' ||
  'MIXED_CARDIO' ||
  'JUMP_ROPE' ||
  'BOXING' ||
  'KICKBOXING' => Sport.hiit,
  'YOGA' ||
  'PILATES' ||
  'BARRE' ||
  'FLEXIBILITY' ||
  'MIND_AND_BODY' ||
  'TAI_CHI' => Sport.yoga,
  'AMERICAN_FOOTBALL' ||
  'AUSTRALIAN_FOOTBALL' ||
  'BADMINTON' ||
  'BASEBALL' ||
  'BASKETBALL' ||
  'CRICKET' ||
  'HANDBALL' ||
  'HOCKEY' ||
  'LACROSSE' ||
  'PICKLEBALL' ||
  'RACQUETBALL' ||
  'RUGBY' ||
  'SOCCER' ||
  'SOFTBALL' ||
  'SQUASH' ||
  'TABLE_TENNIS' ||
  'TENNIS' ||
  'VOLLEYBALL' ||
  'WATER_POLO' ||
  'MARTIAL_ARTS' ||
  'WRESTLING' ||
  'FENCING' => Sport.sport,
  _ => null,
};

/// "RUNNING_TREADMILL" → "Running treadmill".
String healthWorkoutTitle(String type) {
  if (type.isEmpty || type == 'OTHER') return 'Workout';
  final s = type.toLowerCase().replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}
