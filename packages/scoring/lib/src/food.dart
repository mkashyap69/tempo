/// Daily food targets from what you burn (D2): maintenance from the
/// active and resting energy Apple Health / Health Connect hold, then a
/// target for your goal with the arithmetic shown. Read-only data, shown
/// only: no score uses it. Pure Dart.
library;

import 'coach.dart' show Goal;
import 'day_targets.dart' show proteinPerKg;

/// One full day's energy burned, kcal.
typedef DayEnergy = ({DateTime day, double kcal});

/// A day's total from what Health holds: Health Connect's total calories
/// burned when there is one, else active + resting. Null without resting
/// energy: a watch that doesn't write it would make the day look like a
/// famine.
double? dayEnergyTotal({
  double active = 0,
  double resting = 0,
  double total = 0,
}) => total > 0
    ? total
    : resting > 0
    ? active + resting
    : null;

/// Several apps write the same energy (phone and watch both count active
/// energy), so a day takes the single app with the most, never the sum.
double perDayBestSource(Map<String, double> byApp) =>
    byApp.values.fold(0.0, (a, b) => b > a ? b : a);

/// Days of energy maintenance needs, and the window it averages over.
const maintenanceMinDays = 10, maintenanceWindow = 14;

/// Mean daily energy over the last [maintenanceWindow] full days before
/// [today], kcal; null with fewer than [maintenanceMinDays] days.
double? maintenanceKcal(List<DayEnergy> days, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final from = t.subtract(const Duration(days: maintenanceWindow));
  final use = [
    for (final d in days)
      if (!d.day.isBefore(from) && d.day.isBefore(t) && d.kcal > 0) d.kcal,
  ];
  if (use.length < maintenanceMinDays) return null;
  return use.reduce((a, b) => a + b) / use.length;
}

/// A kilo of body fat is about 7,700 kcal, so 500 kcal a day under
/// maintenance loses about 0.45 kg a week.
const kcalPerKg = 7700.0, fatLossDeficit = 500.0;

/// The lowest daily target Tempo suggests (common clinical floors for an
/// unsupervised diet), and the largest deficit as a share of maintenance.
double kcalFloor(bool male) => male ? 1500 : 1200;
const maxDeficitShare = .25;

final class FoodTargets {
  const FoodTargets({
    required this.proteinLo,
    required this.proteinHi,
    required this.protein,
    this.maintenance,
    this.kcal,
    this.fibre,
    this.fat,
    this.carbs,
    required this.kcalWhy,
    required this.proteinWhy,
  });

  /// Protein a day, g: the range for your goal and the target inside it.
  final double proteinLo, proteinHi, protein;

  /// What keeps your weight, from Health; null without enough days.
  final double? maintenance;

  /// Daily kcal target and the macros that follow from it; null without
  /// [maintenance].
  final double? kcal, fibre, fat, carbs;

  /// The arithmetic in words.
  final String kcalWhy, proteinWhy;
}

String _k(num n) {
  final s = n.round().toString();
  return s.length <= 3
      ? s
      : '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}

/// Targets for [goal] at [weightKg]. Fat 30 % of kcal, fibre 14 g per
/// 1,000 kcal (US Dietary Guidelines), carbs what's left after protein
/// and fat. Protein rounds to 5 g.
FoodTargets foodTargets({
  required Goal goal,
  required double weightKg,
  required bool male,
  double? maintenance,
}) {
  final (lo, hi) = proteinPerKg(goal);
  final pLo = lo * weightKg, pHi = hi * weightKg;
  final protein = ((pLo + pHi) / 2 / 5).round() * 5.0;
  final proteinWhy =
      '${lo.toStringAsFixed(1)}–${hi.toStringAsFixed(1)} g per kg of body weight '
      'for your goal, at ${weightKg.toStringAsFixed(weightKg % 1 == 0 ? 0 : 1)} kg, spread over 3–4 meals';
  if (maintenance == null) {
    return FoodTargets(
      proteinLo: pLo,
      proteinHi: pHi,
      protein: protein,
      kcalWhy:
          'Needs $maintenanceMinDays days of active and resting energy from your watch in Health',
      proteinWhy: proteinWhy,
    );
  }
  final m = maintenance;
  final floor = kcalFloor(male);
  double kcal;
  String why;
  if (goal == Goal.fatLoss) {
    final cut = fatLossDeficit.clamp(0, m * maxDeficitShare).toDouble();
    kcal = m - cut;
    final perWeek = cut * 7 / kcalPerKg;
    why =
        'You burned ${_k(m)} kcal a day on average over the last $maintenanceWindow days in Health, which holds your weight. '
        'Eating ${_k(cut)} kcal less is about ${perWeek.toStringAsFixed(1)} kg a week';
    if (kcal < floor) {
      kcal = floor;
      why = '$why. Tempo suggests no less than ${_k(floor)} kcal';
    }
  } else {
    kcal = m;
    why =
        'You burned ${_k(m)} kcal a day on average over the last $maintenanceWindow days in Health, which holds your weight';
  }
  kcal = (kcal / 50).round() * 50.0;
  final fat = (kcal * .30 / 9 / 5).round() * 5.0;
  final carbs = ((kcal - protein * 4 - fat * 9) / 4 / 5).round() * 5.0;
  final fibre = (kcal / 1000 * 14).roundToDouble();
  return FoodTargets(
    proteinLo: pLo,
    proteinHi: pHi,
    protein: protein,
    maintenance: m,
    kcal: kcal,
    fibre: fibre,
    fat: fat,
    carbs: carbs < 0 ? 0 : carbs,
    kcalWhy: why,
    proteinWhy: proteinWhy,
  );
}
