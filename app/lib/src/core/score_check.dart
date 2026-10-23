import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'data_source.dart';
import 'feel.dart';

/// Days of scores the check looks back over.
const scoreCheckDays = 90;

/// Developer → Score check: the validation numbers of
/// docs/research/Algorithm review.md §11 on this phone's own scores.
/// Read-only; nothing leaves the phone.
final class ScoreCheck {
  const ScoreCheck({
    required this.days,
    required this.algoVersions,
    required this.spread,
    required this.noise,
    required this.colours,
    required this.feel,
    required this.offDaysBelow,
    required this.offDays,
  });

  /// Days of the active source in the window.
  final int days;

  /// How many of those days each algo version scored (all current after
  /// the stale-algo pass).
  final Map<int, int> algoVersions;

  /// Per score (sleep score, recovery, strain): spread and day-to-day noise.
  final Map<String, sc.Spread?> spread;
  final Map<String, sc.Noise?> noise;
  final Map<sc.RecoveryColor, double> colours;

  /// Recovery against morning feel.
  final sc.FeelComparison feel;

  /// Share of body-signal days whose recovery (before the vitals penalty)
  /// was below your usual median; null with too few days.
  final double? offDaysBelow;
  final int offDays;
}

Future<ScoreCheck> loadScoreCheck(st.TempoDb db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final from = DateTime(at.year, at.month, at.day - scoreCheckDays);
  final source = (await loadDataSource(db)).key;
  final rows = [
    for (final s in await db.scoresBetween(from, at))
      if (s.source == source) s,
  ];
  final dates = [for (final r in rows) r.date];
  final series = <String, sc.Series>{
    'Sleep score': {for (final r in rows) r.date: r.sleepScore},
    'Recovery': {
      for (final r in rows) r.date: r.calibrating ? null : r.recovery,
    },
    'Strain': {for (final r in rows) r.date: r.strain},
  };
  final versions = <int, int>{};
  for (final r in rows) {
    versions[r.algoVersion] = (versions[r.algoVersion] ?? 0) + 1;
  }
  final judged = [
    for (final r in rows)
      if (!r.calibrating && r.recovery != null)
        (recovery: r.recovery!, penalty: r.vitalsPenalty),
  ];
  return ScoreCheck(
    days: rows.length,
    algoVersions: versions,
    spread: {for (final e in series.entries) e.key: sc.spread(e.value.values)},
    noise: {for (final e in series.entries) e.key: sc.noise(dates, e.value)},
    colours: sc.colours(series['Recovery']!.values),
    feel: await feelComparison(db, at),
    offDaysBelow: sc.offDaysBelowMedian(judged),
    offDays: judged.where((d) => d.penalty > 0).length,
  );
}
