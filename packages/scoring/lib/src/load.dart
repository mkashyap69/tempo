/// Cardio load: Banister's fitness–fatigue model on daily TRIMP.
///
/// Fatigue (acute) is an exponentially weighted average with a 7-day time
/// constant, fitness (chronic) one with 42 days, as TrainingPeaks' ATL /
/// CTL and Intervals.icu do. Form is fitness − fatigue; the ratio of the
/// two drives the status.
///
/// Algo 10: was rolling 7- and 28-day means with the 7 days inside the
/// 28, the coupled acute:chronic ratio whose "sweet spot" doesn't hold up
/// (Lolli 2019; Impellizzeri 2020). Exponential averages track load better
/// (Williams 2017). It is a training-load guide, not an injury predictor.
///
/// Days with no data (band off, not synced, paused) are null and leave
/// both averages where they were. Counting them as 0 made the normal sag
/// after a gap, so an ordinary week read as overreaching.
library;

import 'dart:math';

enum LoadStatus { learning, detraining, maintaining, building, overreaching }

/// Time constants, days.
const fatigueDays = 7, fitnessDays = 42;

final class CardioLoad {
  const CardioLoad({
    required this.acute,
    required this.chronic,
    required this.status,
    this.acuteDays = 0,
    this.chronicDays = 0,
    this.rampPerWeek = 0,
  });

  /// Fatigue: daily TRIMP, exponentially weighted over ~7 days.
  final double acute;

  /// Fitness: daily TRIMP, exponentially weighted over ~42 days.
  final double chronic;
  final LoadStatus status;

  /// Days with data in the last 7 and the last 28.
  final int acuteDays, chronicDays;

  /// How much fitness rose (or fell) over the last 7 days, TRIMP/day.
  final double rampPerWeek;

  double get ratio => chronic <= 0 ? 0 : acute / chronic;

  /// Form: fitness − fatigue. Negative while building, positive when fresh.
  double get form => chronic - acute;

  /// Percent above (+) or below (−) your normal.
  int get percentVsNormal => ((ratio - 1) * 100).round();

  /// Productive range is chronic × 0.8–1.3.
  ({double lo, double hi}) get productive =>
      (lo: chronic * 0.8, hi: chronic * 1.3);
}

/// Days with data needed before a status is shown: in the last 28, and
/// in the last 7.
const loadMinDays = 14, loadMinAcuteDays = 4;

/// A calendar day counts as data with at least this many minutes of HR.
const loadMinWornMinutes = 600;

/// HR readings a day needs to count as worn when the band measures every
/// [everyMinutes] minutes: the same 10 hours of wear. At every 10 or 30
/// minutes a day has at most 144 or 48 readings, so a flat 600 never passed.
int loadMinHrReadings(int everyMinutes) =>
    (loadMinWornMinutes / (everyMinutes < 1 ? 1 : everyMinutes)).ceil();

LoadStatus loadStatusFor(double ratio) => ratio < 0.8
    ? LoadStatus.detraining
    : ratio < 1.0
    ? LoadStatus.maintaining
    : ratio <= 1.3
    ? LoadStatus.building
    : LoadStatus.overreaching;

/// Fatigue and fitness after each day of [oldestFirst] (null = no data,
/// held). Both start from the mean of the first week's known days.
List<({double atl, double ctl})> _ewma(List<double?> oldestFirst) {
  final known = oldestFirst.whereType<double>().take(7).toList();
  if (known.isEmpty) return [for (final _ in oldestFirst) (atl: 0, ctl: 0)];
  var atl = known.reduce((a, b) => a + b) / known.length, ctl = atl;
  final ka = 1 - exp(-1 / fatigueDays), kc = 1 - exp(-1 / fitnessDays);
  return [
    for (final x in oldestFirst)
      if (x == null)
        (atl: atl, ctl: ctl)
      else
        (atl: atl += ka * (x - atl), ctl: ctl += kc * (x - ctl)),
  ];
}

/// [dailyTrimp] is newest first, one entry per day, null where the day
/// has no data. Give it 6+ weeks so fitness has settled.
CardioLoad cardioLoad(List<double?> dailyTrimp) {
  final a = dailyTrimp.take(7).whereType<double>().length;
  final c = dailyTrimp.take(28).whereType<double>().length;
  final series = _ewma(dailyTrimp.reversed.toList());
  if (series.isEmpty) {
    return const CardioLoad(acute: 0, chronic: 0, status: LoadStatus.learning);
  }
  final now = series.last;
  final weekAgo = series.length > 7 ? series[series.length - 8] : series.first;
  final ready = c >= loadMinDays && a >= loadMinAcuteDays && now.ctl > 0;
  return CardioLoad(
    acute: now.atl,
    chronic: now.ctl,
    status: ready ? loadStatusFor(now.atl / now.ctl) : LoadStatus.learning,
    acuteDays: a,
    chronicDays: c,
    rampPerWeek: now.ctl - weekAgo.ctl,
  );
}

/// Rolling (acute, chronic) for each of the last [weeks] weeks, oldest first.
/// [dailyTrimp] is newest first, null where the day has no data.
List<({double acute, double chronic})> loadHistory(
  List<double?> dailyTrimp, {
  int weeks = 12,
}) => [
  for (var w = weeks - 1; w >= 0; w--)
    if (dailyTrimp.length > w * 7)
      (
        acute: cardioLoad(dailyTrimp.sublist(w * 7)).acute,
        chronic: cardioLoad(dailyTrimp.sublist(w * 7)).chronic,
      ),
];
