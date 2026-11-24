import 'dart:convert';

import 'package:health_source/health_source.dart' as hs;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'body.dart' show loadWeightTrend;
import 'coach_service.dart' show dayOf;
import 'data_source.dart';
import 'minutes.dart' show loadHealthRecords;
import 'profile.dart';

/// Food targets from the energy Apple Health / Health Connect hold (D2,
/// decisions.md 2026-11-24). Read-only and shown only: no score uses them.

/// Sums [kinds] per day and per app, then keeps the app with the most for
/// each day (phone and watch both write active energy).
Future<Map<DateTime, double>> _perDay(
  st.TempoDb db,
  DateTime from,
  DateTime to,
  List<hs.HealthKind> kinds,
) async {
  final recs = await loadHealthRecords(db, from, to, kinds: kinds);
  final byDay = <DateTime, Map<String, double>>{};
  for (final r in recs) {
    final apps = byDay[dayOf(r.start)] ??= {};
    apps[r.sourceApp] = (apps[r.sourceApp] ?? 0) + r.value;
  }
  return {for (final e in byDay.entries) e.key: sc.perDayBestSource(e.value)};
}

/// Full days of energy burned before [today], last 14.
Future<List<sc.DayEnergy>> loadDayEnergy(st.TempoDb db, {DateTime? now}) async {
  if (!(await loadDataSource(db)).isHealth) return const [];
  final t = dayOf(now ?? DateTime.now());
  final from = t.subtract(const Duration(days: sc.maintenanceWindow));
  final active = await _perDay(db, from, t, const [hs.HealthKind.activeEnergy]);
  final resting = await _perDay(db, from, t, const [
    hs.HealthKind.restingEnergy,
  ]);
  final total = await _perDay(db, from, t, const [hs.HealthKind.totalEnergy]);
  final days = {...active.keys, ...resting.keys, ...total.keys}.toList()
    ..sort();
  return [
    for (final d in days)
      if (sc.dayEnergyTotal(
            active: active[d] ?? 0,
            resting: resting[d] ?? 0,
            total: total[d] ?? 0,
          )
          case final k?)
        (day: d, kcal: k),
  ];
}

/// Food energy and protein another app logged to Health today; null each
/// when nothing was logged.
Future<({double? kcal, double? protein})> loadIntakeToday(
  st.TempoDb db, {
  DateTime? now,
}) async {
  if (!(await loadDataSource(db)).isHealth) return (kcal: null, protein: null);
  final n = now ?? DateTime.now();
  final t = dayOf(n);
  final end = t.add(const Duration(days: 1));
  final kcal = await _perDay(db, t, end, const [hs.HealthKind.dietaryEnergy]);
  final protein = await _perDay(db, t, end, const [hs.HealthKind.protein]);
  return (kcal: kcal[t], protein: protein[t]);
}

/// Targets you accepted or adjusted, or null while they're only suggested.
final class SavedFood {
  const SavedFood({this.kcal, required this.protein, required this.set});
  final double? kcal;
  final double protein;
  final DateTime set;
}

Future<SavedFood?> loadSavedFood(st.TempoDb db) async {
  final raw = await db.setting(Keys.foodTargets);
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return SavedFood(
      kcal: (j['kcal'] as num?)?.toDouble(),
      protein: (j['protein'] as num).toDouble(),
      set: DateTime.parse(j['set'] as String),
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveFood(st.TempoDb db, {double? kcal, required double protein}) =>
    db.putSetting(
      Keys.foodTargets,
      jsonEncode({
        'kcal': kcal,
        'protein': protein,
        'set': st.dateKey(DateTime.now()),
      }),
    );

Future<void> clearFood(st.TempoDb db) => db.deleteSetting(Keys.foodTargets);

/// Everything the Food screen shows.
final class FoodModel {
  const FoodModel({
    required this.suggested,
    required this.weightKg,
    required this.weightFromHealth,
    required this.daysOfEnergy,
    this.saved,
    this.intakeKcal,
    this.intakeProtein,
    required this.health,
  });
  final sc.FoodTargets suggested;
  final double weightKg;
  final bool weightFromHealth;
  final int daysOfEnergy;
  final SavedFood? saved;
  final double? intakeKcal, intakeProtein;
  final bool health;

  /// The protein target in use: yours once set, else the suggestion.
  double get protein => saved?.protein ?? suggested.protein;
  double? get kcal => saved == null ? suggested.kcal : saved!.kcal;
}

Future<FoodModel> loadFood(st.TempoDb db, {DateTime? now}) async {
  final p = await loadAppProfile(db) ?? const Profile();
  final trend = await loadWeightTrend(db, now: now);
  final weight = trend?.weekMean ?? p.weightKg;
  final energy = await loadDayEnergy(db, now: now);
  final m = sc.maintenanceKcal(energy, now ?? DateTime.now());
  final intake = await loadIntakeToday(db, now: now);
  return FoodModel(
    suggested: sc.foodTargets(
      goal: p.goal,
      weightKg: weight,
      male: p.male,
      maintenance: m,
    ),
    weightKg: weight,
    weightFromHealth: trend != null,
    daysOfEnergy: energy.length,
    saved: await loadSavedFood(db),
    intakeKcal: intake.kcal,
    intakeProtein: intake.protein,
    health: (await loadDataSource(db)).isHealth,
  );
}
