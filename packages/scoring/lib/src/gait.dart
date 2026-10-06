import 'dart:math' as math;

import 'types.dart';

/// Walking stride when the band hasn't counted enough steps to learn it:
/// metres per step = this × height. TODO(verify) against a measured walk.
const walkStridePerHeight = 0.415;

/// Running stride per height. The band's day ratio is mostly walking, so
/// runs use this instead. TODO(verify) against a measured run.
const runStridePerHeight = 0.65;

/// Cadence (steps per minute) from which a session counts as running.
const runningCadence = 140;

/// Minutes under this cadence count as stopped, not moving.
const movingCadence = 60;

/// The band's own distance ÷ steps is trusted once it has counted this many
/// steps in the day (the sync stores it then).
const minStepsForBandStride = 1000;

/// Metres per step. [bandStride] is the band's distance ÷ steps for the
/// day; its stride already follows height and pace (0.77 m on 6 Oct,
/// 3356 m for 4379 steps). Runs, or no plausible band stride, use height
/// ([heightCm], 170 if unknown).
double strideMetres({
  required bool running,
  double? bandStride,
  double? heightCm,
}) {
  final h = (heightCm ?? 170) / 100;
  if (running) return runStridePerHeight * h;
  if (bandStride != null && bandStride >= .4 && bandStride <= 1.2) {
    return bandStride;
  }
  return walkStridePerHeight * h;
}

/// Steps, cadence and step-based distance and pace for a walk or run.
/// Distance and pace are estimates: the band has no GPS.
final class Gait {
  const Gait({
    required this.steps,
    required this.minutes,
    required this.movingMinutes,
    required this.cadence,
    required this.peakCadence,
    required this.strideM,
    required this.perMinute,
    required this.splits,
  });

  final int steps;

  /// Session length and the minutes at or over [movingCadence].
  final int minutes, movingMinutes;

  /// Mean steps per minute over moving minutes, and the best minute.
  final double cadence;
  final int peakCadence;
  final double strideM;

  /// Steps in each minute of the session, in order.
  final List<int> perMinute;

  /// Time for each full kilometre, in order.
  final List<Duration> splits;

  double get distanceM => steps * strideM;
  bool get running => cadence >= runningCadence;

  /// Over the whole session, stops included. Null under 100 m.
  Duration? get pacePerKm => distanceM < 100
      ? null
      : Duration(seconds: (minutes * 60 / (distanceM / 1000)).round());

  /// Over moving minutes only.
  Duration? get movingPacePerKm {
    final moving = [
      for (final s in perMinute)
        if (s >= movingCadence) s,
    ].fold<int>(0, (a, b) => a + b);
    final d = moving * strideM;
    return d < 100
        ? null
        : Duration(seconds: (movingMinutes * 60 / (d / 1000)).round());
  }
}

/// [Gait] for [minutes] (one per minute, in order), or null with under
/// 100 steps.
Gait? gaitOf(List<Minute> minutes, {required double strideM}) {
  final per = [for (final m in minutes) m.steps];
  final steps = per.fold<int>(0, (a, b) => a + b);
  if (steps < 100) return null;
  final moving = [
    for (final s in per)
      if (s >= movingCadence) s,
  ];
  // Kilometre splits: interpolate within the minute each km is passed.
  final splits = <Duration>[];
  var dist = 0.0, lastKmAt = 0.0;
  for (var i = 0; i < per.length; i++) {
    final d = per[i] * strideM;
    while (d > 0 && dist + d >= (splits.length + 1) * 1000) {
      final need = (splits.length + 1) * 1000 - dist;
      final at = (i + need / d) * 60;
      splits.add(Duration(seconds: (at - lastKmAt).round()));
      lastKmAt = at;
    }
    dist += d;
  }
  return Gait(
    steps: steps,
    minutes: per.length,
    movingMinutes: moving.length,
    cadence: moving.isEmpty
        ? 0
        : moving.reduce((a, b) => a + b) / moving.length,
    peakCadence: per.reduce(math.max),
    strideM: strideM,
    perMinute: per,
    splits: splits,
  );
}
