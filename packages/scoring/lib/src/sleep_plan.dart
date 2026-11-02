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

/// Minutes since [bedtime] when [now] falls between bedtime and [wake]
/// (all minutes of day, across midnight), else null: before bedtime, or
/// already the next day.
int? minutesPastBedtime(int now, int bedtime, int wake) {
  final window = ((wake - bedtime) % 1440 + 1440) % 1440;
  final since = ((now - bedtime) % 1440 + 1440) % 1440;
  return since < window ? since : null;
}

/// Hours of sleep left before [wake] if you go to bed at [now], allowing
/// [latency] to fall asleep.
double sleepIfBedNow(int now, int wake, {int latency = fallAsleepMinutes}) =>
    (((wake - now - latency) % 1440 + 1440) % 1440) / 60;

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

// ---- Stepping toward a goal time (V1) ---------------------------------------

/// Minutes a bedtime or wake target moves a week toward its goal. Shifting
/// sleep by 15–30 minutes every few days is what behavioural sleep advice
/// uses; larger jumps aren't kept (owner, Oct 2026: a 23:04 target against
/// a usual 00:31 got 2 taps from 28 wind-down reminders).
const sleepStepMinutes = 15;

/// Nights of history before a usual time is trusted.
const usualMinNights = 5;

/// A clock time on a scale that runs from noon to noon, so 23:30 and 00:30
/// are an hour apart and ordered.
int _noonScale(int m) => ((m - 720) % 1440 + 1440) % 1440;

/// Minutes [a] is later than [b] (negative when earlier), within ±12 h.
int clockDiff(int a, int b) => _noonScale(a) - _noonScale(b);

/// [usual] moved [steps] × [step] minutes toward [goal], never past it;
/// [goal] itself when [usual] is null or already within reach.
int stepToward(int? usual, int goal, int steps, {int step = sleepStepMinutes}) {
  if (usual == null) return goal;
  final d = clockDiff(goal, usual);
  final move = steps * step;
  if (d.abs() <= move) return goal;
  return ((usual + (d > 0 ? move : -move)) % 1440 + 1440) % 1440;
}

/// Tonight's bedtime: [goal] when you already go to bed by then (or near
/// it), else one step earlier than your [usual] bedtime. Only ever asks for
/// earlier: going to bed before the goal is never held against you.
int steppedBedtime({required int goal, int? usual}) =>
    usual == null || clockDiff(usual, goal) <= sleepStepMinutes
    ? goal
    : stepToward(usual, goal, 1);

/// Usual clock time from [times] (minutes of day), or null with fewer than
/// [usualMinNights].
int? usualClock(List<int> times) =>
    times.length < usualMinNights ? null : medianClock(times);

/// When the morning brief goes out: at [set], or 15 min after your
/// [usualWake] when you usually wake later than that (V1; owner: brief set
/// for 6:30, usual wake 9:09, so it landed on a sleeping phone).
int briefMinute(int set, int? usualWake, {int after = 15}) =>
    usualWake == null || clockDiff(usualWake + after, set) <= 0
    ? set
    : (usualWake + after) % 1440;
