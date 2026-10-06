import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../state/providers.dart';

/// The morning check-in shows on Today until this hour. Later in the day
/// the answer is about the day, not the night.
const feelAskUntilHour = 12;

/// Days of ratings the comparison looks back over.
const feelWindowDays = 90;

/// Today's rating (keyed by date), or null when not answered.
final feelProvider = StreamProvider.family<int?, String>(
  (ref, date) => ref.watch(dbProvider).watchFeel(DateTime.parse(date)),
);

/// Recovery against how you felt, over the last [feelWindowDays].
final feelComparisonProvider = dbQuery(
  (db, ref) => feelComparison(db, DateTime.now()),
);

/// Pairs each rated morning with that day's recovery (calibrating days
/// have no recovery to compare and are left out).
Future<sc.FeelComparison> feelComparison(st.TempoDb db, DateTime now) async {
  final from = DateTime(now.year, now.month, now.day - feelWindowDays);
  final feel = {for (final f in await db.feelSince(from)) f.date: f.feel};
  final scores = await db.scoresBetween(from, now);
  return sc.compareFeel([
    for (final s in scores)
      if (feel[s.date] != null && !s.calibrating && s.recovery != null)
        (s.recovery!, feel[s.date]!),
  ]);
}
