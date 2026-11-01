import 'package:health_source/health_source.dart' as hs;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'data_source.dart';
import 'minutes.dart' show loadHealthRecords;

/// Weight, body fat and the cycle from Apple Health / Health Connect (U2,
/// decisions.md 2026-11-01). Read-only and shown only: no score uses them.

/// Daily weights in [from, to], oldest first. Empty off Health.
Future<List<sc.DayWeight>> loadWeights(
  st.TempoDb db,
  DateTime from,
  DateTime to,
) async {
  if (!(await loadDataSource(db)).isHealth) return const [];
  final recs = await loadHealthRecords(
    db,
    from,
    to.add(const Duration(days: 1)),
    kinds: const [hs.HealthKind.weight],
  );
  return sc.dailyWeights([for (final r in recs) (r.start, r.value)]);
}

/// The newest body-fat reading as a percent, or null.
Future<double?> latestBodyFat(st.TempoDb db, {DateTime? now}) async {
  if (!(await loadDataSource(db)).isHealth) return null;
  final t = now ?? DateTime.now();
  final recs = await loadHealthRecords(
    db,
    t.subtract(const Duration(days: 60)),
    t,
    kinds: const [hs.HealthKind.bodyFat],
  );
  if (recs.isEmpty) return null;
  recs.sort((a, b) => a.start.compareTo(b.start));
  final v = recs.last.value;
  // Apple Health stores a fraction, Health Connect a percent.
  return v <= 1 ? v * 100 : v;
}

/// Weight now: the weekly trend, or null without a reading this week.
Future<sc.WeightTrend?> loadWeightTrend(st.TempoDb db, {DateTime? now}) async {
  final t = dayOf(now ?? DateTime.now());
  final w = await loadWeights(db, t.subtract(const Duration(days: 35)), t);
  return sc.weightTrend(w, t);
}

/// The current cycle, or null (no flow data, or none in 60 days).
Future<sc.Cycle?> loadCycle(st.TempoDb db, {DateTime? now}) async {
  if (!(await loadDataSource(db)).isHealth) return null;
  final t = dayOf(now ?? DateTime.now());
  final recs = await loadHealthRecords(
    db,
    t.subtract(const Duration(days: 240)),
    t.add(const Duration(days: 1)),
    kinds: const [hs.HealthKind.menstruation],
  );
  return sc.cycleAt([
    for (final r in recs)
      (day: r.start, flow: r.value, start: r.extra == 'start'),
  ], t);
}
