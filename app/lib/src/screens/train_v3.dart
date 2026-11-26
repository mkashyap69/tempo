import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../core/profile.dart' show sportLabel;
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'add_activity.dart';
import 'nav.dart';
import 'plan_changes.dart';
import 'strength_log.dart';

/// v3 Train: the latest change to the plan, in one card that opens the log.
class PlanChangesSummary extends ConsumerWidget {
  const PlanChangesSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(planChangesProvider).value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final r = rows.first;
    final n = rows.length;
    return TempoCard(
      label: 'Plan changes',
      onTap: () => push(context, const PlanChangesScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Overline(
                  n == 1 ? 'Plan changes · 1' : 'Plan changes · $n',
                  color: s.loadBuilding,
                ),
              ),
              Text('All ›', style: TempoType.caption.c(c.text2)),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${dayShort(r.day)}: ',
                  style: TextStyle(color: c.text2),
                ),
                if (r.from != null) TextSpan(text: '${r.from} → '),
                TextSpan(text: r.skipped && r.from == null ? 'skipped' : r.to),
              ],
            ),
            style: TempoType.bodyS.c(c.text1),
          ),
          const SizedBox(height: 2),
          Text(
            r.why,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TempoType.caption.c(c.text2),
          ),
          if (r.canUndo) ...[
            const SizedBox(height: 4),
            Text(
              'Undo is still available.',
              style: TempoType.caption.c(c.text3),
            ),
          ],
        ],
      ),
    );
  }
}

/// v3 Train: how fresh legs and upper body are, in words. Shown once there
/// are lifts or runs to judge from.
class FreshnessMini extends ConsumerWidget {
  const FreshnessMini({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(freshnessProvider).value;
    if (f == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    (String, Color) word(double v) => v >= 80
        ? ('Fresh', s.recHigh)
        : v >= 50
        ? ('Recovering', s.recMid)
        : ('Tired', s.recLow);
    Widget tile(String name, double v) {
      final (w, col) = word(v);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(TempoRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TempoType.caption.c(c.text2)),
              const SizedBox(height: 2),
              Text(w, style: TempoType.label.c(col)),
              Text('${v.round()} %', style: TempoType.caption.c(c.text3).tnum),
            ],
          ),
        ),
      );
    }

    return TempoCard(
      label: 'Strength freshness',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('Strength'),
          const SizedBox(height: 10),
          Row(
            children: [
              tile('Legs', sc.lowerFreshness(f)),
              const SizedBox(width: 8),
              tile('Upper body', sc.upperFreshness(f)),
            ],
          ),
        ],
      ),
    );
  }
}

final _quickProvider = FutureProvider.autoDispose<List<sc.Sport>>(
  (ref) => quickStartSportsFor(ref),
);

/// v3 Train: one-tap starts, the sports you do most, a lift, a past one.
class QuickStartRow extends ConsumerWidget {
  const QuickStartRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final sports = ref.watch(_quickProvider).value ?? const <sc.Sport>[];
    Widget chip(String label, VoidCallback onTap) => Pressable(
      label: label,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(TempoRadii.pill),
          border: Border.all(color: c.line),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: TempoType.label.c(c.text1)),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('Quick start'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in sports)
              chip(sportLabel(s), () => openLive(context, ref, sport: s)),
            chip(
              'Log strength',
              () => push(context, const StrengthLogScreen()),
            ),
            chip(
              'Log a past one',
              () => push(context, const AddActivityScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
