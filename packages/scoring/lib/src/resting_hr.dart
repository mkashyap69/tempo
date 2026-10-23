import 'baseline.dart';
import 'types.dart';

/// Resting heart rate of a night: the [q] quantile (10th percentile) of
/// the heart rate in its asleep minutes, or of all [minutes] when none
/// is staged asleep. Null with fewer than [minReadings] readings.
///
/// Algo 10: was the lowest 5-minute average, an extreme value that one
/// dropout or a sparse watch (a reading every ~5 min) could set alone. A
/// low percentile is about as low and far steadier from night to night.
double? restingHr(List<Minute> minutes, {double q = .1, int minReadings = 20}) {
  final asleep = [
    for (final m in minutes)
      if (m.stage.asleep && m.hr != null) m.hr!.toDouble(),
  ];
  final xs = asleep.isNotEmpty
      ? asleep
      : [
          for (final m in minutes)
            if (m.hr != null) m.hr!.toDouble(),
        ];
  if (xs.length < minReadings) return null;
  return quantile(xs, q);
}

/// [DailyScore.rhrKind] of a resting HR from the night itself.
const rhrFromSleep = 'sleep';

/// [DailyScore.rhrKind] of the Health source's own (daytime) resting HR,
/// typically 5–10 bpm above the night's: never one baseline with the other.
const rhrFromSource = 'source';
