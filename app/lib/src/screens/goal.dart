import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/block_service.dart';
import '../core/coach_service.dart';
import '../core/format.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// The goal and this week of it (null week = outside the block).
final blockInfoProvider = dbQuery<(sc.TrainingBlock?, sc.BlockWeek?)>((
  db,
  ref,
) async {
  final b = await loadBlock(db);
  if (b == null) return (null, null);
  return (b, await blockWeekFor(db, mondayOf(DateTime.now())));
});

/// Race weeks offered when picking an event date.
const eventWeeks = [4, 5, 6, 8, 10, 12, 14, 16, 20, 24];

String _callLine(sc.WeekCall? c) => switch (c) {
  sc.WeekCall.stepUp => 'Last week went well, so this one steps up.',
  sc.WeekCall.hold => 'Last week was patchy, so this one holds steady.',
  sc.WeekCall.stepBack => 'Last week was hard on you, so this one steps back.',
  null => 'Volume grows each week you handle well.',
};

/// Training goal: what the plan is building toward, and where you are.
class GoalCard extends ConsumerWidget {
  const GoalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final info = ref.watch(blockInfoProvider).value;
    if (info == null) return const SizedBox.shrink();
    final (b, w) = info;
    final String title, sub;
    if (b == null) {
      title = 'No training goal';
      sub =
          'The same week every week. Set a goal and the plan builds, '
          'with a lighter week every 4th.';
    } else if (w == null) {
      title = goalName(b);
      sub = b.isEvent && DateTime.now().isAfter(b.event!)
          ? 'Race done. Set a new goal to keep building.'
          : 'Starts next week.';
    } else {
      final pct = ((w.volume - 1) * 100).round();
      title = goalName(b);
      sub = [
        b.isEvent
            ? 'Week ${w.index + 1} of ${w.weeks} · ${sc.phaseName(w.phase)}'
            : 'Week ${w.index + 1} · ${sc.phaseName(w.phase)}',
        'volume ${pct >= 0 ? '+' : '−'}${pct.abs()}%',
      ].join(' · ');
    }
    return TempoCard(
      onTap: () => pickGoal(context, ref, b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('Training goal'),
          const SizedBox(height: 8),
          Text(title, style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(sub, style: TempoType.bodyS.c(c.text2).tnum),
          if (w != null && w.phase != sc.Phase.race) ...[
            const SizedBox(height: 4),
            Text(_callLine(w.lastCall), style: TempoType.caption.c(c.text3)),
          ],
        ],
      ),
    );
  }

  static String goalName(sc.TrainingBlock b) => b.isEvent
      ? '${sc.goalName(b.goal)} · ${dayShort(b.event!)}'
      : sc.goalName(b.goal);
}

/// Picks a goal (and an event's week), saves it and rebuilds this week.
Future<void> pickGoal(
  BuildContext context,
  WidgetRef ref,
  sc.TrainingBlock? current,
) async {
  final g = await pickOption<String>(
    context,
    title: 'What are you training for?',
    options: ['none', for (final g in sc.BlockGoal.values) g.name],
    label: (o) => o == 'none'
        ? 'No goal (same week every week)'
        : sc.BlockGoal.values.byName(o) == sc.BlockGoal.open
        ? 'Get fitter (keeps building)'
        : sc.goalName(sc.BlockGoal.values.byName(o)),
    selected: current?.goal.name ?? 'none',
  );
  if (g == null || !context.mounted) return;
  final db = ref.read(dbProvider);
  final goal = g == 'none' ? null : sc.BlockGoal.values.byName(g);
  DateTime? event;
  if (goal != null && goal != sc.BlockGoal.open) {
    final sunday = mondayOf(DateTime.now()).add(const Duration(days: 6));
    DateTime raceOn(int weeks) => sunday.add(Duration(days: 7 * (weeks - 1)));
    final weeks = await pickOption<int>(
      context,
      title: 'When is it?',
      options: eventWeeks,
      label: (n) => '${dayShort(raceOn(n))} · $n weeks',
    );
    if (weeks == null || !context.mounted) return;
    event = raceOn(weeks);
  }
  await saveBlock(db, goal, event: event);
  if (context.mounted) {
    showTempoToast(
      context,
      goal == null
          ? 'Goal cleared · plan rebuilt'
          : 'Plan rebuilt for your goal',
    );
  }
}
