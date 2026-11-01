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
import 'coach.dart' show CoachTab, openCoachAt;
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

Color phaseColor(BuildContext context, sc.Phase p) {
  final s = context.s;
  return switch (p) {
    sc.Phase.base => s.loadDetraining,
    sc.Phase.build => s.loadBuilding,
    sc.Phase.peak => s.loadOverreaching,
    sc.Phase.deload => s.loadMaintaining,
    sc.Phase.taper => s.recHigh,
    sc.Phase.race => s.recLow,
  };
}

/// A stage of the plan in plain words ("Build the base").
String phasePlain(sc.Phase p) => switch (p) {
  sc.Phase.base => 'Build the base',
  sc.Phase.build => 'Build up',
  sc.Phase.peak => 'Sharpen',
  sc.Phase.deload => 'Lighter week',
  sc.Phase.taper => 'Ease in',
  sc.Phase.race => 'Race week',
};

/// One-word stage for small labels.
String phaseShort(sc.Phase p) => switch (p) {
  sc.Phase.base => 'Base',
  sc.Phase.build => 'Build',
  sc.Phase.peak => 'Sharpen',
  sc.Phase.deload => 'Lighter',
  sc.Phase.taper => 'Ease in',
  sc.Phase.race => 'Race',
};

/// What a week of [p] asks, in one line ([hard] sessions a week).
String phaseAbout(sc.Phase p, int hard) => switch (p) {
  sc.Phase.base => 'Mostly easy, one harder session',
  sc.Phase.build =>
    hard > 1
        ? '$hard harder sessions, longer long runs'
        : 'Longer sessions, longer long runs',
  sc.Phase.peak => 'Race-effort sessions, the biggest weeks',
  sc.Phase.deload => 'About a third less so the work sinks in',
  sc.Phase.taper => 'About 40% less, a little speed, arrive fresh',
  sc.Phase.race => 'Very light, rest the day before the race',
};

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
      'Next week eases off a little',
      'Recovery or morning feel has been low, so next week is about 5% '
          "shorter whatever you do now. That's the plan protecting you, not "
          'a penalty.',
      'Easing off',
      'Low recovery · next week eases off',
    );
  }
  if (f.now == sc.WeekCall.stepUp) {
    return Verdict(
      Tone.good,
      '↑',
      'Next week grows',
      "You've done enough for next week's sessions to get about 5% longer. "
          'Anything more is a bonus.',
      'Growing',
      '$of · next week grows',
    );
  }
  final up = f.toStepUp;
  if (up != null && f.now == sc.WeekCall.hold) {
    return Verdict(
      Tone.good,
      '↑',
      'On track to grow',
      'Do ${_more(up)} and next week\'s sessions get about 5% longer.',
      'On track',
      '$of · ${_more(up)} to grow',
    );
  }
  if (f.now == sc.WeekCall.stepBack) {
    final hold = f.toHold;
    return Verdict(
      Tone.mid,
      '→',
      hold == null ? 'A light week' : 'Behind, still time',
      hold == null
          ? 'Not enough of the week is left, so next week eases off a '
                'little. Nothing to make up.'
          : 'Do ${_more(hold)} and next week stays the same size.'
                '${up != null ? ' Do $up and it grows.' : ''} No need to make '
                'up what was missed.',
      hold == null ? 'Light' : 'Behind',
      hold == null
          ? '$of · next week eases off'
          : '$of · ${_more(hold)} to keep the level',
    );
  }
  final r = v.soFar.recovery, fe = v.soFar.feel;
  final why = r != null && r < sc.absorbRecovery
      ? 'Recovery has averaged under ${sc.absorbRecovery.round()}, so '
      : fe != null && fe < sc.absorbFeel
      ? 'Morning feel has averaged under ${sc.absorbFeel.round()}, so '
      : 'Not enough of the week is left to grow, so ';
  return Verdict(
    Tone.mid,
    '→',
    'Next week stays the same size',
    '${why}next week stays the same size.',
    'Steady',
    '$of · next week stays the same',
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
  const GoalCard({super.key, this.onOpen});

  /// Opens the goal (default: push the Goal screen).
  final VoidCallback? onOpen;

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
    final vdot = ref.watch(profileProvider).value?.vdot;
    final metres = sc.goalMetres(b.goal);
    final predicted = vdot == null || metres == null
        ? null
        : sc.raceSeconds(vdot, metres);
    return TempoCard(
      label: 'Open training goal',
      onTap: onOpen ?? () => push(context, const GoalScreen()),
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
          // At today's fitness, from your race time (U5).
          if (b.isEvent && predicted != null) ...[
            const SizedBox(height: 4),
            Text(
              'At today’s fitness: about ${sc.durationText(predicted)}',
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

/// One line on Today: the goal and how this week is going. Opens Coach at
/// the goal; with no goal it offers to set one.
class TodayGoalLine extends ConsumerWidget {
  const TodayGoalLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalViewProvider);
    if (!async.hasValue) return const SizedBox.shrink();
    final v = async.value;
    final c = context.c;
    final String text;
    Tone tone = Tone.neutral;
    String glyph = '◎';
    if (v == null) {
      text = 'Training for something? Set a goal';
    } else {
      final days = v.daysToRace;
      final head = [
        sc.goalName(v.block.goal),
        if (days != null && days > 0) _days(days),
      ].join(' · ');
      if (v.week == null) {
        text =
            '$head · ${DateTime.now().isAfter(v.block.event ?? DateTime(9999)) ? 'race done' : 'starts next week'}';
      } else {
        final verdict = verdictFor(v);
        tone = verdict.tone;
        glyph = verdict.glyph;
        text = '$head · ${verdict.line}';
      }
    }
    return TempoCard(
      label: v == null ? 'Set a training goal' : 'Open training goal',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => openCoachAt(context, CoachTab.goal),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              glyph,
              style: TempoType.label.c(
                tone == Tone.neutral ? c.text2 : toneColor(context, tone),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TempoType.bodyS.c(v == null ? c.text2 : c.text1).tnum,
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3, stroke: 2),
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
class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context) => const TempoPage(
    children: [
      DetailHeader(title: 'Your goal'),
      GoalBody(),
    ],
  );
}

/// The goal's sections: title, where this week stands, the weeks as a
/// list, how next week is set, extras, history, how it works and actions.
class GoalBody extends ConsumerWidget {
  const GoalBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final async = ref.watch(goalViewProvider);
    final v = async.value;
    if (!async.hasValue) return const SizedBox(height: 400);
    final List<Widget> children;
    if (v == null) {
      children = [
        Text('No training goal', style: TempoType.pageTitle.c(c.text1)),
        Text(
          'The plan is the same week every week. Set a goal and it builds '
          'toward it: a race on a date (5K to marathon) or just getting '
          'fitter, earning each step from how your weeks go.',
          style: TempoType.body.c(c.text2),
        ),
        TempoButton(
          'Set a goal',
          expand: true,
          onTap: () => startGoal(context, ref),
        ),
        const _HowCard(),
      ];
    } else {
      final b = v.block, w = v.week;
      final days = v.daysToRace;
      children = [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(goalTitle(b), style: TempoType.pageTitle.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              [
                if (days != null && days > 0) '${_days(days)} to go',
                if (days == 0) 'race day',
                if (b.isEvent && v.weeks.isNotEmpty)
                  '${v.weeks.length}-week plan',
                'started ${dm(b.start)}',
              ].join(' · '),
              style: TempoType.bodyS.c(c.text2).tnum,
            ),
          ],
        ),
        if (w != null) _VerdictCard(v: v),
        if (v.weeks.isNotEmpty) _WeeksCard(v: v),
        if (w != null) _NextWeekCard(v: v),
        if (b.tuneUps.isNotEmpty || v.next != null || v.focus != null)
          _AlsoCard(v: v),
        if (v.history.isNotEmpty) _HistoryCard(v: v),
        const _HowCard(),
        _Actions(v: v),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, ch) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          ch,
        ],
      ],
    );
  }
}

/// Where this week stands, in a sentence, tinted by how it's going.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final verdict = verdictFor(v);
    return TempoCard(
      color: toneTint(context, verdict.tone),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              verdict.glyph,
              style: TempoType.titleM.c(
                verdict.tone == Tone.neutral
                    ? c.text2
                    : toneColor(context, verdict.tone),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(verdict.title, style: TempoType.label.c(c.text1)),
                const SizedBox(height: 2),
                Text(verdict.body, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The block as a list of weeks, each with its dates, stage and what it
/// asks, the current one marked.
class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context) {
    final b = v.block;
    final current = v.week?.index ?? -1;
    final weeks = v.weeks;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline(b.isEvent ? 'The ${weeks.length} weeks' : 'The weeks ahead'),
          const SizedBox(height: 14),
          for (final (k, s) in weeks.indexed)
            _WeekRow(
              v: v,
              s: s,
              now: s.index == current,
              past: s.index < current,
              last: k == weeks.length - 1,
            ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.v,
    required this.s,
    required this.now,
    required this.past,
    required this.last,
  });
  final GoalView v;
  final sc.BlockWeek s;
  final bool now, past, last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = phaseColor(context, s.phase);
    final mon = v.block.start.add(Duration(days: 7 * s.index));
    final rec = s.index < v.history.length ? v.history[s.index] : null;
    final tune = s.tuneUp;
    final lines = [
      '${dm(mon)} – ${dm(mon.add(const Duration(days: 6)))}',
      phaseAbout(s.phase, s.hard(v.usualHard)),
      if (rec != null)
        _outcomeLine(rec.outcome)
      else if (!now && !past && s.phase != sc.Phase.race)
        'Sessions ${volumeLine(s.volume)}. Projected: it depends on the weeks '
            'before.',
      if (tune != null)
        '${sc.goalName(tune.goal)} tune-up on ${dayShort(tune.date)}.',
    ];
    final dot = Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: now || past || s.phase == sc.Phase.race ? col : null,
        border: Border.all(color: col, width: 2),
        boxShadow: now
            ? [BoxShadow(color: c.lineStrong, spreadRadius: 3)]
            : null,
      ),
    );
    return Semantics(
      label:
          'Week ${s.index + 1}, ${phasePlain(s.phase)}${now ? ', this week' : ''}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 22,
                child: Column(
                  children: [
                    dot,
                    if (!last)
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
                  padding: EdgeInsets.only(bottom: last ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Week ${s.index + 1} · ${phasePlain(s.phase)}',
                              style: TempoType.label.c(
                                past ? c.text2 : c.text1,
                              ),
                            ),
                          ),
                          if (now)
                            TempoBadge(
                              'Now',
                              color: c.textInverse,
                              background: c.text1,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lines.join(' · '),
                        style: TempoType.bodyS.c(c.text2).tnum,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How next week is set: this week's numbers against the rule, and the
/// three outcomes with the one it's heading for.
class _NextWeekCard extends StatelessWidget {
  const _NextWeekCard({required this.v});
  final GoalView v;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final w = v.week!;
    final o = v.soFar;
    final f = v.forecast;
    if (!sc.movesLevel(w.phase)) {
      return TempoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Next week'),
            const SizedBox(height: 8),
            Text(
              '${phasePlain(w.phase)} weeks are fixed: what you do now '
              'doesn’t change the size of the weeks ahead. '
              '${_sessions(v.left)} left this week.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ),
      );
    }
    double half(double x) => (x * 2).ceil() / 2;
    final up = half(o.planned * sc.absorbRatio);
    final back = half(o.planned * sc.backRatio);
    final heading = f.bodySaysBack ? sc.WeekCall.stepBack : f.now;
    Widget check(String label, String value, String? note) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TempoType.body.c(c.text1))),
          Text(value, style: TempoType.label.c(c.text1).tnum),
          if (note != null) ...[
            const SizedBox(width: 6),
            Text(note, style: TempoType.caption.c(c.text3).tnum),
          ],
        ],
      ),
    );
    String okNote(double? x, double good, double low) => x == null
        ? ''
        : x >= good
        ? 'OK'
        : x >= low
        ? 'low'
        : 'very low';
    Widget outcome(sc.WeekCall call, String title, String when) {
      final on = call == heading;
      final possible = !f.bodySaysBack && call == f.best && !on;
      final col = switch (call) {
        sc.WeekCall.stepUp => s.recHigh,
        sc.WeekCall.hold => s.recMid,
        sc.WeekCall.stepBack => s.recLow,
      };
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: on ? c.surface2 : null,
          borderRadius: BorderRadius.circular(TempoRadii.md),
          border: Border.all(color: on ? col : c.line, width: on ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: TempoType.label.c(c.text1))),
                if (on)
                  Text('Heading here', style: TempoType.caption.c(col))
                else if (possible)
                  Text('Still possible', style: TempoType.caption.c(col)),
              ],
            ),
            const SizedBox(height: 2),
            Text(when, style: TempoType.bodyS.c(c.text2).tnum),
          ],
        ),
      );
    }

    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('How next week is set'),
          const SizedBox(height: 6),
          check(
            'Sessions done',
            '${halves(o.done)} of ${o.planned}',
            v.left > 0 ? '${v.left} left' : null,
          ),
          const Hair(),
          check(
            'Recovery, average',
            o.recovery == null ? '–' : '${o.recovery!.round()}',
            o.recovery == null
                ? 'not enough days'
                : okNote(o.recovery, sc.absorbRecovery, sc.backRecovery),
          ),
          const Hair(),
          check(
            'Morning feel, average',
            o.feel == null ? '–' : o.feel!.toStringAsFixed(1),
            o.feel == null
                ? 'not enough days'
                : okNote(o.feel, sc.absorbFeel, sc.backFeel),
          ),
          const SizedBox(height: 4),
          outcome(
            sc.WeekCall.stepUp,
            'Next week grows about 5%',
            '${halves(up)} or more sessions, recovery '
                '${sc.absorbRecovery.round()}+ and feel '
                '${sc.absorbFeel.round()}+.',
          ),
          outcome(
            sc.WeekCall.hold,
            'Next week stays the same size',
            'Anything in between.',
          ),
          outcome(
            sc.WeekCall.stepBack,
            'Next week eases off about 5%',
            'Under ${halves(back)} sessions, recovery under '
                '${sc.backRecovery.round()} or feel under ${sc.backFeel}.',
          ),
          const SizedBox(height: 10),
          Text(
            'Missed sessions are never stacked up to catch up.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}

String _outcomeLine(sc.WeekOutcome o) => [
  if (o.planned == 0)
    'No sessions planned'
  else
    '${halves(o.done)} of ${o.planned} sessions',
  if (o.recovery != null) 'recovery ${o.recovery!.round()}',
  if (o.feel != null) 'feel ${o.feel!.toStringAsFixed(1)}',
].join(' · ');

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
