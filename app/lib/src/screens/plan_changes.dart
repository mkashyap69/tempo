import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/plan_changes.dart';
import '../core/coach_service.dart' show dayOf;
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// The last four weeks and the rest of this one, newest first.
final planChangesProvider = FutureProvider<List<PlanChangeRow>>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final today = dayOf(DateTime.now());
  final rows = await db.planBetween(
    today.subtract(const Duration(days: 28)),
    today.add(const Duration(days: 7)),
  );
  return planChanges(rows, today: today);
});

/// v3 Plan changes: what the coach (or you) changed, and why.
class PlanChangesScreen extends ConsumerWidget {
  const PlanChangesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rows = ref.watch(planChangesProvider).value;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Plan changes'),
        Text(
          'Every day that differs from what was first planned, with the reason. Undo puts every day of a change back to its first plan.',
          style: TempoType.bodyS.c(c.text2),
        ),
        if (rows == null)
          const SizedBox(height: 120)
        else if (rows.isEmpty)
          const TempoEmpty(
            'No changes in the last four weeks. The plan has run as first set.',
          )
        else
          for (final r in rows) PlanChangeTile(r),
      ],
    );
  }
}

class PlanChangeTile extends ConsumerWidget {
  const PlanChangeTile(this.r, {super.key});
  final PlanChangeRow r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final who = r.by == ChangeBy.coach ? 'Coach' : 'You';
    final undo = r.canUndo && (r.stamp != null || r.skipped);
    return TempoCard(
      label: '${dayShort(r.day)}: ${r.why}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dayShort(r.day),
                  style: TempoType.caption.c(c.text2),
                ),
              ),
              TempoBadge(
                r.skipped ? '$who · skipped' : who,
                small: true,
                color: r.by == ChangeBy.coach ? s.loadBuilding : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                if (r.from != null) ...[
                  TextSpan(
                    text: r.from,
                    style: TextStyle(
                      color: c.text3,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const TextSpan(text: '  →  '),
                ],
                TextSpan(text: r.to),
              ],
            ),
            style: TempoType.body.c(c.text1),
          ),
          const SizedBox(height: 4),
          Text(r.why, style: TempoType.bodyS.c(c.text2)),
          if (r.together.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Changed together with ${r.together.map(dayShort).join(', ')}.',
              style: TempoType.caption.c(c.text3),
            ),
          ],
          if (undo) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TempoButton(
                r.skipped && r.stamp == null ? 'Plan it again' : 'Undo',
                small: true,
                fontSize: 14,
                kind: ButtonKind.secondary,
                onTap: () async {
                  final db = ref.read(dbProvider);
                  final List<DateTime> days;
                  if (r.stamp != null) {
                    days = await undoPlanChange(db, r.stamp!);
                  } else {
                    await undoSkip(db, r.day);
                    days = [r.day];
                  }
                  ref.invalidate(todayProvider);
                  if (context.mounted) {
                    showTempoToast(
                      context,
                      'Back to the first plan: ${days.map(dayShort).join(', ')}',
                    );
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
