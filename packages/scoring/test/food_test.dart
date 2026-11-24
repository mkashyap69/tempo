import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 11, 24);
  List<DayEnergy> days(int n, {double kcal = 2000}) => [
    for (var i = 1; i <= n; i++)
      (day: today.subtract(Duration(days: i)), kcal: kcal),
  ];

  group('maintenance', () {
    test('mean over 14 full days', () {
      expect(maintenanceKcal(days(14), today), 2000);
    });

    test('needs 10 days; today and empty days are left out', () {
      expect(maintenanceKcal(days(9), today), isNull);
      final d = [
        ...days(10),
        (day: today, kcal: 6500.0),
        (day: today.subtract(const Duration(days: 11)), kcal: 0.0),
      ];
      expect(maintenanceKcal(d, today), 2000);
    });

    test('days older than the window are left out', () {
      final d = [
        ...days(10),
        (day: today.subtract(const Duration(days: 20)), kcal: 6000.0),
      ];
      expect(maintenanceKcal(d, today), 2000);
    });

    test('a day: total wins, else active + resting, never without resting', () {
      expect(dayEnergyTotal(active: 500, resting: 1600), 2100);
      expect(dayEnergyTotal(active: 500, total: 2400), 2400);
      expect(dayEnergyTotal(active: 500), isNull);
    });

    test('apps writing the same energy are not added up', () {
      expect(perDayBestSource({'phone': 300, 'watch': 520}), 520);
      expect(perDayBestSource({}), 0);
    });
  });

  group('targets', () {
    test('fat loss: 500 under maintenance with the arithmetic', () {
      final f = foodTargets(
        goal: Goal.fatLoss,
        weightKg: 80,
        male: true,
        maintenance: 2600,
      );
      expect(f.kcal, 2100);
      expect(f.protein, 145); // 1.6–2.0 g/kg at 80 kg = 128–160, mid 144 → 145
      expect(f.fat, 70); // 30 % of 2,100 / 9 = 70
      expect(f.carbs, 225); // (2100 − 580 − 630) / 4 = 222.5 → 225
      expect(f.fibre, 29);
      expect(
        f.kcalWhy,
        'You burned 2,600 kcal a day on average over the last 14 days in Health, which holds your weight. Eating 500 kcal less is about 0.5 kg a week',
      );
    });

    test('never under the floor, never more than a quarter under', () {
      final f = foodTargets(
        goal: Goal.fatLoss,
        weightKg: 60,
        male: true,
        maintenance: 1800,
      );
      // 25 % of 1,800 = 450 → 1,350, under the 1,500 floor.
      expect(f.kcal, 1500);
      expect(f.kcalWhy, endsWith('. Tempo suggests no less than 1,500 kcal'));
      final w = foodTargets(
        goal: Goal.fatLoss,
        weightKg: 60,
        male: false,
        maintenance: 1800,
      );
      expect(w.kcal, 1350);
    });

    test('other goals eat to maintenance', () {
      final f = foodTargets(
        goal: Goal.fitness,
        weightKg: 70,
        male: false,
        maintenance: 2210,
      );
      expect(f.kcal, 2200);
      expect(f.protein, 105); // 1.4–1.6 × 70 = 98–112 → 105
    });

    test('no maintenance: protein only, and why', () {
      final f = foodTargets(goal: Goal.wellbeing, weightKg: 70, male: true);
      expect(f.kcal, isNull);
      expect(f.protein, 100); // 84–112 → 98 → 100
      expect(f.kcalWhy, contains('10 days'));
    });
  });
}
