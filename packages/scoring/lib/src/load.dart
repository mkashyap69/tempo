/// Cardio load: last 7 days of TRIMP against the last 28 (acute vs chronic).
library;

enum LoadStatus { learning, detraining, maintaining, building, overreaching }

final class CardioLoad {
  const CardioLoad({
    required this.acute,
    required this.chronic,
    required this.status,
  });

  /// Mean daily TRIMP over the last 7 days.
  final double acute;

  /// Mean daily TRIMP over the last 28 days.
  final double chronic;
  final LoadStatus status;

  double get ratio => chronic <= 0 ? 0 : acute / chronic;

  /// Percent above (+) or below (−) the 28-day normal.
  int get percentVsNormal => ((ratio - 1) * 100).round();

  /// Productive range is chronic × 0.8–1.3.
  ({double lo, double hi}) get productive =>
      (lo: chronic * 0.8, hi: chronic * 1.3);
}

/// Days of data needed before a status is shown.
const loadMinDays = 7;

LoadStatus loadStatusFor(double ratio) => ratio < 0.8
    ? LoadStatus.detraining
    : ratio < 1.0
    ? LoadStatus.maintaining
    : ratio <= 1.3
    ? LoadStatus.building
    : LoadStatus.overreaching;

/// [dailyTrimp] is newest first, one entry per day (missing days as 0).
CardioLoad cardioLoad(List<double> dailyTrimp) {
  double mean(Iterable<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  final acute = mean(dailyTrimp.take(7));
  final chronic = mean(dailyTrimp.take(28));
  if (dailyTrimp.length < loadMinDays || chronic <= 0) {
    return CardioLoad(
      acute: acute,
      chronic: chronic,
      status: LoadStatus.learning,
    );
  }
  return CardioLoad(
    acute: acute,
    chronic: chronic,
    status: loadStatusFor(acute / chronic),
  );
}

/// Rolling (acute, chronic) for each of the last [weeks] weeks, oldest first.
/// [dailyTrimp] is newest first.
List<({double acute, double chronic})> loadHistory(
  List<double> dailyTrimp, {
  int weeks = 12,
}) => [
  for (var w = weeks - 1; w >= 0; w--)
    if (dailyTrimp.length > w * 7)
      (
        acute: cardioLoad(dailyTrimp.sublist(w * 7)).acute,
        chronic: cardioLoad(dailyTrimp.sublist(w * 7)).chronic,
      ),
];
