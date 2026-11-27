import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_proposal.dart';
import '../core/coach_service.dart';
import '../core/format.dart' show clock12;
import '../core/plan_changes.dart' show undoPlanChange;
import '../core/profile.dart' show Keys;
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import '../billing/pro.dart';

/// The coach's blue label, on everything the coach says (v3).
class CoachLabel extends StatelessWidget {
  const CoachLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: s.loadBuilding.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: TempoIcon(
            TempoIcons.heartRate,
            size: 12,
            color: s.loadBuilding,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Overline(text, color: s.loadBuilding)),
      ],
    );
  }
}

/// Today's planned session when it's still to do, else null.
sc.Session? openPlan(TodayData t) {
  final p = t.plan;
  if (p == null || p.isRest || t.pause != null) return null;
  return t.status == sc.DayStatus.pending ||
          t.status == sc.DayStatus.moved ||
          t.status == sc.DayStatus.missedSlot
      ? p
      : null;
}

/// v3 (0.8.0): "How's today looking?" under the call. Each reply opens a
/// preview; nothing changes until Use this.
class QuickReplyRow extends ConsumerWidget {
  const QuickReplyRow({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coach behaviour is Tempo Pro (launch plan §3).
    if (!ref.watch(proProvider)) return const SizedBox.shrink();
    final plan = openPlan(t);
    if (plan == null) return const SizedBox.shrink();
    final c = context.c;
    final replies = [
      sc.QuickReply.shortOnTime,
      sc.QuickReply.feelingFlat,
      if (sc.upForMoreAllowed(recovery: t.recovery, state: t.state))
        sc.QuickReply.upForMore,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(height: 1, color: c.line),
        const SizedBox(height: 12),
        Text('How’s today looking?', style: TempoType.bodyS.c(c.text2)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in replies)
              Pressable(
                key: ValueKey('reply-${r.name}'),
                label: sc.quickReplyLabel(r),
                onTap: () => showQuickReplySheet(context, ref, t, plan, r),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(TempoRadii.pill),
                    border: Border.all(color: c.lineStrong),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      sc.quickReplyLabel(r),
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The preview: what the reply would make of today's plan, then Use this
/// or Keep my plan. Use this swaps today's session the way any user swap
/// does (Plan changes lists it, Undo restores it).
Future<void> showQuickReplySheet(
  BuildContext context,
  WidgetRef ref,
  TodayData t,
  sc.Session plan,
  sc.QuickReply reply,
) {
  // Only times the session can actually be cut to (it never goes below
  // what still does its job), plus the shortest it goes.
  final shortest = sc.fitDay(plan, 1).minutes;
  final times = [
    for (final m in sc.quickReplyMinutes)
      if (m < plan.minutes && m >= shortest) m,
  ];
  var minutes = times.contains(30)
      ? 30
      : (times.isEmpty ? shortest : times.last);
  return showTempoSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.c, s = ctx.s;
        final o = sc.quickReplyOffer(
          plan,
          reply,
          minutes: minutes,
          recovery: t.recovery,
          state: t.state,
          maxMinutes: t.profile.maxMinutes,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            CoachLabel('Coach · ${sc.quickReplyLabel(reply).toLowerCase()}'),
            const SizedBox(height: 10),
            if (o == null)
              Text(
                reply == sc.QuickReply.shortOnTime
                    ? 'Today’s ${plan.title.toLowerCase()} is already ${plan.minutes} min, the shortest that still does its job.'
                    : 'Nothing to change today: keep the plan.',
                style: TempoType.body.c(c.text1),
              )
            else ...[
              Text(
                o.headline,
                key: const ValueKey('reply-headline'),
                style: TempoType.titleM.c(c.text1),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(TempoRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plan.title} · ${plan.minutes} min',
                      style: TempoType.bodyS.copyWith(
                        color: c.text3,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${o.to.title} · ${o.to.minutes} min',
                            key: const ValueKey('reply-to'),
                            style: TempoType.label.c(c.text1),
                          ),
                        ),
                        TempoBadge('new', small: true, color: s.loadBuilding),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o.to.structure,
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(o.why, style: TempoType.bodyS.c(c.text2)),
            ],
            if (reply == sc.QuickReply.shortOnTime && times.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'How much time have you got?',
                style: TempoType.caption.c(c.text2),
              ),
              const SizedBox(height: 8),
              TempoSegmented<int>(
                values: times,
                labels: [for (final m in times) '$m′'],
                selected: minutes,
                onChanged: (m) => setState(() => minutes = m),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (o != null) ...[
                  Expanded(
                    child: TempoButton(
                      'Use this',
                      expand: true,
                      onTap: () async {
                        final stamp = await _apply(ref, plan, o);
                        if (!ctx.mounted) return;
                        // Shown on the root overlay, so it outlives the
                        // sheet.
                        if (stamp != null) {
                          showTempoToast(
                            ctx,
                            'Today’s plan changed',
                            action: 'Undo',
                            onAction: () async {
                              await undoPlanChange(ref.read(dbProvider), stamp);
                              ref.invalidate(todayProvider);
                            },
                          );
                        }
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TempoButton(
                    'Keep my plan',
                    kind: ButtonKind.secondary,
                    expand: true,
                    onTap: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    ),
  );
}

/// Swaps today's session for [o]; returns the change's stamp for Undo.
Future<int?> _apply(WidgetRef ref, sc.Session plan, sc.ReplyOffer o) async {
  final db = ref.read(dbProvider);
  await CoachService(db)
      .swapToday(o.to, '${sc.quickReplyLabel(o.reply)}: ${o.headline}');
  // Feeling flat on a hard day: the coach brings the session back on the
  // next good morning (the same slot the morning adaptation uses).
  if (o.reply == sc.QuickReply.feelingFlat && plan.isHard) {
    await db.putSetting(Keys.carried, jsonEncode(plan.toJson()));
  }
  final row = await db.planDay(dayOf(DateTime.now()));
  ref.invalidate(todayProvider);
  return row?.adaptedAt;
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// v3 interactive coach 2 (0.9.0): what the morning adaptation would change,
/// asked first. Accept writes it (Undo in the toast and Plan changes);
/// Keep my plan drops it; unanswered, it applies at its deadline.
class CoachSuggestCard extends ConsumerWidget {
  const CoachSuggestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coach behaviour is Tempo Pro (launch plan §3).
    if (!ref.watch(proProvider)) return const SizedBox.shrink();
    final p = Proposal.parse(ref.watch(settingProvider(proposalKey)).value);
    if (p == null || p.changes.isEmpty) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final one = p.changes.length == 1 ? p.changes.first : null;
    String day(String date) => _days[DateTime.parse(date).weekday - 1];
    return Container(
      key: const ValueKey('coach-suggests'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .7],
          colors: [
            Color.alphaBlend(s.loadBuilding.withValues(alpha: .10), c.surface1),
            c.surface1,
          ],
        ),
        borderRadius: BorderRadius.circular(TempoRadii.lg),
        border: Border.all(color: s.loadBuilding.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: CoachLabel('Coach suggests')),
              Text(
                'applies at ${clock12(p.deadline)}',
                style: TempoType.caption.c(c.text3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            one != null
                ? 'Swap ${day(one.date)}’s ${one.fromTitle.toLowerCase()} for ${one.toTitle.toLowerCase()}.'
                : 'A change to ${p.changes.length} days this week.',
            style: TempoType.titleM.c(c.text1),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TempoRadii.md),
            ),
            child: Column(
              children: [
                for (final ch in p.changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            day(ch.date),
                            style: TempoType.bodyS.c(c.text2),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            ch.fromTitle,
                            style: TempoType.bodyS.copyWith(
                              color: c.text3,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ch.toTitle,
                            style: TempoType.bodyS.c(s.loadBuilding),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Why: ${p.why}', style: TempoType.bodyS.c(c.text2)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TempoButton(
                  'Accept',
                  expand: true,
                  onTap: () async {
                    final db = ref.read(dbProvider);
                    final stamp = await acceptProposal(db, p);
                    ref.invalidate(todayProvider);
                    if (!context.mounted) return;
                    showTempoToast(
                      context,
                      'Plan changed',
                      action: 'Undo',
                      onAction: () async {
                        await undoPlanChange(db, stamp);
                        ref.invalidate(todayProvider);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TempoButton(
                  'Keep my plan',
                  kind: ButtonKind.secondary,
                  expand: true,
                  onTap: () async {
                    await declineProposal(ref.read(dbProvider));
                    if (context.mounted) {
                      showTempoToast(context, 'Kept your plan');
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
