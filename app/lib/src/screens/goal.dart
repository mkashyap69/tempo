import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/block_service.dart';
import '../core/coach_service.dart' show dayOf;
import '../core/format.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'goal_setup.dart';
import 'longevity.dart' show LongevityScreen, leverName;
import 'nav.dart';

/// The goal and where this week stands (null = no goal).
final goalViewProvider = dbQuery<GoalView?>((db, ref) => loadGoalView(db));

String goalTitle(sc.TrainingBlock b) => b.isEvent
    ? '${sc.goalName(b.goal)} · ${dayShort(b.event!)}'
    : sc.goalName(b.goal);

/// "15 % longer than week 1".
String volumeLine(double v) {
  final p = ((v - 1) * 100).round();
  if (p == 0) return 'same as week 1';
  return '${p.abs()}% ${p > 0 ? 'longer' : 'shorter'} than week 1';
}

/// 3.5 → "3½".
String halves(double x) {
  final whole = x.floor();
  final half = x - whole >= .5;
  if (!half) return '$whole';
  return whole == 0 ? '½' : '$whole½';
}

String _days(int n) => n == 1 ? '1 day' : '$n days';
String _sessions(int n) => n == 1 ? '1 session' : '$n sessions';
String _more(int n) => n == 1 ? '1 more session' : '$n more sessions';

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

Color phaseColor(BuildContext context, sc.Phase p) {
  final c = context.c, s = context.s;
  return switch (p) {
    sc.Phase.base => s.loadMaintaining,
    sc.Phase.build => s.loadBuilding,
    sc.Phase.peak => s.loadOverreaching,
    sc.Phase.deload => c.lineStrong,
    sc.Phase.taper => s.recHigh,
    sc.Phase.race => c.text1,
  };
}

/// Good / so-so / bad, for chips and verdicts.
enum Tone { good, mid, low, neutral }

Color toneColor(BuildContext context, Tone t) => switch (t) {
  Tone.good => context.s.recHigh,
  Tone.mid => context.s.recMid,
  Tone.low => context.s.recLow,
  Tone.neutral => context.c.text2,
};

Color toneTint(BuildContext context, Tone t) => switch (t) {
  Tone.good => context.s.tintRecHigh,
  Tone.mid => context.s.tintRecMid,
  Tone.low => context.s.tintRecLow,
  Tone.neutral => context.c.surface2,
};

/// What this week is heading for, in words.
final class Verdict {
  const Verdict(
    this.tone,
    this.glyph,
    this.title,
    this.body,
    this.chip,
    this.line,
  );
  final Tone tone;
  final String glyph, title, body;

  /// Short chip label and the one-liner on the Weekly plan card.
  final String chip, line;
}

Verdict verdictFor(GoalView v) {
  final w = v.week;
  if (w == null) {
    return const Verdict(Tone.neutral, '·', 'Outside the block', '', '', '');
  }
  final done = halves(v.soFar.done);
  final of = '$done of ${v.soFar.planned} done';
  switch (w.phase) {
    case sc.Phase.deload:
      return Verdict(
        Tone.neutral,
        '·',
        'Lighter week',
        "This week doesn't change your level. Get the sessions in easily and "
            'let the last three weeks sink in.',
        'Lighter',
        '$of · lighter week',
      );
    case sc.Phase.peak:
      return Verdict(
        Tone.neutral,
        '·',
        'Peak week',
        'Peak weeks hold the plan at its biggest. There is no step to earn; '
            'hit the race-effort sessions and sleep well.',
        'Peak',
        '$of · peak week',
      );
    case sc.Phase.taper:
      return Verdict(
        Tone.neutral,
        '·',
        'Taper',
        'Less running so you arrive fresh. Keep the short fast bits and '
            "don't add extra.",
        'Taper',
        '$of · tapering',
      );
    case sc.Phase.race:
      return Verdict(
        Tone.neutral,
        '·',
        'Race week',
        'Very light. Rest the day before the race. Race day is never moved.',
        'Race week',
        'Race ${dayShort(v.block.event!)}',
      );
    case sc.Phase.base || sc.Phase.build:
      break;
  }
  final f = v.forecast;
  if (f.bodySaysBack) {
    return const Verdict(
      Tone.low,
      '↓',
      'Next week steps back 5%',
      'Recovery or morning feel has been low. Next week will be a little '
          "shorter whatever you do now. That's the plan protecting you, not "
          'a penalty.',
      'Rough',
      'Low recovery · next week steps back',
    );
  }
  if (f.now == sc.WeekCall.stepUp) {
    return Verdict(
      Tone.good,
      '↑',
      'Step up earned',
      "You've done enough for next week's sessions to get about 5% longer. "
          'Anything more is a bonus.',
      'Step up',
      '$of · step up earned',
    );
  }
  final up = f.toStepUp;
  if (up != null && f.now == sc.WeekCall.hold) {
    return Verdict(
      Tone.good,
      '↑',
      'On track to step up',
      '${_more(up)} and next week\'s sessions get about 5% longer.',
      'On track',
      '$of · on track to step up',
    );
  }
  if (f.now == sc.WeekCall.stepBack) {
    final hold = f.toHold;
    return Verdict(
      Tone.mid,
      '→',
      'Heading for a step back',
      hold == null
          ? 'Not enough of the week is left to hold. Next week will be a '
                'little shorter.'
          : 'Do ${_more(hold)} and next week holds instead.'
                '${up != null ? ' Do $up and it steps up.' : ''}',
      'Patchy',
      hold == null ? '$of · steps back' : '$of · $hold more to hold',
    );
  }
  final r = v.soFar.recovery, fe = v.soFar.feel;
  final why = r != null && r < sc.absorbRecovery
      ? 'Recovery has averaged under ${sc.absorbRecovery.round()}, so '
      : fe != null && fe < sc.absorbFeel
      ? 'Morning feel has averaged under ${sc.absorbFeel.round()}, so '
      : 'Not enough of the week is left to step up, so ';
  return Verdict(
    Tone.mid,
    '→',
    'Next week holds',
    '${why}next week stays the same size.',
    'Holding',
    '$of · next week holds',
  );
}

/// The block as bars: past shaded, this week ringed, the rest dashed.
class BlockTimeline extends StatelessWidget {
  const BlockTimeline({
    super.key,
    required this.weeks,
    required this.current,
    this.selected,
    this.onTap,
    this.height = 92,
    this.flags = const {},
  });
  final List<sc.BlockWeek> weeks;

  /// This week's index (-1 = none, everything is planned).
  final int current;
  final int? selected;
  final ValueChanged<int>? onTap;
  final double height;

  /// Week index → short label drawn above its bar (tune-ups).
  final Map<int, String> flags;

  @override
  Widget build(BuildContext context) {
    final colors = [for (final w in weeks) phaseColor(context, w.phase)];
    final painter = _TimelinePainter(
      weeks: weeks,
      colors: colors,
      current: current,
      selected: selected,
      flags: flags,
      ring: context.c.text1,
      bg: context.c.surface1,
      flagStyle: TempoType.caption.copyWith(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: context.c.text1,
      ),
    );
    final box = SizedBox(
      height: height + (flags.isEmpty ? 0 : 16),
      width: double.infinity,
      child: CustomPaint(painter: painter),
    );
    if (onTap == null || weeks.isEmpty) return ExcludeSemantics(child: box);
    return LayoutBuilder(
      builder: (context, cons) => Semantics(
        label: 'Weeks of the block. Tap a week to read about it.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final i = (d.localPosition.dx / cons.maxWidth * weeks.length)
                .floor()
                .clamp(0, weeks.length - 1);
            TempoHaptics.selection();
            onTap!(i);
          },
          child: box,
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.weeks,
    required this.colors,
    required this.current,
    required this.selected,
    required this.flags,
    required this.ring,
    required this.bg,
    required this.flagStyle,
  });
  final List<sc.BlockWeek> weeks;
  final List<Color> colors;
  final int current;
  final int? selected;
  final Map<int, String> flags;
  final Color ring, bg;
  final TextStyle flagStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;
    final n = weeks.length;
    const gap = 3.0;
    final top = flags.isEmpty ? 0.0 : 16.0;
    final h = size.height - top;
    final bw = (size.width - gap * (n - 1)) / n;
    final maxV = math.max(
      1.35,
      weeks.map((w) => w.volume).fold<double>(0, math.max),
    );
    for (var i = 0; i < n; i++) {
      final w = weeks[i];
      final bh = math.max(6.0, w.volume / maxV * (h - 4));
      final x = i * (bw + gap);
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, size.height - bh, bw, bh),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      );
      final col = colors[i];
      if (i > current) {
        _dashed(canvas, r.deflate(.75), col);
      } else {
        canvas.drawRRect(
          r,
          Paint()..color = i < current ? col.withValues(alpha: .55) : col,
        );
      }
      if (i == current || i == selected) {
        canvas.drawRRect(
          r.inflate(i == current ? 2.5 : 1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == current ? 1.75 : 1.25
            ..color = i == current ? ring : ring.withValues(alpha: .6),
        );
      }
      final f = flags[i];
      if (f != null) {
        final tp = TextPainter(
          text: TextSpan(text: f, style: flagStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final fx = (x + bw / 2 - tp.width / 2).clamp(
          0.0,
          size.width - tp.width,
        );
        final fy = size.height - bh - tp.height - 4;
        tp.paint(canvas, Offset(fx, math.max(0, fy)));
      }
    }
  }

  void _dashed(Canvas canvas, RRect r, Color col) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = col;
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter o) =>
      o.weeks != weeks ||
      o.current != current ||
      o.selected != selected ||
      o.ring != ring ||
      o.colors.toString() != colors.toString();
}

Map<int, String> _flags(sc.TrainingBlock b) => {
  for (final t in b.tuneUps) b.weekOf(t.date): sc.goalName(t.goal),
};

/// Training goal on the Weekly plan: what the plan builds toward, the
/// block at a glance and how this week is going.
class GoalCard extends ConsumerWidget {
  const GoalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final async = ref.watch(goalViewProvider);
    if (!async.hasValue) return const SizedBox.shrink();
    final v = async.value;
    if (v == null) {
      return TempoCard(
        label: 'Set a training goal',
        onTap: () => startGoal(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Training goal'),
            const SizedBox(height: 8),
            Text('No training goal', style: TempoType.titleM.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              'The same week every week. Set a goal and the plan builds, '
              'with a lighter week every 4th.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ),
      );
    }
    final b = v.block, w = v.week;
    final days = v.daysToRace;
    String sub;
    if (w == null) {
      sub = b.isEvent && DateTime.now().isAfter(b.event!)
          ? v.next == null
                ? 'Race done. Set a new goal to keep building.'
                : 'Race done. ${sc.goalName(v.next!.goal)} starts after a recovery week.'
          : 'Starts next week.';
    } else {
      sub = [
        b.isEvent
            ? 'Week ${w.index + 1} of ${w.weeks} · ${sc.phaseName(w.phase)}'
            : 'Week ${w.index + 1} · ${sc.phaseName(w.phase)}',
        'sessions ${volumeLine(w.volume)}',
      ].join(' · ');
    }
    final also = [
      for (final t in b.tuneUps)
        if (!t.date.isBefore(dayOf(DateTime.now())))
          '${sc.goalName(t.goal)} tune-up ${dayShort(t.date)}',
      if (v.next != null) '${sc.goalName(v.next!.goal)} next',
    ];
    final verdict = w == null ? null : verdictFor(v);
    return TempoCard(
      label: 'Open training goal',
      onTap: () => push(context, const GoalScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Training goal')),
              if (days != null && days >= 0)
                TempoBadge(days == 0 ? 'Race day' : '${_days(days)} to go'),
            ],
          ),
          const SizedBox(height: 8),
          Text(goalTitle(b), style: TempoType.titleM.c(c.text1)),
          if (v.weeks.isNotEmpty) ...[
            const SizedBox(height: 10),
            BlockTimeline(
              weeks: v.weeks,
              current: w?.index ?? -1,
              height: 30,
              flags: _flags(b),
            ),
          ],
          const SizedBox(height: 8),
          Text(sub, style: TempoType.bodyS.c(c.text2).tnum),
          if (also.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Also: ${also.join(' · ')}',
              style: TempoType.bodyS.c(c.text2).tnum,
            ),
          ],
          if (verdict != null) ...[
            const SizedBox(height: 12),
            const Hair(),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  verdict.glyph,
                  style: TempoType.label.c(toneColor(context, verdict.tone)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verdict.line,
                    style: TempoType.bodyS.c(c.text1).tnum,
                  ),
                ),
                TempoIcon(
                  TempoIcons.chevron,
                  size: 16,
                  color: c.text3,
                  stroke: 2,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens goal setup and, once saved, offers to undo it.
Future<void> startGoal(BuildContext context, WidgetRef ref) async {
  final block = ref.read(goalViewProvider).value?.block;
  final r = await present<GoalSetupResult>(
    context,
    GoalSetupScreen(mode: SetupMode.newGoal, block: block),
  );
  if (r == null || !context.mounted) return;
  final db = ref.read(dbProvider);
  showTempoToast(
    context,
    r.cleared ? 'Goal cleared · plan rebuilt' : 'Plan rebuilt for your goal',
    action: 'Undo',
    onAction: () => restoreBlock(db, r.before),
  );
}

/// Where the goal stands: the block, this week's scorecard, what's ahead
/// and why past weeks went the way they did.
class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key});

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final async = ref.watch(goalViewProvider);
    final v = async.value;
    if (!async.hasValue) return Scaffold(backgroundColor: c.bg);
    if (v == null) {
      return TempoPage(
        children: [
          const DetailHeader(title: 'Training goal'),
          Text('No training goal', style: TempoType.pageTitle.c(c.text1)),
          Text(
            'The plan is the same week every week. Set a goal and it builds '
            'toward it, earning each step from how your weeks go.',
            style: TempoType.body.c(c.text2),
          ),
          TempoButton(
            'Set a goal',
            expand: true,
            onTap: () => startGoal(context, ref),
          ),
        ],
      );
    }
    final b = v.block, w = v.week;
    final sel = _sel ?? w?.index ?? 0;
    final days = v.daysToRace;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Training goal'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sc.goalName(b.goal), style: TempoType.pageTitle.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              [
                if (b.isEvent) dayShort(b.event!),
                if (days != null && days > 0) '${_days(days)} to go',
                if (days == 0) 'race day',
                'started ${dm(b.start)}',
              ].join(' · '),
              style: TempoType.bodyS.c(c.text2).tnum,
            ),
          ],
        ),
        if (w != null && w.newPhase && !v.phaseSeen) _PhaseCard(v: v),
        if (v.weeks.isNotEmpty) _BlockCard(v: v, sel: sel, onSel: _pick),
        if (w != null) _ThisWeekCard(v: v),
        if (b.tuneUps.isNotEmpty || v.next != null || v.focus != null)
          _AlsoCard(v: v),
        if (v.history.isNotEmpty) _HistoryCard(v: v),
        const _HowCard(),
        _Actions(v: v),
      ],
    );
  }

  void _pick(int i) => setState(() => _sel = i);
}

class _PhaseCard extends ConsumerWidget {
  const _PhaseCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final w = v.week!;
    // The run of weeks in this phase, and what follows.
    var end = w.index;
    while (end + 1 < v.weeks.length && v.weeks[end + 1].phase == w.phase) {
      end++;
    }
    final next = end + 1 < v.weeks.length ? v.weeks[end + 1].phase : null;
    final hard = w.hard(v.usualHard);
    final range = end == w.index
        ? 'Week ${w.index + 1}'
        : 'Weeks ${w.index + 1}–${end + 1}';
    final then = next == null
        ? null
        : 'After ${end == w.index ? 'this week' : 'week ${end + 1}'} comes '
              '${sc.phaseName(next).toLowerCase()}.';
    final points = <(String, String)>[
      ...switch (w.phase) {
        sc.Phase.base => [
          (
            'One hard session a week.',
            ' Everything else is easy, to build the engine.',
          ),
          (
            'Sessions grow about 5%',
            ' each week you handle well (2 of 3 sessions done, recovery and '
                'feel holding).',
          ),
        ],
        sc.Phase.build => [
          (
            hard > 1 ? '$hard hard sessions a week' : 'Longer sessions',
            hard > 1 ? ' instead of one.' : ' with one hard session.',
          ),
          ('Long runs grow faster,', ' about 10% each week you earn a step.'),
        ],
        sc.Phase.peak => [
          (
            'Race-effort sessions.',
            ' The plan holds at its biggest; there are no step-ups.',
          ),
        ],
        sc.Phase.deload => [
          (
            'About a third shorter',
            ', with one hard session, so the last weeks sink in.',
          ),
          ("It doesn't count", ' for or against you.'),
        ],
        sc.Phase.taper => [
          ('About 40% less,', ' keeping a little speed, so you arrive fresh.'),
          ('Sleep and easy days', ' matter most now.'),
        ],
        sc.Phase.race => [
          ('Very light.', ' Rest the day before the race.'),
          ('Race day is never moved', ' or adapted.'),
        ],
      },
      if (then != null) ('Next:', ' $then'),
    ];
    return TempoCard(
      border: phaseColor(context, w.phase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('New phase this week')),
              TempoBadge(range),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${sc.phaseName(w.phase)} starts',
            style: TempoType.titleM.c(c.text1),
          ),
          const SizedBox(height: 4),
          Text(sc.phaseSay(w.phase), style: TempoType.bodyS.c(c.text2)),
          for (final (h, t) in points) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: h, style: TempoType.bodyS.c(c.text1).w500),
                  TextSpan(text: t),
                ],
              ),
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Shown once per phase. Tap a week below to read it again.',
                  style: TempoType.caption.c(c.text3),
                ),
              ),
              TempoButton(
                'Got it',
                small: true,
                kind: ButtonKind.secondary,
                onTap: () =>
                    dismissPhase(ref.read(dbProvider), v.block, w.index),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.v, required this.sel, required this.onSel});
  final GoalView v;
  final int sel;
  final ValueChanged<int> onSel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = v.block;
    final current = v.week?.index ?? -1;
    final n = v.weeks.length;
    final phases = {for (final w in v.weeks) w.phase}.toList();
    final s = v.weeks[sel.clamp(0, n - 1)];
    final mon = b.start.add(Duration(days: 7 * s.index));
    final rec = s.index < v.history.length ? v.history[s.index] : null;
    final tune = s.tuneUp;
    final when = s.index < current
        ? 'Done'
        : s.index == current
        ? 'This week'
        : 'Planned';
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('The block')),
              Text('Tap a week', style: TempoType.caption.c(c.text3)),
            ],
          ),
          const SizedBox(height: 12),
          BlockTimeline(
            weeks: v.weeks,
            current: current,
            selected: sel,
            onTap: onSel,
            flags: _flags(b),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Text(
                    i == current
                        ? 'now'
                        : v.weeks[i].phase == sc.Phase.race
                        ? 'race'
                        : i % (n > 12 ? 4 : 2) == 0
                        ? '${i + 1}'
                        : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: TempoType.caption
                        .copyWith(
                          fontSize: 10,
                          fontWeight: i == current ? FontWeight.w600 : null,
                        )
                        .c(i == current ? c.text1 : c.text3)
                        .tnum,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final p in phases)
                Legend(phaseColor(context, p), sc.phaseName(p), height: 8),
              Legend(c.text3, 'If weeks go well', outline: true, height: 8),
            ],
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
                  'Week ${s.index + 1} · ${dm(mon)} – ${dm(mon.add(const Duration(days: 6)))} · ${sc.phaseName(s.phase)}',
                  style: TempoType.label.c(c.text1).tnum,
                ),
                const SizedBox(height: 4),
                Text(sc.phaseSay(s.phase), style: TempoType.bodyS.c(c.text2)),
                const SizedBox(height: 4),
                Text(
                  s.phase == sc.Phase.race
                      ? '$when: very light, then the race.'
                      : '$when: sessions ${volumeLine(s.volume)}.',
                  style: TempoType.bodyS.c(c.text2).tnum,
                ),
                if (rec != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    rec.call == null
                        ? '${sc.phaseName(rec.phase)} · ${_outcomeLine(rec.outcome)}'
                        : '${_callName(rec.call!)} · ${_outcomeLine(rec.outcome)}',
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                ] else if (s.index > current) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Projected. It gets smaller if a week before it holds or '
                    'steps back.',
                    style: TempoType.caption.c(c.text3),
                  ),
                ],
                if (tune != null) ...[
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${sc.goalName(tune.goal)} tune-up on ${dayShort(tune.date)}. ',
                          style: TempoType.bodyS.c(c.text1).w500,
                        ),
                        const TextSpan(
                          text:
                              "It's this week's hard session. The two days before "
                              'are easy and the day after is rest.',
                        ),
                      ],
                    ),
                    style: TempoType.bodyS.c(c.text2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _callName(sc.WeekCall c) => switch (c) {
  sc.WeekCall.stepUp => 'Stepped up',
  sc.WeekCall.hold => 'Held',
  sc.WeekCall.stepBack => 'Stepped back',
};

String _outcomeLine(sc.WeekOutcome o) => [
  if (o.planned == 0)
    'No sessions planned'
  else
    '${halves(o.done)} of ${o.planned} sessions',
  if (o.recovery != null) 'recovery ${o.recovery!.round()}',
  if (o.feel != null) 'feel ${o.feel!.toStringAsFixed(1)}',
].join(' · ');

class _ThisWeekCard extends ConsumerWidget {
  const _ThisWeekCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = v.week!;
    final verdict = verdictFor(v);
    final o = v.soFar;
    final moves = sc.movesLevel(w.phase);
    final mon = v.days.isEmpty ? null : v.days.first.date;
    double half(double x) => (x * 2).ceil() / 2;
    final upAt = half(o.planned * sc.absorbRatio);
    final backUnder = half(o.planned * sc.backRatio);
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Overline(
                  mon == null
                      ? 'This week'
                      : 'This week · ${dm(mon)} – ${dm(mon.add(const Duration(days: 6)))}',
                ),
              ),
              if (verdict.chip.isNotEmpty)
                _Chip(verdict.chip, tone: verdict.tone),
            ],
          ),
          if (v.days.length == 7) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (i, d) in v.days.indexed)
                  Expanded(
                    child: _DayDot(d: d, i: i, today: v.today),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Hair(),
          const SizedBox(height: 14),
          _Check(
            label: 'Sessions',
            value: '${halves(o.done)} of ${o.planned}',
            need: moves
                ? 'Step up at ${halves(upAt)} · step back under ${halves(backUnder)}'
                : '${_sessions(v.left)} left this week',
            frac: o.planned == 0 ? 0 : o.done / o.planned,
            tick: moves ? upAt / math.max(1, o.planned) : null,
            tone: o.ratio >= sc.absorbRatio
                ? Tone.good
                : o.ratio >= sc.backRatio
                ? Tone.mid
                : Tone.low,
          ),
          const SizedBox(height: 14),
          _Check(
            label: 'Recovery',
            value: o.recovery == null ? null : 'avg ${o.recovery!.round()}',
            need:
                'Step up at ${sc.absorbRecovery.round()} · step back under ${sc.backRecovery.round()} · ${_days(v.recDays)} so far',
            frac: (o.recovery ?? 0) / 100,
            tick: sc.absorbRecovery / 100,
            tone: _tone(o.recovery, sc.absorbRecovery, sc.backRecovery),
          ),
          const SizedBox(height: 14),
          _Check(
            label: 'Morning feel',
            value: o.feel == null ? null : 'avg ${o.feel!.toStringAsFixed(1)}',
            need:
                'Step up at ${sc.absorbFeel.toStringAsFixed(0)} · step back under ${sc.backFeel} · ${_days(v.feelDays)} so far',
            frac: (o.feel ?? 0) / 5,
            tick: sc.absorbFeel / 5,
            tone: _tone(o.feel, sc.absorbFeel, sc.backFeel),
          ),
          const SizedBox(height: 14),
          _VerdictBox(v: v, verdict: verdict),
        ],
      ),
    );
  }

  static Tone _tone(double? x, double up, double back) => x == null
      ? Tone.neutral
      : x >= up
      ? Tone.good
      : x >= back
      ? Tone.mid
      : Tone.low;
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.tone});
  final String text;
  final Tone tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: toneTint(context, tone),
      borderRadius: BorderRadius.circular(TempoRadii.pill),
    ),
    child: Text(
      text,
      style: TempoType.caption
          .copyWith(fontWeight: FontWeight.w500)
          .c(tone == Tone.neutral ? context.c.text1 : toneColor(context, tone))
          .tnum,
    ),
  );
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.d, required this.i, required this.today});
  final DayCredit d;
  final int i, today;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final rest = d.session.isRest;
    final skipped = d.status == sc.Intent.skipped.name;
    final missed = !rest && d.credit == 0 && (i < today || skipped);
    final good = s.recHigh;
    final Widget dot = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: d.credit >= 1 ? good : null,
        gradient: d.credit > 0 && d.credit < 1
            ? LinearGradient(
                colors: [good, good, Colors.transparent, Colors.transparent],
                stops: const [0, .5, .5, 1],
              )
            : null,
        border: Border.all(
          width: 1.5,
          color: d.credit > 0
              ? good
              : missed
              ? s.recLow
              : c.lineStrong,
        ),
      ),
      child: d.credit >= 1
          ? TempoIcon(
              TempoIcons.check,
              size: 13,
              color: c.textInverse,
              stroke: 2.5,
            )
          : missed
          ? Text('×', style: TempoType.label.c(s.recLow))
          : null,
    );
    final short = d.session.key == 'race'
        ? 'Race'
        : rest
        ? 'Rest'
        : d.session.title.split(' ').first;
    return Semantics(
      label:
          '${weekdayNames[i]}: ${d.session.title}${d.credit >= 1
              ? ', done'
              : d.credit > 0
              ? ', done easier'
              : missed
              ? ', missed'
              : ''}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: i == today
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.text1, width: 1.5),
                    )
                  : null,
              child: dot,
            ),
            const SizedBox(height: 4),
            Text(
              'MTWTFSS'[i],
              style: TempoType.caption.c(i == today ? c.text1 : c.text3),
            ),
            Text(
              short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TempoType.caption.copyWith(fontSize: 10).c(c.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.need,
    required this.frac,
    required this.tick,
    required this.tone,
  });
  final String label;
  final String? value;
  final String need;
  final double frac;
  final double? tick;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = toneColor(context, tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TempoType.body.c(c.text1))),
            _Chip(
              value ?? 'Not enough days yet',
              tone: value == null ? Tone.neutral : tone,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, cons) => SizedBox(
            height: 12,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.trackOff,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                if (value != null)
                  Container(
                    height: 6,
                    width: cons.maxWidth * frac.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: col,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                if (tick != null)
                  Positioned(
                    left: (cons.maxWidth * tick!).clamp(0.0, cons.maxWidth - 2),
                    child: Container(width: 2, height: 12, color: c.text1),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(need, style: TempoType.caption.c(c.text3).tnum),
      ],
    );
  }
}

class _VerdictBox extends ConsumerWidget {
  const _VerdictBox({required this.v, required this.verdict});
  final GoalView v;
  final Verdict verdict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final db = ref.read(dbProvider);
    final m = v.missed, r = v.realign;
    String plan(sc.Realign x) => [
      for (final i in x.changed)
        '${weekdayNames[i].substring(0, 3)} ${x.week[i].title}',
    ].join(' · ');
    final children = <Widget>[
      Text(verdict.title, style: TempoType.label.c(c.text1)),
      const SizedBox(height: 2),
      Text(verdict.body, style: TempoType.bodyS.c(c.text2)),
    ];
    if (m != null) {
      final name = v.days[m].session.title;
      children.addAll([
        const SizedBox(height: 10),
        Text(
          r == null
              ? '${weekdayNames[m]}’s $name was missed and there’s no room '
                    'left for it without two hard days in a row. Nothing is '
                    'added to catch up.'
              : '${weekdayNames[m]}’s $name was missed. Fit it in: ${plan(r)}.',
          style: TempoType.bodyS.c(c.text1),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (r != null)
              TempoButton(
                'Rearrange the week',
                small: true,
                onTap: () async {
                  await rearrangeWeek(db, v);
                  if (context.mounted) {
                    showTempoToast(context, 'Week rearranged');
                  }
                },
              ),
            TempoButton(
              'Let it go',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () => letGo(db, v),
            ),
          ],
        ),
      ]);
    } else if (v.ease != null) {
      children.addAll([
        const SizedBox(height: 10),
        Text(
          'Make the rest of the week easy: ${plan(v.ease!)}.',
          style: TempoType.bodyS.c(c.text1),
        ),
        const SizedBox(height: 10),
        TempoButton(
          'Make it easy',
          small: true,
          onTap: () async {
            await easeWeek(db, v);
            if (context.mounted) {
              showTempoToast(context, 'Rest of the week is easy');
            }
          },
        ),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: toneTint(context, verdict.tone),
        borderRadius: BorderRadius.circular(TempoRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              verdict.glyph,
              style: TempoType.titleM.c(toneColor(context, verdict.tone)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlsoCard extends ConsumerWidget {
  const _AlsoCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final db = ref.read(dbProvider);
    final b = v.block;
    Widget row(String title, String chip, String body, {VoidCallback? onTap}) =>
        Pressable(
          label: title,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TempoType.label.c(c.text1).tnum,
                      ),
                    ),
                    TempoBadge(chip),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
        );
    final today = dayOf(DateTime.now());
    final next = v.next;
    final start = sc.nextBlockStart(b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Overline('Also on your plan')),
            Text(
              '${sc.goalName(b.goal)} leads',
              style: TempoType.caption.c(c.text3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CardList(
          children: [
            for (final t in b.tuneUps)
              row(
                '${sc.goalName(t.goal)} tune-up · ${dayShort(t.date)}',
                t.date.isBefore(today) ? 'Done' : 'In this block',
                'Runs as week ${b.weekOf(t.date) + 1}’s hard session. The two '
                    'days before are easy and the day after is rest. The '
                    '${sc.goalName(b.goal).toLowerCase()} plan carries on around it.',
                onTap: () async {
                  final ok = await confirmSheet(
                    context,
                    title: 'Remove this tune-up?',
                    body:
                        'The ${sc.goalName(t.goal)} on ${dayShort(t.date)} comes off the plan and that week goes back to normal.',
                    action: 'Remove',
                    danger: true,
                  );
                  if (ok) await removeTuneUp(db, t);
                },
              ),
            if (next != null && start != null)
              row(
                '${sc.goalName(next.goal)} · ${dayShort(next.event)}',
                'Up next',
                'Starts ${dm(start)} after a recovery week, as a '
                    '${sc.eventWeeks(start, next.event)}-week block. Nothing changes until then.',
                onTap: () async {
                  final ok = await confirmSheet(
                    context,
                    title: 'Remove the next goal?',
                    body: 'After this race the plan goes back to the same week every week until you set a new goal.',
                    action: 'Remove',
                    danger: true,
                  );
                  if (ok) await saveNext(db, null);
                },
              ),
            if (v.focus != null)
              row(
                leverName(v.focus!.lever),
                'Alongside',
                'Your Tempo Age focus, week ${v.focus!.weekOn(DateTime.now())} of '
                    '${v.focus!.weeks}. It fits on easy and rest days and never '
                    'takes a hard day.',
                onTap: () => push(context, const LongevityScreen()),
              ),
          ],
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('How past weeks went'),
          for (final (k, r) in v.history.reversed.indexed) ...[
            SizedBox(height: k == 0 ? 12 : 10),
            if (k > 0) ...[const Hair(), const SizedBox(height: 10)],
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    'Week ${r.index + 1}',
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                ),
                Expanded(
                  child: Text(
                    sc.phaseName(r.phase),
                    style: TempoType.bodyS.c(c.text1),
                  ),
                ),
                Text(
                  switch (r.call) {
                    sc.WeekCall.stepUp => '↑ Stepped up',
                    sc.WeekCall.hold => '→ Held',
                    sc.WeekCall.stepBack => '↓ Stepped back',
                    null => 'No change',
                  },
                  style: TempoType.label.c(switch (r.call) {
                    sc.WeekCall.stepUp => s.recHigh,
                    sc.WeekCall.hold => s.recMid,
                    sc.WeekCall.stepBack => s.recLow,
                    null => c.text3,
                  }),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 58, top: 2),
              child: Text(
                r.call == null
                    ? "${_outcomeLine(r.outcome)}. ${sc.phaseName(r.phase)} weeks don't change your level."
                    : _outcomeLine(r.outcome),
                style: TempoType.bodyS.c(c.text2).tnum,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowCard extends StatefulWidget {
  const _HowCard();
  @override
  State<_HowCard> createState() => _HowCardState();
}

class _HowCardState extends State<_HowCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final points = [
      (
        'You earn each step.',
        ' At the end of a base or build week Tempo checks three things. If '
            'you did at least 2 of every 3 sessions, recovery averaged '
            '${sc.absorbRecovery.round()} or more and morning feel averaged '
            '${sc.absorbFeel.round()} or more, next week\'s sessions get about 5% longer.',
      ),
      (
        'A patchy week holds.',
        ' Anything between a good week and a rough one keeps next week the '
            'same size.',
      ),
      (
        'A rough week steps back 5%.',
        ' Under 1 in 3 sessions, recovery under ${sc.backRecovery.round()} or '
            'feel under ${sc.backFeel}. It stops you digging a hole.',
      ),
      (
        'Every 4th week is lighter.',
        " About a third shorter, one hard session. It doesn't count for or "
            'against you.',
      ),
      (
        'Long runs grow twice as fast,',
        ' up to a cap for the distance. Growth stops at +40%.',
      ),
      (
        'The last weeks are fixed.',
        ' Peak holds steady, the taper cuts volume so you arrive fresh, and '
            'race day is never moved.',
      ),
      (
        'Missed a key session?',
        ' Tempo offers to fit it back in without two hard days in a row, or '
            'to let it go. It never stacks sessions to catch up.',
      ),
    ];
    return TempoCard(
      onTap: () => setState(() => _open = !_open),
      label: 'How the plan grows',
      child: AnimatedSize(
        duration: TempoMotion.base,
        curve: TempoMotion.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'How the plan grows',
                    style: TempoType.label.c(c.text1),
                  ),
                ),
                Text(_open ? '−' : '+', style: TempoType.titleM.c(c.text3)),
              ],
            ),
            if (_open)
              for (final (h, t) in points) ...[
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: h, style: TempoType.bodyS.c(c.text1).w500),
                      TextSpan(text: t),
                    ],
                  ),
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = v.block;
    final db = ref.read(dbProvider);
    final raceOver = b.isEvent && dayOf(DateTime.now()).isAfter(b.event!);
    return CardList(
      children: [
        if (b.isEvent && !raceOver)
          ListRow(
            'Change race date',
            onTap: () => present<GoalSetupResult>(
              context,
              GoalSetupScreen(mode: SetupMode.changeDate, block: b),
            ),
          ),
        if (!raceOver)
          ListRow(
            'Add to your plan',
            sub: 'A tune-up race, the next goal or a habit',
            onTap: () => showAddToPlan(context, ref, v),
          ),
        ListRow(
          raceOver ? 'Set a new goal' : 'Switch goal',
          onTap: () => startGoal(context, ref),
        ),
        ListRow(
          'End this goal',
          color: context.s.recLow,
          chevron: false,
          onTap: () async {
            final ok = await confirmSheet(
              context,
              title: 'End the ${sc.goalName(b.goal).toLowerCase()} goal?',
              body:
                  'Your plan goes back to the same week every week. Past '
                  'weeks stay in your history.',
              action: 'End goal',
              danger: true,
            );
            if (!ok || !context.mounted) return;
            final before = await saveBlock(db, null);
            if (context.mounted) {
              showTempoToast(
                context,
                'Goal ended · plan rebuilt',
                action: 'Undo',
                onAction: () => restoreBlock(db, before),
              );
              Navigator.maybePop(context);
            }
          },
        ),
      ],
    );
  }
}
