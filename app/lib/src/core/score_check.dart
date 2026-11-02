import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'data_source.dart';
import 'feel.dart';
import 'score_service.dart' show toScoring;

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
    this.bySignal = const {},
    this.better,
  });

  /// Each recovery input against morning feel (V8), and the one that
  /// tracks it clearly better than the score, if any.
  final Map<String, ({int n, double? rho})> bySignal;
  final String? better;

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
  // V8: each rated morning's recovery inputs, rebuilt as the score used
  // them, against how you felt.
  final older = [
    for (final s in await db.scoresBetween(
      from.subtract(const Duration(days: 31)),
      at,
    ))
      if (s.source == source) toScoring(s),
  ]..sort((a, b) => b.date.compareTo(a.date));
  final rated = {for (final f in await db.feelSince(from)) f.date: f.feel};
  final mornings = <(List<sc.RecoveryShare>, int)>[];
  for (var i = 0; i < older.length; i++) {
    final d = older[i];
    final key = st.dateKey(d.date);
    if (d.calibrating || d.recovery == null || rated[key] == null) continue;
    mornings.add((sc.recoveryBreakdown(d, older.sublist(i + 1)), rated[key]!));
  }
  final bySignal = sc.feelBySignal(mornings);
  final feel = await feelComparison(db, at);
  return ScoreCheck(
    bySignal: bySignal,
    better: sc.betterSignal(bySignal, feel.rho),
    days: rows.length,
    algoVersions: versions,
    spread: {for (final e in series.entries) e.key: sc.spread(e.value.values)},
    noise: {for (final e in series.entries) e.key: sc.noise(dates, e.value)},
    colours: sc.colours(series['Recovery']!.values),
    feel: feel,
    offDaysBelow: sc.offDaysBelowMedian(judged),
    offDays: judged.where((d) => d.penalty > 0).length,
  );
}
