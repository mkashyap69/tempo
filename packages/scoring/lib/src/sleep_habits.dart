/// Sleep type (larks and owls, steady or restless) and the 21-day sleep
/// plan: one habit a week, picked from the weakest area.
library;

import 'dart:math';

import 'everyday.dart' show NightSpan, Regularity, regularityBand;
import 'sleep_plan.dart' show consistency;

// ---- sleep type -------------------------------------------------------------

/// When you sleep: mid-sleep before 03:30 is a lark, after 04:30 an owl,
/// in between a dove. Adults' mid-sleep centres near 04:00 (Roenneberg
/// 2007, MCTQ); the hour around it is the middle. TODO(verify) the cut-offs
/// against real users' spread before the beta.
enum Bird { lark, dove, owl }

/// How steady the timing is (from the Sleep Regularity Index bands).
enum Steadiness { steady, wandering, restless }

/// Nights needed before a type is shown.
const sleepTypeNights = 7;

/// Long and short sleepers, by average hours asleep.
const longSleeperHours = 8.5, shortSleeperHours = 6.5;

final class SleepType {
  const SleepType({
    required this.bird,
    required this.steadiness,
    required this.midSleep,
    required this.hours,
    required this.nights,
  });
  final Bird bird;
  final Steadiness steadiness;

  /// Median mid-sleep, minutes from midnight (negative = before midnight).
  final int midSleep;

  /// Average hours from sleep start to end.
  final double hours;
  final int nights;

  /// "Restless owl".
  String get name {
    final s = switch (steadiness) {
      Steadiness.steady => 'Steady',
      Steadiness.wandering => 'Wandering',
      Steadiness.restless => 'Restless',
    };
    return '$s ${bird.name}';
  }

  bool get longSleeper => hours >= longSleeperHours;
  bool get shortSleeper => hours < shortSleeperHours;
}

/// Mid-sleep of [n] as minutes from midnight, in −720..719.
int midSleepMinute(NightSpan n) {
  final mid = n.start.add(n.end.difference(n.start) ~/ 2);
  final m = mid.hour * 60 + mid.minute;
  return m >= 720 ? m - 1440 : m;
}

Bird birdFor(int midSleep) => midSleep < 210
    ? Bird.lark
    : midSleep > 270
    ? Bird.owl
    : Bird.dove;

/// Steadiness from the Sleep Regularity Index when there is one, else from
/// how many bedtimes fall within 25 minutes of the usual one (≥ 70 %
/// steady, ≥ 45 % wandering). TODO(verify) the fallback bands.
Steadiness steadinessFor({double? sri, required List<int> bedtimes}) {
  if (sri != null) {
    return switch (regularityBand(sri)) {
      Regularity.regular => Steadiness.steady,
      Regularity.fair => Steadiness.wandering,
      Regularity.irregular => Steadiness.restless,
    };
  }
  final c = consistency(bedtimes);
  return c >= .7
      ? Steadiness.steady
      : c >= .45
      ? Steadiness.wandering
      : Steadiness.restless;
}

/// Your sleep type over [nights] (the last 14 main sleeps), or null under
/// [sleepTypeNights].
SleepType? sleepType(List<NightSpan> nights, {double? sri}) {
  if (nights.length < sleepTypeNights) return null;
  final mids = [for (final n in nights) midSleepMinute(n)]..sort();
  final mid = mids[mids.length ~/ 2];
  final hours =
      nights.fold<double>(
        0,
        (a, n) => a + n.end.difference(n.start).inMinutes / 60,
      ) /
      nights.length;
  return SleepType(
    bird: birdFor(mid),
    steadiness: steadinessFor(
      sri: sri,
      bedtimes: [for (final n in nights) n.start.hour * 60 + n.start.minute],
    ),
    midSleep: mid,
    hours: hours,
    nights: nights.length,
  );
}

/// One line on what the type means.
String sleepTypeLine(SleepType t) {
  final when = switch (t.bird) {
    Bird.lark => 'An early sleeper',
    Bird.dove => 'A middle-of-the-night sleeper',
    Bird.owl => 'A night person',
  };
  final how = switch (t.steadiness) {
    Steadiness.steady => 'who keeps the same hours',
    Steadiness.wandering => 'whose hours drift a little',
    Steadiness.restless => 'whose bedtime wanders',
  };
  return '$when $how.';
}

/// The one tip for the type.
String sleepTypeTip(SleepType t) => switch (t.steadiness) {
  Steadiness.steady when t.shortSleeper =>
    'Your timing is steady. The win now is a little more of it: lights out '
        '20 minutes earlier.',
  Steadiness.steady =>
    '${t.bird == Bird.owl ? 'Owls do fine when the timing is steady, and yours is.' : 'Your timing is steady.'} Keep weekends close to weekdays.',
  _ =>
    '${t.bird == Bird.owl ? 'Owls do fine when the timing is steady. ' : ''}Your biggest win is a fixed wake time, weekends too.',
};

// ---- the 21-day plan --------------------------------------------------------

/// What the plan works on.
enum SleepFocus { regularity, duration, fallingAsleep }

const sleepPlanDays = 21;

/// The weakest area: how far each sits from a healthy mark, scaled so one
/// unit is a clear gap (regularity 30 SRI points under 80, an hour under
/// need, 20 minutes over 20 to fall asleep). Ties go to regularity, the
/// area most tied to how rested people feel (Phillips 2017).
SleepFocus weakestSleepArea({
  double? sri,
  double? bedtimeConsistency,
  double? hours,
  double? needHours,
  double? latencyMin,
}) {
  final reg = sri != null
      ? (80 - sri) / 30
      : bedtimeConsistency == null
      ? 0.0
      : (.7 - bedtimeConsistency) / .4;
  final dur = hours == null || needHours == null ? 0.0 : (needHours - hours);
  final lat = latencyMin == null ? 0.0 : (latencyMin - 20) / 20;
  final best = max(reg, max(dur, lat));
  if (best <= 0 || reg == best) return SleepFocus.regularity;
  return dur == best ? SleepFocus.duration : SleepFocus.fallingAsleep;
}

String sleepFocusName(SleepFocus f) => switch (f) {
  SleepFocus.regularity => 'Steady rhythm',
  SleepFocus.duration => 'More sleep',
  SleepFocus.fallingAsleep => 'Falling asleep faster',
};

/// A habit in the plan; [auto] ones are ticked from the night's data.
final class SleepHabit {
  const SleepHabit(this.id, this.title, this.detail, {this.auto = false});
  final String id, title, detail;
  final bool auto;
}

/// One week's new habit, as the weeks list shows it.
final class SleepWeek {
  const SleepWeek(this.habit, this.why);
  final SleepHabit habit;
  final String why;
}

String _clock(int m) {
  final x = ((m % 1440) + 1440) % 1440;
  return '${x ~/ 60}:${(x % 60).toString().padLeft(2, '0')}';
}

/// The three weeks for [f], with the wake and bed times the plan keeps.
List<SleepWeek> sleepWeeks(
  SleepFocus f, {
  required int wakeMinute,
  required int bedMinute,
}) {
  final wake = SleepWeek(
    SleepHabit(
      'wake',
      'Up by ${_clock(wakeMinute)}',
      'Within 30 minutes, weekends too. Counted from your sleep.',
      auto: true,
    ),
    'A fixed wake time anchors the body clock; bedtime follows.',
  );
  final light = SleepWeek(
    const SleepHabit(
      'light',
      'Daylight within an hour of waking',
      '10 minutes outside is enough.',
    ),
    'Morning light sets the clock earlier and steadier.',
  );
  final wind = SleepWeek(
    SleepHabit(
      'wind',
      'Wind down from ${_clock(bedMinute - 30)}',
      'Screens off and lights low for the last 30 minutes.',
    ),
    'A routine tells your body sleep is coming.',
  );
  final caffeine = SleepWeek(
    const SleepHabit(
      'caffeine',
      'No caffeine after 14:00',
      'Coffee, tea, cola and energy drinks.',
    ),
    'Caffeine lasts 5–6 hours and delays falling asleep.',
  );
  final bed = SleepWeek(
    SleepHabit(
      'bed',
      'Lights out by ${_clock(bedMinute)}',
      'Counted from when your sleep starts.',
      auto: true,
    ),
    'The surest way to more sleep is starting it earlier.',
  );
  final getUp = SleepWeek(
    const SleepHabit(
      'getup',
      'Awake over 20 minutes? Get up',
      'Something calm in dim light, back to bed when sleepy.',
    ),
    'Bed stays linked with sleep, not with lying awake.',
  );
  return switch (f) {
    SleepFocus.regularity => [wake, light, wind],
    SleepFocus.duration => [bed, wind, caffeine],
    SleepFocus.fallingAsleep => [caffeine, wind, getUp],
  };
}

/// Day of the plan (0-based) on [day], or null outside it.
int? sleepPlanDay(DateTime start, DateTime day) {
  final d = DateTime(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime(start.year, start.month, start.day)).inDays;
  return d < 0 || d >= sleepPlanDays ? null : d;
}

/// The habits for plan day [d]: each week adds one and keeps the earlier.
List<SleepHabit> habitsOn(List<SleepWeek> weeks, int d) => [
  for (var w = 0; w <= min(d ~/ 7, weeks.length - 1); w++) weeks[w].habit,
];

/// Whether an auto habit was kept: woke (or fell asleep) within 30 minutes
/// of the target, or earlier; [actual] and [target] are minutes of day.
bool keptTime(int actual, int target, {int tolerance = 30}) {
  var d = (actual - target) % 1440;
  if (d > 720) d -= 1440;
  if (d < -720) d += 1440;
  return d <= tolerance;
}

/// A day counts as kept when at least two thirds of its habits were done.
bool dayKept(int done, int habits) => habits > 0 && done * 3 >= habits * 2;
