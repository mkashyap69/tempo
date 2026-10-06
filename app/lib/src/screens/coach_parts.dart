import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart';
import '../core/coach_service.dart';
import '../core/home_widgets.dart' show rescheduleNotifications;
import '../core/profile.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'longevity.dart';
import 'nav.dart';

final coachExtrasProvider = FutureProvider<CoachExtras>((ref) async {
  ref.watch(dbTickProvider);
  final t = await ref.watch(todayProvider.future);
  return loadCoachExtras(ref.watch(dbProvider), t);
});

/// Short status label for today's session chip.
String statusLabel(TodayData t) => switch (t.status) {
  sc.DayStatus.done => 'Done ✓',
  sc.DayStatus.doneEasier => 'Done, easier',
  sc.DayStatus.partial => 'Partly done',
  sc.DayStatus.pending =>
    t.plannedMinute == null ? 'Any time' : 'Planned ${fmtHm(t.plannedMinute!)}',
  sc.DayStatus.moved =>
    t.plannedMinute == null ? 'Moved' : 'Moved to ${fmtHm(t.plannedMinute!)}',
  sc.DayStatus.missedSlot => 'Not seen yet',
  sc.DayStatus.missedDay => 'Missed',
  sc.DayStatus.skipped => 'Skipped',
  sc.DayStatus.rest => 'Rest',
};

Color statusColor(BuildContext context, sc.DayStatus s) => switch (s) {
  sc.DayStatus.done || sc.DayStatus.doneEasier => context.s.recHigh,
  sc.DayStatus.missedDay => context.s.recLow,
  sc.DayStatus.missedSlot || sc.DayStatus.partial => context.s.recMid,
  _ => context.c.text2,
};

/// One-glyph status for the week row.
String statusGlyph(sc.DayStatus? s) => switch (s) {
  null => '·',
  sc.DayStatus.done || sc.DayStatus.doneEasier => '✓',
  sc.DayStatus.partial => '◐',
  sc.DayStatus.missedDay || sc.DayStatus.missedSlot => '✕',
  sc.DayStatus.skipped => '–',
  sc.DayStatus.rest => '○',
  sc.DayStatus.pending || sc.DayStatus.moved => '•',
};

Future<void> _afterChange(WidgetRef ref) async {
  HapticFeedback.selectionClick();
  await rescheduleNotifications(ref.read(dbProvider));
}

/// Buttons under today's session: move, skip, mark done, undo.
class SessionActions extends ConsumerWidget {
  const SessionActions(this.t, {super.key});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coach = CoachService(ref.read(dbProvider));
    final day = t.day;
    final pm = t.pmSlot;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final buttons = <Widget>[];
    void add(String label, Future<void> Function() go, {bool primary = false}) {
      buttons.add(
        TempoButton(
          label,
          small: true,
          expand: true,
          fontSize: 14,
          kind: primary ? ButtonKind.secondary : ButtonKind.ghost,
          onTap: () async {
            await go();
            await _afterChange(ref);
          },
        ),
      );
    }

    switch (t.status) {
      case sc.DayStatus.pending:
        if ((t.plannedMinute ?? 0) < pm && nowMin < pm) {
          add(
            'Move to ${fmtHm(pm)}',
            () => coach.setIntent(day, sc.Intent.moved, minute: pm, slot: 'pm'),
          );
        }
        add('Done already', () => coach.setIntent(day, sc.Intent.done));
        add('Skip', () => coach.setIntent(day, sc.Intent.skipped));
      case sc.DayStatus.moved:
        add('Done already', () => coach.setIntent(day, sc.Intent.done));
        add('Skip', () => coach.setIntent(day, sc.Intent.skipped));
      case sc.DayStatus.missedSlot || sc.DayStatus.partial:
        add('Done already', () => coach.setIntent(day, sc.Intent.done));
      case sc.DayStatus.skipped || sc.DayStatus.missedDay:
        if (t.intent != sc.Intent.planned) {
          add('Undo', () => coach.setIntent(day, sc.Intent.planned));
        }
      case _:
        if (t.intent == sc.Intent.done) {
          add('Undo', () => coach.setIntent(day, sc.Intent.planned));
        }
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final (i, b) in buttons.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: b),
        ],
      ],
    );
  }
}

/// "Missed this morning → 18:00 easy 30′" with Plan it / Skip.
class RescueCard extends ConsumerWidget {
  const RescueCard(this.t, {super.key});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final r = t.rescue;
    final coach = CoachService(ref.read(dbProvider));
    if (r.tier == sc.RescueTier.alreadyCovered) {
      return TempoCard(
        color: s.tintRecHigh,
        child: Text(
          'Your ${t.plan!.title.toLowerCase()} didn’t show up, but today’s strain already reached its target. Nothing to make up.',
          style: TempoType.bodyS.c(c.text1),
        ),
      );
    }
    if (!r.offered && t.state == sc.DayState.rest) {
      return TempoCard(
        child: Text(
          'Your ${t.plan!.title.toLowerCase()} didn’t show up — and today is a rest day now anyway, so there’s nothing to make up.',
          style: TempoType.bodyS.c(c.text2),
        ),
      );
    }
    if (!r.offered) {
      return TempoCard(
        child: Text(
          'Your ${t.plan!.title.toLowerCase()} didn’t show up, and there’s not enough time before bed for it to help. Let it go — tomorrow is planned as normal.',
          style: TempoType.bodyS.c(c.text2),
        ),
      );
    }
    final ses = r.session!;
    final eased = ses.key != t.plan!.key;
    final why = switch (r.tier) {
      sc.RescueTier.full when eased => 'Today is an easy day, so it comes back as aerobic work that still ends well before bed.',
      sc.RescueTier.full => 'The full session still ends well before bed.',
      sc.RescueTier.easier => 'Shorter and easier, so it ends an hour before bed and doesn’t cost tonight’s sleep.',
      _ =>
        'A short, gentle option — anything harder this late would cost sleep.',
    };
    return TempoCard(
      color: s.tintRecMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline('Still time today', color: s.recMid),
          const SizedBox(height: 8),
          Text(
            '${fmtHm(r.start!)} · ${ses.title} ${ses.minutes}′',
            style: TempoType.titleM.c(c.text1).tnum,
          ),
          const SizedBox(height: 4),
          Text(
            '${t.plan!.title} wasn’t seen this morning. $why Bedtime ${fmtHm(t.bedtimeMinute)}.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TempoButton(
                  'Plan it',
                  small: true,
                  expand: true,
                  onTap: () async {
                    await coach.setIntent(
                      t.day,
                      sc.Intent.moved,
                      minute: r.start,
                      slot: 'pm',
                      session:
                          ses.key == t.plan!.key &&
                              ses.minutes == t.plan!.minutes
                          ? null
                          : ses,
                    );
                    await _afterChange(ref);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TempoButton(
                  'Skip today',
                  small: true,
                  expand: true,
                  kind: ButtonKind.ghost,
                  onTap: () async {
                    await coach.setIntent(t.day, sc.Intent.skipped);
                    await _afterChange(ref);
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

/// Three or more missed days in a week: rebuild or keep.
class RealignCard extends ConsumerWidget {
  const RealignCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final db = ref.read(dbProvider);
    Future<void> dismiss() =>
        db.putSetting(Keys.realignDismissed, st.dateKey(DateTime.now()));
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Realign this week?'),
          const SizedBox(height: 8),
          Text(
            'A few sessions didn’t happen lately — that’s normal. Tempo can rebuild the rest of this week from today instead of carrying them.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TempoButton(
                'Rebuild from today',
                small: true,
                onTap: () async {
                  await db.putSetting(Keys.carried, '');
                  await CoachService(db)
                      .ensureWeek(DateTime.now(), rebuild: true);
                  await dismiss();
                  await _afterChange(ref);
                },
              ),
              TempoButton(
                'Keep as is',
                small: true,
                kind: ButtonKind.ghost,
                onTap: dismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Also today": the focus lever's actions plus tonight's bedtime.
class AlsoToday extends StatelessWidget {
  const AlsoToday(this.x, {super.key});
  final CoachExtras x;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final floor = x.floor;
    return Section(
      title: 'Also today',
      child: CardList(
        children: [
          for (final a in x.actions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  TempoIcon(
                    a.done ? TempoIcons.check : TempoIcons.dot,
                    size: 18,
                    color: a.done ? s.recHigh : c.text3,
                    stroke: a.done ? 2.25 : 4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: TempoType.label.c(c.text1)),
                        const SizedBox(height: 2),
                        Text(a.detail, style: TempoType.caption.c(c.text2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (floor != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  TempoIcon(
                    TempoIcons.dot,
                    size: 18,
                    color: c.text3,
                    stroke: 4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          floor.minutesShort > 0
                              ? '${floor.minutesShort}′ short of 150 this week'
                              : 'One more strength session this week',
                          style: TempoType.label.c(c.text1),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          floor.minutesShort > 0
                              ? 'A brisk 20′ walk on the days left closes it'
                              : '20′ of bodyweight work counts',
                          style: TempoType.caption.c(c.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Mon–Sun glyphs under the week bars.
class WeekStatusRow extends StatelessWidget {
  const WeekStatusRow(this.week, {super.key});
  final List<sc.DayStatus?> week;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label:
          'This week: ${week.where((s) => s == sc.DayStatus.done || s == sc.DayStatus.doneEasier).length} done, '
          '${week.where((s) => s == sc.DayStatus.missedDay).length} missed',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusGlyph(week[i]),
                textAlign: TextAlign.center,
                style: TempoType.label.c(
                  week[i] == null ? c.text3 : statusColor(context, week[i]!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Longevity focus in one line, opening Longevity.
class FocusSummary extends StatelessWidget {
  const FocusSummary(this.x, {super.key});
  final CoachExtras x;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = x.focus;
    return TempoCard(
      onTap: () => push(context, const LongevityScreen(standalone: true)),
      label: 'Longevity focus',
      child: Row(
        children: [
          TempoIcon(TempoIcons.longevity, size: 22, color: c.text1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f == null ? 'Pick a longevity focus' : leverName(f.lever),
                  style: TempoType.label.c(c.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  f == null
                      ? 'Coach can build your weeks around one Tempo Age lever'
                      : 'Week ${f.weekOn(DateTime.now())} of ${f.weeks} · the plan leans on it',
                  style: TempoType.caption.c(c.text2),
                ),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 18, color: c.text3, stroke: 2),
        ],
      ),
    );
  }
}

/// What an unplanned workout did to today's plan: counted, moved, or
/// credited while the session still stands. Offers the strength fix-up
/// when the band couldn't tell.
class SwapNote extends ConsumerWidget {
  const SwapNote(this.t, {super.key});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final plan = t.plan;
    final w = t.swap.by;
    if (plan == null || w == null) return const SizedBox.shrink();
    final did = sc.sessionFromDone(w).title;
    final String text;
    Color? tint;
    switch (t.swap.kind) {
      case sc.SwapKind.counted:
        if (plan.key == 'done' || w.sport == plan.sport) {
          return const SizedBox.shrink();
        }
        text = '$did counted as today’s ${plan.title.toLowerCase()}.';
        tint = s.tintRecHigh;
      case sc.SwapKind.stands:
        text = plan.sport == sc.Sport.strength
            ? '$did counted toward Zone 2 and steps. Strength is still today’s session — cardio doesn’t replace it.'
            : '$did counted toward your day. ${plan.title} is still on — it trains something different.';
      case sc.SwapKind.moved || sc.SwapKind.none:
        return const SizedBox.shrink();
    }
    final match = t.workouts
        .where((x) => st.fromTs(x.start) == w.start)
        .firstOrNull;
    return TempoCard(
      color: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TempoType.bodyS.c(c.text1)),
          if (plan.sport == sc.Sport.strength &&
              w.sport != sc.Sport.strength &&
              match != null) ...[
            const SizedBox(height: 8),
            TempoButton(
              'That was my strength session',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () async {
                await ref
                    .read(dbProvider)
                    .updateWorkout(
                      match.id,
                      const st.WorkoutsCompanion(
                        sport: Value('strength'),
                        title: Value('Strength'),
                        confirmed: Value(true),
                      ),
                    );
                await _afterChange(ref);
              },
            ),
          ],
        ],
      ),
    );
  }
}
