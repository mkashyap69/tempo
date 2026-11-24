import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/food.dart';
import '../core/format.dart' show dayShort;
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'day_targets.dart' show dayTargetsProvider;

final foodProvider = FutureProvider<FoodModel>((ref) async {
  ref.watch(dbTickProvider);
  return loadFood(ref.watch(dbProvider));
});

String _k(num n) {
  final s = n.round().toString();
  return s.length <= 3
      ? s
      : '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}

/// You → Food targets, also opened from Today's protein target (D2):
/// targets from your weight and the energy Health holds, with the
/// arithmetic shown. Use these, or adjust.
class FoodScreen extends ConsumerWidget {
  const FoodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final m = ref.watch(foodProvider).value;
    if (m == null) return Scaffold(backgroundColor: c.bg);
    final db = ref.read(dbProvider);
    final f = m.suggested;
    final saved = m.saved;
    Future<void> changed() async {
      ref.invalidate(foodProvider);
      ref.invalidate(dayTargetsProvider);
    }

    Widget row(String name, String why, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TempoType.label.c(c.text1)),
                const SizedBox(height: 2),
                Text(why, style: TempoType.caption.c(c.text2)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(value, style: TempoType.titleM.c(c.text1).tnum),
        ],
      ),
    );

    final kcal = m.kcal;
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Food targets'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(
              m.intakeProtein == null ? 'Protein a day' : 'Protein today',
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _k(m.intakeProtein ?? m.protein),
                  style: TempoType.scoreL.c(c.text1),
                ),
                const SizedBox(width: 8),
                Text(
                  m.intakeProtein == null ? 'g' : 'g of ${_k(m.protein)} g',
                  style: TempoType.body.c(c.text2),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              m.intakeKcal == null && m.intakeProtein == null
                  ? m.health
                        ? 'Log meals in an app that writes to Health and Tempo counts them here. Until then, tick protein on Today.'
                        : 'Tick protein on Today after your meals.'
                  : 'From what you logged to Health today: ${m.intakeKcal == null ? '' : '${_k(m.intakeKcal!)} kcal · '}${_k(m.intakeProtein ?? 0)} g protein.',
              style: TempoType.body.c(c.text2),
            ),
          ],
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Overline(
                saved == null
                    ? 'Suggested for your goal'
                    : 'Yours since ${dayShort(saved.set)}',
              ),
              const SizedBox(height: 4),
              row(
                'Calories',
                saved?.kcal != null && saved!.kcal != f.kcal
                    ? 'Set by you. ${f.kcalWhy}.'
                    : '${f.kcalWhy}.',
                kcal == null ? '—' : '${_k(kcal)} kcal',
              ),
              const Hair(),
              row(
                'Protein',
                saved != null && saved.protein != f.protein
                    ? 'Set by you. Suggested ${_k(f.protein)} g: ${f.proteinWhy}.'
                    : '${f.proteinWhy}.',
                '${_k(m.protein)} g',
              ),
              if (f.fibre != null) ...[
                const Hair(),
                row(
                  'Fibre',
                  '14 g per 1,000 kcal, as dietary guidelines advise',
                  '${_k(f.fibre!)} g',
                ),
                const Hair(),
                row('Fat', '30 % of calories', '${_k(f.fat!)} g'),
                const Hair(),
                row(
                  'Carbs',
                  'The calories left after protein and fat',
                  '${_k(f.carbs!)} g',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (saved == null) ...[
                    Expanded(
                      child: TempoButton(
                        'Save these',
                        expand: true,
                        onTap: () async {
                          await saveFood(db, kcal: f.kcal, protein: f.protein);
                          await changed();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: TempoButton(
                      'Change',
                      kind: ButtonKind.secondary,
                      expand: true,
                      onTap: () async {
                        final r = await _adjust(
                          context,
                          kcal: kcal,
                          protein: m.protein,
                        );
                        if (r == null) return;
                        await saveFood(db, kcal: r.$1, protein: r.$2);
                        await changed();
                      },
                    ),
                  ),
                ],
              ),
              if (saved != null)
                TempoButton(
                  'Back to the suggestion',
                  kind: ButtonKind.text,
                  expand: true,
                  onTap: () async {
                    await clearFood(db);
                    await changed();
                  },
                ),
            ],
          ),
        ),
        Text(
          '${m.weightFromHealth ? 'Weight from Health' : 'Weight from your profile'}: '
          '${m.weightKg.toStringAsFixed(1)} kg. '
          '${m.daysOfEnergy == 0 ? 'No energy from Health yet.' : '${m.daysOfEnergy} of the last 14 days of energy from Health.'} '
          'A starting point for healthy adults, not medical advice: if you '
          'have a condition or are pregnant, ask a dietitian.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

/// Calories and protein in steps of 50 kcal and 5 g.
Future<(double?, double)?> _adjust(
  BuildContext context, {
  required double? kcal,
  required double protein,
}) => showTempoSheet<(double?, double)>(
  context,
  builder: (ctx) {
    var k = kcal, p = protein;
    return StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        Widget stepper(
          String name,
          String value,
          VoidCallback down,
          VoidCallback up,
        ) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(name, style: TempoType.label.c(c.text1))),
              TempoButton(
                '−',
                small: true,
                kind: ButtonKind.ghost,
                onTap: down,
              ),
              SizedBox(
                width: 96,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TempoType.titleM.c(c.text1).tnum,
                ),
              ),
              TempoButton('+', small: true, kind: ButtonKind.ghost, onTap: up),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change targets', style: TempoType.titleM.c(c.text1)),
            const SizedBox(height: 12),
            if (k != null)
              stepper(
                'Calories',
                '${_k(k!)} kcal',
                () => set(() => k = (k! - 50).clamp(1000, 5000)),
                () => set(() => k = (k! + 50).clamp(1000, 5000)),
              ),
            stepper(
              'Protein',
              '${_k(p)} g',
              () => set(() => p = (p - 5).clamp(30, 300)),
              () => set(() => p = (p + 5).clamp(30, 300)),
            ),
            const SizedBox(height: 12),
            TempoButton(
              'Save',
              expand: true,
              onTap: () => Navigator.pop(ctx, (k, p)),
            ),
          ],
        );
      },
    );
  },
);
