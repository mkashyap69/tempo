/// Auto-detects activities from per-minute samples. Every result is a guess
/// the user can confirm or change; the sport guess uses cadence and HR only.
library;

import 'dart:math';

import 'coach.dart' show Sport;
import 'types.dart';

final class DetectedActivity {
  const DetectedActivity({
    required this.start,
    required this.end,
    required this.sport,
    required this.avgHr,
    required this.maxHr,
    required this.stepsPerMin,
  });
  final DateTime start, end;

  /// null = unknown kind ("Workout").
  final Sport? sport;
  final int? avgHr, maxHr;
  final double stepsPerMin;
  Duration get duration => end.difference(start);
}

final class ActivityParams {
  const ActivityParams({
    this.hrPct = 0.6,
    this.minSteps = 90,
    this.minMinutes = 10,
    this.maxGap = 2,
  });

  /// A minute counts as active at ≥ this share of max HR (Z2) …
  final double hrPct;

  /// … or at least this many steps.
  final int minSteps;
  final int minMinutes;

  /// Inactive minutes allowed inside one activity.
  final int maxGap;
}

/// [minutes] sorted, one per minute. Sleep minutes are never active.
List<DetectedActivity> detectActivities(
  List<Minute> minutes, {
  required int hrMax,
  ActivityParams p = const ActivityParams(),
}) {
  bool active(Minute m) =>
      !m.stage.asleep &&
      ((m.hr != null && m.hr! >= p.hrPct * hrMax) ||
          m.steps >= p.minSteps ||
          m.bandWalking);

  final out = <DetectedActivity>[];
  int? start, last;
  void close() {
    if (start != null && last != null) {
      final run = minutes.sublist(start!, last! + 1);
      final mins = run.last.ts.difference(run.first.ts).inMinutes + 1;
      if (mins >= p.minMinutes) out.add(_describe(run, hrMax));
    }
    start = last = null;
  }

  for (var i = 0; i < minutes.length; i++) {
    final m = minutes[i];
    if (last != null &&
        m.ts.difference(minutes[last!].ts).inMinutes > p.maxGap + 1) {
      close();
    }
    if (active(m)) {
      start ??= i;
      last = i;
    }
  }
  close();
  return out;
}

DetectedActivity _describe(List<Minute> run, int hrMax) {
  final hrs = run.map((m) => m.hr).whereType<int>().toList();
  final avgHr = hrs.isEmpty
      ? null
      : (hrs.reduce((a, b) => a + b) / hrs.length).round();
  final maxHr = hrs.isEmpty ? null : hrs.reduce(max);
  final spm = run.fold<int>(0, (a, m) => a + m.steps) / run.length;
  final hrShare = avgHr == null ? 0 : avgHr / hrMax;
  // The band marks walking minutes itself; half the run marked is enough,
  // even when cadence is uneven (stops at crossings).
  final bandWalk = run.where((m) => m.bandWalking).length >= run.length / 2;
  final Sport? sport = spm >= 130 && hrShare >= 0.7
      ? Sport.running
      : spm >= 80 || bandWalk
      ? Sport.walking
      : spm < 30 && hrShare >= 0.6
      ? Sport.cycling
      : null;
  return DetectedActivity(
    start: run.first.ts,
    end: run.last.ts.add(const Duration(minutes: 1)),
    sport: sport,
    avgHr: avgHr,
    maxHr: maxHr,
    stepsPerMin: spm,
  );
}
