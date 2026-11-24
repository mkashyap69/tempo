import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart' show stepsToday;
import '../core/food.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'food.dart';
import 'nav.dart';

/// Today's targets (D2, decisions.md 2026-11-24): what's left today in
/// one line, unfolding to the list. Data ticks what it can; a habit is
/// ticked by hand and writes its Journal entry.
final dayTargetsProvider = FutureProvider<List<sc.DayTarget>>((ref) async {
  ref.watch(dbTickProvider);
  final t = await ref.watch(todayProvider.future);
  return dayTargetsFor(ref.read(dbProvider), t);
});

Future<List<sc.DayTarget>> dayTargetsFor(
  st.TempoDb db,
  TodayData t, {
  DateTime? now,
}) async {
  final n = now ?? appNow();
  final p = t.profile;
  final habit = sc.goalHabit(p.goal);
  final answer = [
    for (final j in await db.journalFor(t.day))
      if (j.tag == habit.key) j.value,
  ];
  double? protein, proteinTarget;
  if (habit.key == 'high_protein') {
    final intake = await loadIntakeToday(db, now: n);
    protein = intake.protein;
    if (protein != null) {
      proteinTarget =
          (await loadSavedFood(db))?.protein ??
          sc
              .foodTargets(goal: p.goal, weightKg: p.weightKg, male: p.male)
              .protein;
    }
  }
  final plan = t.plan;
  final rest = t.restDay || t.state == sc.DayState.rest;
  int? steps;
  try {
    steps = await stepsToday(db, n);
  } catch (_) {}
  return sc.dayTargets(
    sc.DayTargetsInput(
      goal: p.goal,
      weightKg: p.weightKg,
      stepGoal: p.effectiveStepGoal,
      bedMinute: t.bedtimeMinute,
      wakeMinute: t.wakeMinute,
      sessionTitle: rest || plan == null || plan.isRest ? null : plan.title,
      sessionMinutes: plan?.minutes,
      status: t.status,
      steps: steps,
      habitAnswer: answer.isEmpty ? null : answer.last,
      proteinGrams: protein,
      proteinTarget: proteinTarget,
    ),
  );
}

String targetGroup(sc.TargetKind k, String? journalKey) => switch (k) {
  sc.TargetKind.session => 'Train',
  sc.TargetKind.steps => 'Move',
  sc.TargetKind.habit => journalKey == 'high_protein' ? 'Food' : 'Body',
  sc.TargetKind.sleep => 'Sleep',
};

class DayTargetsCard extends ConsumerStatefulWidget {
  const DayTargetsCard({super.key, required this.day});
  final DateTime day;

  @override
  ConsumerState<DayTargetsCard> createState() => _DayTargetsCardState();
}

class _DayTargetsCardState extends ConsumerState<DayTargetsCard> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(dayTargetsProvider).value;
    if (ts == null || ts.isEmpty) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final sum = sc.summarise(ts);
    final next = sum.next;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            label: _open ? 'Hide today’s targets' : 'Show today’s targets',
            onTap: () => setState(() => _open = !_open),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Overline(
                        'Today’s targets · ${sum.done} of ${sum.total}',
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? -.25 : .25,
                      duration: const Duration(milliseconds: 180),
                      child: TempoIcon(
                        TempoIcons.chevron,
                        size: 18,
                        color: c.text3,
                        stroke: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  next == null
                      ? 'Every target met today'
                      : 'Up next: ${next.title}',
                  style: TempoType.titleM.c(c.text1),
                ),
                const SizedBox(height: 12),
                Bar(
                  fraction: sum.share,
                  color: sum.next == null ? s.recHigh : c.text1,
                  height: 4,
                ),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            for (final (i, x) in ts.indexed) ...[
              if (i > 0) const Hair(),
              _TargetRow(x: x, day: widget.day),
            ],
          ],
        ],
      ),
    );
  }
}

class _TargetRow extends ConsumerWidget {
  const _TargetRow({required this.x, required this.day});
  final sc.DayTarget x;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final hand = !x.auto && x.journalKey != null;
    final skipped = x.state == sc.TargetState.skipped;
    Future<void> toggle() async {
      await ref.read(dbProvider).setJournal(day, x.journalKey!, !x.done);
      ref.invalidate(dayTargetsProvider);
    }

    final food = x.journalKey == 'high_protein';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                targetGroup(x.kind, x.journalKey),
                style: TempoType.caption.c(c.text2),
              ),
            ),
          ),
          Pressable(
            label: hand
                ? (x.done ? 'Untick ${x.title}' : 'Tick ${x.title}')
                : x.title,
            onTap: hand ? toggle : null,
            child: _Box(done: x.done, hand: hand, skipped: skipped),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Pressable(
              label: x.title,
              onTap: food ? () => push(context, const FoodScreen()) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.title,
                    style: TempoType.label
                        .c(x.done || skipped ? c.text3 : c.text1)
                        .copyWith(
                          decoration: x.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hand && !x.done ? '${x.sub} · tap the box' : x.sub,
                    style: TempoType.caption.c(c.text2).tnum,
                  ),
                ],
              ),
            ),
          ),
          if (food)
            TempoIcon(TempoIcons.chevron, size: 16, color: c.text3, stroke: 2),
        ],
      ),
    );
  }
}

/// Filled with a tick when done; dashed when it waits for your tick; plain
/// when data ticks it.
class _Box extends StatelessWidget {
  const _Box({required this.done, required this.hand, required this.skipped});
  final bool done, hand, skipped;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const size = 26.0;
    if (done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.text1,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: TempoIcon(
            TempoIcons.check,
            size: 16,
            color: c.bg,
            stroke: 2.5,
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BoxPainter(
          color: skipped ? c.line : c.lineStrong,
          dashed: hand,
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7),
    ).deflate(.8);
    if (!dashed) {
      canvas.drawRRect(r, p);
      return;
    }
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 3.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => o.color != color || o.dashed != dashed;
}
