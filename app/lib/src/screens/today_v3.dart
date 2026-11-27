import 'package:flutter/material.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/day_story.dart';
import '../core/format.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'shared.dart';

/// v3 Today: the call as a card under the rings. The word, the sentence,
/// and the two signals that moved recovery most; tap for Why.
class CallCard extends StatelessWidget {
  const CallCard({
    super.key,
    required this.t,
    required this.noData,
    this.health = false,
    this.onWhy,
  });
  final TodayData t;
  final bool noData, health;
  final VoidCallback? onWhy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final call = callFor(t, noData: noData, health: health);
    final word = callWordFor(t, noData: noData, health: health);
    final tone = callColor(context, call.tone);
    final tinted = word != null;
    final chips = noData || t.calibrating
        ? const <Contributor>[]
        : ([
                for (final x in contributors(context, t))
                  if (x.effect != 0) x,
              ]..sort((a, b) => b.effect.abs().compareTo(a.effect.abs())))
              .take(2)
              .toList();
    return Pressable(
      label: 'Why today’s call',
      onTap: onWhy,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: c.surface1,
          gradient: tinted
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .75],
                  colors: [
                    Color.alphaBlend(tone.withValues(alpha: .13), c.surface1),
                    c.surface1,
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(TempoRadii.lg),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Overline('Today’s call', color: tinted ? tone : null),
                ),
                if (onWhy != null)
                  Text('Why? ›', style: TempoType.caption.c(c.text2)),
              ],
            ),
            if (word != null) ...[
              const SizedBox(height: 10),
              Text(
                sc.callWordLabel(word),
                key: const ValueKey('call-word'),
                style: TempoType.hero.copyWith(
                  fontSize: 52,
                  height: 1,
                  color: c.text1,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: call.lead,
                    style: TextStyle(color: tone),
                  ),
                  TextSpan(text: call.rest),
                ],
              ),
              style: TempoType.body.c(c.text1),
            ),
            if (call.note != null) ...[
              const SizedBox(height: 6),
              Text(call.note!, style: TempoType.bodyS.c(c.text2)),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final x in chips) _SignalChip(x)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip(this.x);
  final Contributor x;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.pill),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: x.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${x.name.replaceAll(', overnight', '')} ${x.effect > 0 ? 'helped' : 'held it back'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TempoType.caption.copyWith(
                color: c.text1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The inputs [dayStory] needs, from Today's data.
List<StoryEvent> storyFor(TodayData t, DateTime now) {
  int minuteOf(DateTime d) => d.hour * 60 + d.minute;
  final end = t.score?.sleepEnd;
  final today = [
    for (final w in t.workouts)
      if (sameDay(st.fromTs(w.start), now))
        (minuteOf(st.fromTs(w.start)), minuteOf(st.fromTs(w.end)), w.title),
  ];
  final p = t.plan;
  final pending =
      p != null &&
      !p.isRest &&
      (t.status == sc.DayStatus.pending ||
          t.status == sc.DayStatus.moved ||
          t.status == sc.DayStatus.missedSlot);
  return dayStory(
    nowMinute: minuteOf(now),
    bedtimeMinute: t.bedtimeMinute,
    wakeMinute: end == null ? null : minuteOf(st.fromTs(end)),
    sleptHours: t.slept,
    workouts: today,
    planTitle: pending ? p.title : null,
    plannedMinute: pending ? t.plannedMinute : null,
  );
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// v3 Today: "Your day so far": what's happened and what's ahead.
class DaySoFarCard extends StatelessWidget {
  const DaySoFarCard({super.key, required this.t, this.onTimeline});
  final TodayData t;
  final VoidCallback? onTimeline;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final events = storyFor(t, appNow());
    Color dot(StoryEvent e) => switch (e.kind) {
      StoryKind.wake => s.sleepChannel,
      StoryKind.workout => s.strain[2],
      StoryKind.planned => s.strain[2],
      StoryKind.windDown || StoryKind.bedtime => s.sleepChannel,
    };
    return TempoCard(
      label: 'Your day so far',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Your day so far')),
              if (onTimeline != null)
                Pressable(
                  label: 'Day timeline',
                  onTap: onTimeline,
                  child: Text(
                    'Timeline ›',
                    style: TempoType.caption.c(c.text2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, e) in events.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 12,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e.done ? dot(e) : null,
                            border: e.done
                                ? null
                                : Border.all(color: c.text3, width: 2),
                          ),
                        ),
                        if (i < events.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.only(top: 4),
                              color: c.line,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            style: TempoType.bodyS.c(
                              e.done ? c.text1 : c.text2,
                            ),
                          ),
                          if (e.sub != null)
                            Text(e.sub!, style: TempoType.caption.c(c.text3)),
                        ],
                      ),
                    ),
                  ),
                  if (e.minute != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: Text(
                        clock12(e.minute! % 1440),
                        style: TempoType.caption.c(c.text3).tnum,
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

/// What Today's Next up card is built from.
sc.NextUp? nextUpFor(TodayData t, DateTime now) {
  final p = t.plan;
  final planOpen =
      p != null &&
      !p.isRest &&
      (t.status == sc.DayStatus.pending ||
          t.status == sc.DayStatus.moved ||
          t.status == sc.DayStatus.missedSlot);
  final likes = t.profile.likes;
  return sc.nextUp(
    nowMinute: now.hour * 60 + now.minute,
    bedtimeMinute: t.bedtimeMinute,
    bedtime: clock12(t.bedtimeMinute),
    strain: t.strain,
    target: t.target,
    planOpen: planOpen,
    hrRest: t.rhrBase?.mean ?? 60,
    hrMax: t.profile.effectiveMaxHr.toDouble(),
    likes: likes.contains(sc.Sport.cycling) && !likes.contains(sc.Sport.running)
        ? sc.Sport.cycling
        : sc.Sport.running,
    needHours: t.needTonight > 0 ? t.needTonight : null,
    forecast: t.forecast,
  );
}

/// v3 Today (0.7.0): one card under the plan that changes with the day.
/// Before mid-afternoon, the effort today has left and what would fill it;
/// after, tonight's bedtime and what tomorrow looks like. Nothing when
/// there's nothing to say.
class NextUpCard extends StatelessWidget {
  const NextUpCard({super.key, required this.t, this.onTap});
  final TodayData t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = nextUpFor(t, appNow());
    if (n == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final tone = n.kind == sc.NextUpKind.room ? s.strain[2] : s.sleepChannel;
    return TempoCard(
      key: const ValueKey('next-up'),
      label: n.title,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(
            n.kind == sc.NextUpKind.room ? 'Room today' : 'Tonight',
            color: tone,
          ),
          const SizedBox(height: 8),
          Text(n.title, style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(n.body, style: TempoType.bodyS.c(c.text2)),
        ],
      ),
    );
  }
}
