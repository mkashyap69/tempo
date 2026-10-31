/// One-tap tags on Today's timeline, written as the Journal entries they
/// mean, so the impact engine gets them with the time they happened.
library;

import 'dart:math';

enum QuickTag { coffee, meal, alcohol, daylight }

String quickTagName(QuickTag t) => switch (t) {
  QuickTag.coffee => 'Coffee',
  QuickTag.meal => 'Meal',
  QuickTag.alcohol => 'Alcohol',
  QuickTag.daylight => 'Daylight',
};

/// One Journal answer: [value] for yes/no, [amount] for numbers and times
/// (minutes after midnight).
typedef QuickEntry = ({String key, bool value, double? amount});

/// Caffeine after 14:00 counts as late (the Journal's "Caffeine after 2 pm").
const lateCaffeineMinute = 14 * 60;

/// A meal within 2 hours of bedtime counts as late.
const lateMealMinutes = 120;

/// The Journal entries a [tag] at [minute] writes, given the day's existing
/// time and amount answers ([amounts], by key) and tonight's [bedtime]
/// (minute of day). Only ever turns a yes on; a later tag never clears one.
List<QuickEntry> quickTagEntries(
  QuickTag tag,
  int minute, {
  Map<String, double?> amounts = const {},
  required int bedtime,
}) {
  double later(String k) => max(amounts[k] ?? -1, minute.toDouble());
  double earlier(String k) => min(amounts[k] ?? 1e9, minute.toDouble());
  switch (tag) {
    case QuickTag.coffee:
      return [
        (key: 'last_caffeine', value: true, amount: later('last_caffeine')),
        if (minute >= lateCaffeineMinute)
          (key: 'caffeine_late', value: true, amount: null),
      ];
    case QuickTag.meal:
      final beforeBed = (bedtime - minute) % 1440;
      return [
        (key: 'last_meal', value: true, amount: later('last_meal')),
        (key: 'first_meal', value: true, amount: earlier('first_meal')),
        if (beforeBed <= lateMealMinutes)
          (key: 'late_meal', value: true, amount: null),
      ];
    case QuickTag.alcohol:
      return [
        (key: 'alcohol', value: true, amount: null),
        (key: 'drinks', value: true, amount: (amounts['drinks'] ?? 0) + 1),
      ];
    case QuickTag.daylight:
      return [(key: 'daylight', value: true, amount: null)];
  }
}
