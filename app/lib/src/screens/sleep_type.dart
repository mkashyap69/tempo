import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart' show dayOf;
import '../core/format.dart';
import '../core/sleep_coach.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';

final sleepTypeProvider = dbQuery((db, _) => loadSleepType(db));
final sleepPlanProvider = dbQuery((db, _) => loadSleepPlan(db));
final suggestedFocusProvider = dbQuery((db, _) => suggestedFocus(db));

/// A lark, dove or owl, drawn in the sleep colours.
class BirdMark extends StatelessWidget {
  const BirdMark(this.bird, {super.key, this.size = 96});
  final sc.Bird bird;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'A ${bird.name}',
    child: CustomPaint(
      size: Size.square(size),
      painter: _BirdPainter(
        bird,
        bg: context.s.tintSleep,
        body: context.s.sleepDeep,
        belly: context.s.sleepChannel,
        eye: context.c.surface1,
        pupil: context.c.text1,
        beak: context.s.recMid,
      ),
    ),
  );
}

class _BirdPainter extends CustomPainter {
  _BirdPainter(
    this.bird, {
    required this.bg,
    required this.body,
    required this.belly,
    required this.eye,
    required this.pupil,
    required this.beak,
  });
  final sc.Bird bird;
  final Color bg, body, belly, eye, pupil, beak;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100;
    Paint p(Color c) => Paint()..color = c;
    final cx = 50 * u;
    canvas.drawCircle(Offset(cx, cx), 49 * u, p(bg));
    final owl = bird == sc.Bird.owl;
    // Ear tufts (owl) or a crest (lark).
    if (owl) {
      for (final s in [-1, 1]) {
        final path = Path()
          ..moveTo(cx + s * 14 * u, 30 * u)
          ..lineTo(cx + s * 26 * u, 14 * u)
          ..lineTo(cx + s * 27 * u, 34 * u)
          ..close();
        canvas.drawPath(path, p(body));
      }
    } else if (bird == sc.Bird.lark) {
      final crest = Path()
        ..moveTo(cx - 4 * u, 24 * u)
        ..lineTo(cx + 2 * u, 10 * u)
        ..lineTo(cx + 8 * u, 24 * u)
        ..close();
      canvas.drawPath(crest, p(body));
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, 58 * u),
        width: 56 * u,
        height: 62 * u,
      ),
      p(body),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, 68 * u),
        width: 32 * u,
        height: 36 * u,
      ),
      p(belly),
    );
    final eyeR = (owl ? 10 : 6) * u;
    final gap = (owl ? 11 : 10) * u;
    for (final s in [-1, 1]) {
      final c = Offset(cx + s * gap, 46 * u);
      canvas.drawCircle(c, eyeR, p(eye));
      canvas.drawCircle(c.translate(0, u), eyeR * .45, p(pupil));
    }
    final b = Path()
      ..moveTo(cx - 4 * u, 55 * u)
      ..lineTo(cx + 4 * u, 55 * u)
      ..lineTo(cx, 62 * u)
      ..close();
    canvas.drawPath(b, p(beak));
    if (owl) {
      // A moon over the owl's shoulder.
      final m = Offset(80 * u, 22 * u);
      canvas.drawCircle(m, 8 * u, p(body));
      canvas.drawCircle(m.translate(4 * u, -3 * u), 7 * u, p(bg));
    } else if (bird == sc.Bird.lark) {
      final s = Offset(80 * u, 22 * u);
      canvas.drawCircle(s, 6 * u, p(beak));
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(
          s + Offset(math.cos(a), math.sin(a)) * 9 * u,
          s + Offset(math.cos(a), math.sin(a)) * 12 * u,
          p(beak)..strokeWidth = 1.5 * u,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BirdPainter o) =>
      o.bird != bird || o.bg != bg || o.body != body;
}

/// Mid-sleep as a clock ("05:10").
String midClock(int m) => fmtHm(((m % 1440) + 1440) % 1440);

/// Sleep: your type (lark, dove or owl; steady to restless), what it means,
/// one tip and the way into the plan.
class SleepTypeCard extends ConsumerWidget {
  const SleepTypeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final async = ref.watch(sleepTypeProvider);
    if (!async.hasValue) return const SizedBox.shrink();
    final t = async.value;
    final plan = ref.watch(sleepPlanProvider).value;
    if (t == null) {
      return TempoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Your sleep type'),
            const SizedBox(height: 8),
            Text(
              'Lark, dove or owl? Your type shows after '
              '${sc.sleepTypeNights} nights.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ),
      );
    }
    Widget chip(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TempoRadii.pill),
      ),
      child: Text(
        text,
        style: TempoType.caption.copyWith(fontWeight: FontWeight.w600).c(fg),
      ),
    );
    return TempoCard(
      label: 'Your sleep type',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('Your sleep type'),
          const SizedBox(height: 12),
          Row(
            children: [
              BirdMark(t.bird, size: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: TempoType.titleL.c(c.text1)),
                    const SizedBox(height: 4),
                    Text(
                      sc.sleepTypeLine(t),
                      style: TempoType.bodyS.c(c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip('Mid-sleep ${midClock(t.midSleep)}', c.text1, c.surface2),
              chip(
                switch (t.steadiness) {
                  sc.Steadiness.steady => 'Regular',
                  sc.Steadiness.wandering => 'Fairly regular',
                  sc.Steadiness.restless => 'Irregular',
                },
                t.steadiness == sc.Steadiness.steady ? s.recHigh : s.recMid,
                t.steadiness == sc.Steadiness.steady
                    ? s.tintRecHigh
                    : s.tintRecMid,
              ),
              chip(
                t.longSleeper
                    ? 'Long sleeper · ${hmShort(t.hours)}'
                    : t.shortSleeper
                    ? 'Short sleeper · ${hmShort(t.hours)}'
                    : '${hmShort(t.hours)} a night',
                c.text1,
                c.surface2,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(sc.sleepTypeTip(t), style: TempoType.bodyS.c(c.text1)),
          const SizedBox(height: 12),
          TempoButton(
            plan == null || plan.finished
                ? 'Start a 21-day sleep plan'
                : 'Sleep plan · day ${plan.day + 1} of ${sc.sleepPlanDays}',
            expand: true,
            kind: plan == null || plan.finished
                ? ButtonKind.primary
                : ButtonKind.secondary,
            onTap: () => push(context, const SleepPlanScreen()),
          ),
          const SizedBox(height: 8),
          Text(
            'From your last ${t.nights} nights; updates as you sleep.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}

/// Today: the sleep plan in one row, while one runs.
class SleepPlanRow extends ConsumerWidget {
  const SleepPlanRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(sleepPlanProvider).value;
    if (v == null || v.finished) return const SizedBox.shrink();
    final c = context.c;
    final done = v.today.where((h) => h.state == HabitState.done).length;
    return TempoCard(
      label: 'Sleep plan',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => push(context, const SleepPlanScreen()),
      child: Row(
        children: [
          BirdMark(sc.Bird.dove, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sleep plan · day ${v.day + 1} of ${sc.sleepPlanDays}',
                  style: TempoType.label.c(c.text1),
                ),
                Text(
                  '$done of ${v.today.length} habits today · '
                  '${v.plan.weeks[v.week].habit.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          Text('›', style: TempoType.titleM.c(c.text3)),
        ],
      ),
    );
  }
}

/// The 21-day sleep plan: start it (focus and times), then today's
/// habits, the three weeks and how the focus metric moved.
class SleepPlanScreen extends ConsumerWidget {
  const SleepPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(sleepPlanProvider);
    final t = ref.watch(todayProvider).value;
    if (!v.hasValue || t == null) {
      return Scaffold(backgroundColor: context.c.bg);
    }
    final plan = v.value;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Sleep plan'),
        if (plan == null || plan.finished)
          _StartPlan(t: t, done: plan)
        else
          ..._active(context, ref, plan),
      ],
    );
  }

  List<Widget> _active(BuildContext context, WidgetRef ref, SleepPlanView v) {
    final c = context.c, s = context.s;
    final db = ref.read(dbProvider);
    final weeks = v.plan.weeks;
    final unit = switch (v.plan.focus) {
      sc.SleepFocus.regularity => (double x) => '${x.round()}%',
      sc.SleepFocus.duration => (double x) => hmShort(x),
      sc.SleepFocus.fallingAsleep => (double x) => '${x.round()} min',
    };
    final metric = switch (v.plan.focus) {
      sc.SleepFocus.regularity => 'Bedtimes within 25 min',
      sc.SleepFocus.duration => 'Hours asleep',
      sc.SleepFocus.fallingAsleep => 'Time to fall asleep',
    };
    return [
      TempoCard(
        color: s.tintSleep,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Overline(
                    '${sc.sleepFocusName(v.plan.focus)} · 21 days',
                  ),
                ),
                Text(
                  'Day ${v.day + 1}',
                  style: TempoType.caption.c(c.text2).tnum,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Week ${v.week + 1}: ${weeks[v.week].habit.title.toLowerCase()}',
              style: TempoType.titleM.c(c.text1),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (i, d) in v.days.indexed) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: switch (d) {
                          PlanDayState.kept => s.sleepDeep,
                          PlanDayState.missed => s.sleepChannel.withValues(
                            alpha: .35,
                          ),
                          PlanDayState.today => c.text1,
                          PlanDayState.ahead => c.trackOff,
                        },
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              v.day == 0
                  ? 'Day 1. A day counts when you keep two thirds of its habits.'
                  : '${v.kept} of ${v.day} days kept so far.',
              style: TempoType.caption.c(c.text2),
            ),
          ],
        ),
      ),
      Section(
        title: 'Today',
        child: CardList(
          children: [
            for (final h in v.today)
              _HabitRow(
                h: h,
                onTick: h.habit.auto
                    ? null
                    : () => tickHabit(
                        db,
                        dayOf(DateTime.now()),
                        h.habit.id,
                        h.state != HabitState.done,
                      ),
              ),
          ],
        ),
      ),
      Section(
        title: 'The three weeks',
        child: CardList(
          children: [
            for (final (i, w) in weeks.indexed)
              ListRow(
                'Week ${i + 1} · ${w.habit.title}',
                sub: w.why,
                chevron: false,
                trailing: i == v.week
                    ? TempoBadge(
                        'Now',
                        color: c.textInverse,
                        background: c.text1,
                      )
                    : null,
              ),
          ],
        ),
      ),
      TempoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('So far'),
            const SizedBox(height: 8),
            Text(metric, style: TempoType.bodyS.c(c.text2)),
            const SizedBox(height: 4),
            Text(
              v.before == null && v.since == null
                  ? 'Not enough nights yet'
                  : '${v.before == null ? '–' : unit(v.before!)} → ${v.since == null ? '…' : unit(v.since!)}',
              style: TempoType.titleL.c(c.text1).tnum,
            ),
            const SizedBox(height: 6),
            Text(
              v.since == null
                  ? 'The 14 nights before the plan, against the nights since. '
                        'The comparison shows after 3 nights.'
                  : 'The 14 nights before the plan against the '
                        '${v.sinceNights} since. Early numbers move a lot; '
                        'the result that counts is day 21.',
              style: TempoType.caption.c(c.text3),
            ),
          ],
        ),
      ),
      TempoButton(
        'End the plan',
        kind: ButtonKind.ghost,
        expand: true,
        onTap: () async {
          final ok = await confirmSheet(
            context,
            title: 'End the sleep plan?',
            body:
                'Your ticks for this plan are cleared. You can start a new '
                'one any time.',
            action: 'End plan',
            danger: true,
          );
          if (ok) await endSleepPlan(db);
        },
      ),
    ];
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.h, this.onTick});
  final HabitToday h;
  final VoidCallback? onTick;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final done = h.state == HabitState.done;
    final missed = h.state == HabitState.missed;
    final mark = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? s.recHigh : null,
        border: done ? null : Border.all(color: c.lineStrong, width: 2),
      ),
      child: done ? Text('✓', style: TempoType.label.c(c.textInverse)) : null,
    );
    return Pressable(
      label: '${h.habit.title}${done ? ', done' : ''}',
      onTap: onTick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            mark,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.habit.title, style: TempoType.label.c(c.text1)),
                  Text(
                    h.note ?? h.habit.detail,
                    style: TempoType.bodyS.c(c.text2),
                  ),
                ],
              ),
            ),
            if (missed)
              Text('Missed', style: TempoType.caption.c(s.recMid))
            else if (h.habit.auto && !done)
              Text('Auto', style: TempoType.caption.c(c.text3))
            else if (!h.habit.auto)
              Text(done ? 'Undo' : 'Done', style: TempoType.label.c(c.text2)),
          ],
        ),
      ),
    );
  }
}

class _StartPlan extends ConsumerStatefulWidget {
  const _StartPlan({required this.t, this.done});
  final TodayData t;
  final SleepPlanView? done;

  @override
  ConsumerState<_StartPlan> createState() => _StartPlanState();
}

class _StartPlanState extends ConsumerState<_StartPlan> {
  sc.SleepFocus? _focus;
  int? _wake;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final suggested = ref.watch(suggestedFocusProvider).value;
    final focus = _focus ?? suggested ?? sc.SleepFocus.regularity;
    final wake = _wake ?? widget.t.wakeMinute;
    final need = widget.t.needTonight;
    final bed = sc.bedtimeMinute(need, wake);
    final done = widget.done;
    // Week 1 asks for one 15-min step from your usual times (V1).
    final fromWake = widget.t.usualWakeMinute,
        fromBed = widget.t.usualBedMinute;
    final wake1 = sc.stepToward(fromWake, wake, 1);
    final bed1 = sc.stepToward(fromBed, bed, 1);
    String about(sc.SleepFocus f) => sc
        .sleepWeeks(f, wakeMinute: wake1, bedMinute: bed1)
        .map((w) => w.habit.title)
        .join(' → ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (done != null) ...[
          TempoCard(
            child: Text(
              'Your ${sc.sleepFocusName(done.plan.focus).toLowerCase()} plan '
              'is done: ${done.kept} of 21 days kept. Start another below, '
              'or keep the habits going on your own.',
              style: TempoType.bodyS.c(c.text1),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text('21 days, one habit a week', style: TempoType.titleL.c(c.text1)),
        const SizedBox(height: 6),
        Text(
          'Each week adds one habit and keeps the last. Tempo ticks the ones '
          'it can see in your sleep; you tick the rest.',
          style: TempoType.body.c(c.text2),
        ),
        const SizedBox(height: 20),
        const Overline('Work on'),
        const SizedBox(height: 8),
        for (final f in sc.SleepFocus.values) ...[
          TempoCard(
            onTap: () => setState(() => _focus = f),
            label: sc.sleepFocusName(f),
            border: f == focus ? c.text1 : c.line,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sc.sleepFocusName(f),
                        style: TempoType.label.c(c.text1),
                      ),
                    ),
                    if (f == suggested)
                      TempoBadge('Your weakest area', small: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(about(f), style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        const Overline('Wake time'),
        const SizedBox(height: 8),
        TempoCard(
          child: Row(
            children: [
              TempoButton(
                '−15',
                small: true,
                kind: ButtonKind.secondary,
                onTap: () => setState(() => _wake = (wake - 15) % 1440),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(fmtHm(wake), style: TempoType.titleL.c(c.text1).tnum),
                    Text(
                      'Lights out ${fmtHm(bed)} for ${hmShort(need)}',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                    if (wake1 != wake || bed1 != bed)
                      Text(
                        'Starts from your usual ${fmtHm(fromBed ?? bed)}–'
                        '${fmtHm(fromWake ?? wake)}, 15 min closer each week',
                        style: TempoType.caption.c(c.text3).tnum,
                      ),
                  ],
                ),
              ),
              TempoButton(
                '+15',
                small: true,
                kind: ButtonKind.secondary,
                onTap: () => setState(() => _wake = (wake + 15) % 1440),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TempoButton(
          'Start the plan',
          expand: true,
          onTap: () async {
            await startSleepPlan(
              ref.read(dbProvider),
              focus,
              wake: wake,
              bed: bed,
              fromWake: fromWake,
              fromBed: fromBed,
            );
            if (context.mounted) {
              showTempoToast(context, 'Sleep plan started · day 1 of 21');
            }
          },
        ),
      ],
    );
  }
}
