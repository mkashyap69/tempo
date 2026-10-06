/// Cardio load: last 7 days of TRIMP against the last 28 (acute vs chronic).
///
/// Days with no data (band off, not synced, paused) are null and drop out
/// of both means. Counting them as 0 made the 28-day normal sag after a
/// gap, so an ordinary week read as overreaching.
library;

enum LoadStatus { learning, detraining, maintaining, building, overreaching }

final class CardioLoad {
  const CardioLoad({
    required this.acute,
    required this.chronic,
    required this.status,
    this.acuteDays = 0,
    this.chronicDays = 0,
  });

  /// Mean daily TRIMP over the last 7 days.
  final double acute;

  /// Mean daily TRIMP over the last 28 days.
  final double chronic;
  final LoadStatus status;

  /// Days with data behind [acute] (of 7) and [chronic] (of 28).
  final int acuteDays, chronicDays;

  double get ratio => chronic <= 0 ? 0 : acute / chronic;

  /// Percent above (+) or below (−) the 28-day normal.
  int get percentVsNormal => ((ratio - 1) * 100).round();

  /// Productive range is chronic × 0.8–1.3.
  ({double lo, double hi}) get productive =>
      (lo: chronic * 0.8, hi: chronic * 1.3);
}

/// Days with data needed before a status is shown: in the last 28, and
/// in the last 7. With fewer, the ratio compares a week with itself.
const loadMinDays = 14, loadMinAcuteDays = 4;

/// A calendar day counts as data with at least this many minutes of HR.
const loadMinWornMinutes = 600;

LoadStatus loadStatusFor(double ratio) => ratio < 0.8
    ? LoadStatus.detraining
    : ratio < 1.0
    ? LoadStatus.maintaining
    : ratio <= 1.3
    ? LoadStatus.building
    : LoadStatus.overreaching;

/// [dailyTrimp] is newest first, one entry per day, null where the day
/// has no data.
CardioLoad cardioLoad(List<double?> dailyTrimp) {
  final a = dailyTrimp.take(7).whereType<double>().toList();
  final c = dailyTrimp.take(28).whereType<double>().toList();
  double mean(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  final acute = mean(a), chronic = mean(c);
  final ready =
      c.length >= loadMinDays && a.length >= loadMinAcuteDays && chronic > 0;
  return CardioLoad(
    acute: acute,
    chronic: chronic,
    status: ready ? loadStatusFor(acute / chronic) : LoadStatus.learning,
    acuteDays: a.length,
    chronicDays: c.length,
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
