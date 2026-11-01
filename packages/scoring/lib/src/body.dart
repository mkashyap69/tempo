/// Body weight and the menstrual cycle, as read from Apple Health / Health
/// Connect (U2). Shown only: neither feeds a score. Pure Dart.
library;

/// A day's weight (the last reading of the day), kg.
typedef DayWeight = ({DateTime day, double kg});

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// One weight per day, the day's last reading, oldest first.
List<DayWeight> dailyWeights(Iterable<(DateTime, double)> readings) {
  final byDay = <DateTime, (DateTime, double)>{};
  for (final r in readings) {
    final d = _day(r.$1);
    final had = byDay[d];
    if (had == null || r.$1.isAfter(had.$1)) byDay[d] = r;
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) (day: d, kg: byDay[d]!.$2)];
}

/// Where weight is heading: this week's mean against the mean four weeks
/// earlier. Day-to-day weight swings by a kilo or more with water and
/// food, so single readings are never compared.
final class WeightTrend {
  const WeightTrend({
    required this.weekMean,
    required this.readings,
    this.change4w,
  });

  /// Mean of the last 7 days' readings, kg.
  final double weekMean;

  /// Readings in the last 7 days.
  final int readings;

  /// This week's mean minus the mean of days 28–34 ago; null without
  /// readings then.
  final double? change4w;

  /// "Steady" inside ±0.3 kg over four weeks, else the direction.
  String get word {
    final c = change4w;
    if (c == null) return 'Not enough history yet';
    if (c.abs() < .3) return 'Steady';
    return c < 0 ? 'Going down' : 'Going up';
  }
}

/// The trend at [today] from daily weights; null without a reading in the
/// last 7 days.
WeightTrend? weightTrend(List<DayWeight> days, DateTime today) {
  final t = _day(today);
  List<double> between(int fromAgo, int toAgo) => [
    for (final d in days)
      if (!d.day.isBefore(t.subtract(Duration(days: toAgo))) &&
          !d.day.isAfter(t.subtract(Duration(days: fromAgo))))
        d.kg,
  ];
  double mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;
  final week = between(0, 6);
  if (week.isEmpty) return null;
  final then = between(28, 34);
  return WeightTrend(
    weekMean: mean(week),
    readings: week.length,
    change4w: then.isEmpty ? null : mean(week) - mean(then),
  );
}

/// A day's menstrual flow as stored (0 none … 3 heavy), and whether the
/// app marked it as the first day of a cycle.
typedef FlowDay = ({DateTime day, double flow, bool start});

/// The cycle Tempo can see: day 1 is the first flow day after at least
/// [gap] days without flow (or a day the app marked as a start).
final class Cycle {
  const Cycle({required this.start, required this.day, this.typicalLength});

  /// Day 1 of the current cycle.
  final DateTime start;

  /// Today's day of the cycle, 1-based.
  final int day;

  /// Median length of the last cycles (up to 6) of 21–45 days; null with
  /// fewer than 2.
  final int? typicalLength;

  /// The days before an expected period, when resting heart rate and night
  /// temperature often run higher and HRV lower: the last 7 days of a
  /// typical cycle. False without a typical length.
  bool get late => typicalLength != null && day > typicalLength! - 7;
}

/// The current cycle at [today] from flow days; null without a start in
/// the last 60 days (or none at all).
Cycle? cycleAt(Iterable<FlowDay> flow, DateTime today, {int gap = 10}) {
  final t = _day(today);
  final bleed = {
    for (final f in flow)
      if (f.flow > .5 || f.start) _day(f.day),
  };
  final marked = {
    for (final f in flow)
      if (f.start) _day(f.day),
  };
  final days = bleed.where((d) => !d.isAfter(t)).toList()..sort();
  final starts = <DateTime>[];
  DateTime? prev;
  for (final d in days) {
    if (marked.contains(d) || prev == null || d.difference(prev).inDays > gap) {
      if (starts.isEmpty || d.difference(starts.last).inDays > gap) {
        starts.add(d);
      }
    }
    prev = d;
  }
  if (starts.isEmpty) return null;
  final start = starts.last;
  final day = t.difference(start).inDays + 1;
  if (day > 60) return null;
  final lengths = <int>[
    for (var i = 1; i < starts.length; i++)
      starts[i].difference(starts[i - 1]).inDays,
  ].where((n) => n >= 21 && n <= 45).toList();
  final recent = lengths.length > 6
      ? lengths.sublist(lengths.length - 6)
      : lengths;
  int? typical;
  if (recent.length >= 2) {
    final s = [...recent]..sort();
    typical = s.length.isOdd
        ? s[s.length ~/ 2]
        : ((s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2).round();
  }
  return Cycle(start: start, day: day, typicalLength: typical);
}
