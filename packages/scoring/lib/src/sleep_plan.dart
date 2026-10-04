/// Tonight's bedtime, sleep consistency and wake-ups within a night.
library;

import 'types.dart';

/// Minutes allowed to fall asleep when planning a bedtime.
const fallAsleepMinutes = 10;

/// Bedtime as minutes after midnight (0–1439) to sleep [needHours] and wake
/// at [wakeMinute].
int bedtimeMinute(
  double needHours,
  int wakeMinute, {
  int latency = fallAsleepMinutes,
}) => ((wakeMinute - (needHours * 60).round() - latency) % 1440 + 1440) % 1440;

/// Median of clock times (minutes after midnight), wrapping around midnight
/// so 23:50 and 00:10 average near midnight. Evening times are shifted.
int medianClock(List<int> minutes) {
  if (minutes.isEmpty) return 0;
  final shifted = [for (final m in minutes) m < 720 ? m + 1440 : m]..sort();
  return shifted[shifted.length ~/ 2] % 1440;
}

/// Share of [bedtimes] within ±[tolerance] minutes of their median.
double consistency(List<int> bedtimes, {int tolerance = 25}) {
  if (bedtimes.isEmpty) return 0;
  final med = medianClock(bedtimes);
  int dist(int a) {
    final d = (a - med).abs() % 1440;
    return d > 720 ? 1440 - d : d;
  }

  return bedtimes.where((b) => dist(b) <= tolerance).length / bedtimes.length;
}

final class WakeUp {
  const WakeUp(this.start, this.minutes, this.afterStage, this.moved);
  final DateTime start;
  final int minutes;

  /// Stage right before waking.
  final Stage afterStage;

  /// Steps were recorded during the wake-up.
  final bool moved;
}

/// Wake runs of ≥ [minMinutes] inside a night (first/last asleep excluded).
List<WakeUp> wakeUps(List<Minute> night, {int minMinutes = 2}) {
  final out = <WakeUp>[];
  var i = 0;
  while (i < night.length) {
    if (night[i].stage == Stage.wake) {
      final s = i;
      var moved = false;
      while (i < night.length && night[i].stage == Stage.wake) {
        if (night[i].steps > 0) moved = true;
        i++;
      }
      if (s > 0 && i < night.length && i - s >= minMinutes) {
        out.add(WakeUp(night[s].ts, i - s, night[s - 1].stage, moved));
      }
    } else {
      i++;
    }
  }
  return out;
}

/// Estimated minutes to fall asleep: the still, worn minutes right before
/// the first asleep minute, capped at 60. [before] is sorted, oldest first.
int sleepLatency(List<Minute> before) {
  var n = 0;
  for (final m in before.reversed) {
    if (m.steps > 0 || m.stage == Stage.unknown || n >= 60) break;
    n++;
  }
  return n;
}
