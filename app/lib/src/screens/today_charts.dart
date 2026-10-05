import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'cardio_load.dart';
import 'nav.dart';
import 'recovery.dart';
import 'shared.dart' show loadColor;
import 'sleep.dart';
import 'strain.dart';

/// Today, design B: recovery, strain and sleep as three nested rings with
/// a legend. Recovery is the outer ring in its state colour; strain marks
/// today's target band; sleep is the share of need.
class TodayRings extends StatelessWidget {
  const TodayRings({
    super.key,
    required this.t,
    required this.noData,
    this.dim = false,
  });
  final TodayData t;
  final bool noData, dim;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final r = t.recovery;
    final calibrating = !noData && t.calibrating;
    final recColor = noData
        ? c.trackOff
        : calibrating || r == null
        ? c.text2
        : s.recoveryFor(r);
    final recFrac = noData
        ? 0.0
        : calibrating
        ? t.nights / 14
        : (r ?? 0) / 100;
    final strainColor = s.strain[2];
    final sp = t.sleepPerf;
    final rings = [
      RingSpec(recFrac, recColor),
      RingSpec(
        noData ? 0 : t.strain / 21,
        strainColor,
        marks: noData || t.firstDay
            ? const []
            : [t.target.lo / 21, if (!t.target.cap) t.target.hi / 21],
      ),
      RingSpec(noData || sp == null ? 0 : sp / 100, s.sleepChannel),
    ];

    final (big, word) = noData
        ? ('—', 'No data')
        : calibrating
        ? ('${t.nights}/14', 'Calibrating')
        : r == null
        ? ('—', 'After tonight')
        : ('${r.round()}%', recoveryWord(r));

    final ringsWidget = Semantics(
      label: noData
          ? 'No data yet'
          : 'Recovery $big, strain ${n1(t.strain)}, sleep ${sp == null ? 'no data' : '${sp.round()} percent'}',
      child: NestedRings(
        size: 196,
        rings: rings,
        center: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              big,
              style: TempoType.scoreL.copyWith(
                fontSize: 34,
                height: 1.1,
                color: dim ? c.text2 : c.text1,
              ),
            ),
            Text(word, style: TempoType.caption.c(c.text2)),
          ],
        ),
      ),
    );

    final tg = t.target;
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendItem(
          label: 'RECOVERY',
          color: noData ? c.text3 : recColor,
          value: big,
          sub: noData
              ? ''
              : calibrating
              ? '${14 - t.nights} nights to baseline'
              : _rhrLine(t),
          onTap: noData ? null : () => push(context, const RecoveryScreen()),
        ),
        const SizedBox(height: 14),
        _LegendItem(
          label: 'STRAIN',
          color: noData ? c.text3 : strainColor,
          value: noData ? '—' : n1(t.strain),
          trailing: noData || t.firstDay
              ? null
              : tg.cap
              ? ' / cap ${tg.hi.round()}'
              : ' / ${tg.lo.round()}–${tg.hi.round()}',
          sub: noData ? '' : 'of 21',
          onTap: noData ? null : () => push(context, const StrainScreen()),
        ),
        const SizedBox(height: 14),
        _LegendItem(
          label: 'SLEEP',
          color: noData ? c.text3 : s.sleepChannel,
          value: noData || sp == null ? '—' : '${sp.round()}%',
          sub: noData
              ? ''
              : sp == null
              ? 'Wear the band tonight'
              : '${hmShort(t.slept!)} of ${hmShort(t.need!)}',
          onTap: noData ? null : () => push(context, const SleepScreen()),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 330
          ? Column(children: [ringsWidget, const SizedBox(height: 16), legend])
          : Row(
              children: [
                ringsWidget,
                const SizedBox(width: 16),
                Expanded(child: legend),
              ],
            ),
    );
  }

  static String _rhrLine(TodayData t) {
    final d = t.rhrDelta;
    if (d == null) return '';
    final n = d.round();
    return 'RHR ${n == 0
        ? '±0'
        : n > 0
        ? '+$n'
        : '−${-n}'} vs normal';
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
    required this.value,
    required this.sub,
    this.trailing,
    this.onTap,
  });
  final String label, value, sub;
  final String? trailing;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      label: '$label $value',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TempoType.overline.copyWith(color: color)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value),
                if (trailing != null)
                  TextSpan(text: trailing, style: TempoType.caption.c(c.text3)),
              ],
            ),
            style: TempoType.titleL
                .copyWith(fontWeight: FontWeight.w300, color: c.text1)
                .tnum,
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TempoType.caption.c(c.text3),
            ),
        ],
      ),
    );
  }
}

/// One ring: [fraction] 0–1 of a full turn, plus optional tick [marks]
/// (fractions) drawn across the ring, e.g. a target band.
class RingSpec {
  const RingSpec(this.fraction, this.color, {this.marks = const []});
  final double fraction;
  final Color color;
  final List<double> marks;
}

/// Concentric rings, outermost first, drawing in on first build.
class NestedRings extends StatelessWidget {
  const NestedRings({
    super.key,
    required this.size,
    required this.rings,
    this.center,
    this.stroke = 15,
    this.gap = 5,
  });
  final double size, stroke, gap;
  final List<RingSpec> rings;
  final Widget? center;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: context.reduceMotion ? 1 : 0, end: 1),
      duration: TempoMotion.draw,
      curve: TempoMotion.easeOut,
      builder: (context, k, child) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingsPainter(rings, k, stroke, gap, c.dark),
          child: Center(child: child),
        ),
      ),
      child: center,
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings, this.k, this.stroke, this.gap, this.dark);
  final List<RingSpec> rings;
  final double k, stroke, gap;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final o = size.center(Offset.zero);
    var r = size.width / 2 - stroke / 2;
    for (final ring in rings) {
      final rect = Rect.fromCircle(center: o, radius: r);
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ring.color.withValues(alpha: dark ? .18 : .16);
      canvas.drawCircle(o, r, track);
      final f = (ring.fraction.clamp(0.0, 1.0)) * k;
      if (f > 0) {
        canvas.drawArc(
          rect,
          -math.pi / 2,
          math.max(f * 2 * math.pi, .02),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = ring.color,
        );
      }
      for (final m in ring.marks) {
        final a = -math.pi / 2 + m.clamp(0.0, 1.0) * 2 * math.pi;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          o + dir * (r - stroke / 2 - 2),
          o + dir * (r + stroke / 2 + 2),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = dark ? const Color(0xFFF3F2EF) : const Color(0xFF121316),
        );
      }
      r -= stroke + gap;
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.k != k || old.rings != rings || old.dark != dark;
}

/// Last 7 days: a recovery bar (in its state colour) and a strain bar per
/// day. Calibrating days show only strain.
class WeekRecoveryStrain extends StatelessWidget {
  const WeekRecoveryStrain({super.key, required this.t});
  final TodayData t;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final byDate = {for (final d in t.last7) d.date: d};
    final days = [
      for (var i = 6; i >= 0; i--) t.day.subtract(Duration(days: i)),
    ];
    const h = 76.0;
    return TempoCard(
      onTap: () => push(context, const RecoveryScreen()),
      label: 'Last 7 days of recovery and strain',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Last 7 days', style: TempoType.label.c(c.text1)),
              ),
              _Key(colors: [s.recHigh, s.recMid, s.recLow], text: 'recovery'),
              const SizedBox(width: 10),
              _Key(colors: [s.strain[2]], text: 'strain'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: h + 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final row = byDate[st.dateKey(d)];
                        final rec = row == null || row.calibrating
                            ? null
                            : row.recovery;
                        final strain = row?.strain ?? 0;
                        final today = d == t.day;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _Bar(
                                  height: rec == null
                                      ? 3
                                      : math.max(3, rec / 100 * h),
                                  color: rec == null
                                      ? c.trackOff
                                      : s.recoveryFor(rec),
                                ),
                                const SizedBox(width: 3),
                                _Bar(
                                  height: math.max(3, strain / 21 * h),
                                  color: row == null ? c.trackOff : s.strain[2],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'MTWTFSS'[d.weekday - 1],
                              style: TempoType.caption.c(
                                today ? c.text1 : c.text3,
                              ),
                            ),
                          ],
                        );
                      },
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

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});
  final double height;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key({required this.colors, required this.text});
  final List<Color> colors;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, col) in colors.indexed)
        Container(
          width: 8,
          height: 8,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
          decoration: BoxDecoration(
            color: col,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      const SizedBox(width: 5),
      Text(text, style: TempoType.caption.c(context.c.text3)),
    ],
  );
}

/// Today's time in heart-rate zones as a donut, total in the middle.
class ZoneDonutCard extends ConsumerWidget {
  const ZoneDonutCard({super.key, required this.t});
  final TodayData t;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final d = ref.watch(strainDayProvider(t.day)).value;
    final zones = d?.zones ?? const [0, 0, 0, 0, 0];
    final total = zones.fold<int>(0, (a, b) => a + b);
    return TempoCard(
      padding: const EdgeInsets.all(14),
      onTap: () => push(context, const StrainScreen()),
      label: 'Time in zones today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Time in zones', style: TempoType.caption.c(c.text2)),
          const SizedBox(height: 8),
          Center(
            child: Semantics(
              label: total == 0
                  ? 'No time in zones yet'
                  : '$total minutes in zones: ${[for (var i = 0; i < 5; i++) 'zone ${i + 1} ${zones[i]}'].join(', ')}',
              child: SizedBox.square(
                dimension: 104,
                child: CustomPaint(
                  painter: _DonutPainter([
                    for (var i = 0; i < 5; i++) (zones[i], s.zone[i]),
                  ], c.trackOff),
                  child: Center(
                    child: Text(
                      total == 0
                          ? '0m'
                          : mmssShort(total).replaceAll(' min', 'm'),
                      style: TempoType.label
                          .copyWith(fontSize: 16, color: c.text1)
                          .tnum,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 5; i++)
                Text(
                  'Z${i + 1}',
                  style: TempoType.caption
                      .c(zones[i] > 0 ? s.zone[i] : c.text3)
                      .tnum,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.track);
  final List<(int, Color)> parts;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    const w = 13.0;
    final o = size.center(Offset.zero);
    final r = size.width / 2 - w / 2;
    final rect = Rect.fromCircle(center: o, radius: r);
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    if (total == 0) {
      canvas.drawCircle(o, r, paint..color = track);
      return;
    }
    final shown = parts.where((p) => p.$1 > 0).length;
    final gap = shown > 1 ? .04 : 0.0;
    var a = -math.pi / 2;
    for (final (v, col) in parts) {
      if (v == 0) continue;
      final sweep = v / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        a + gap / 2,
        math.max(sweep - gap, .01),
        false,
        paint..color = col,
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// Cardio load as a half gauge: 7-day load against 28-day, 0–2×, with the
/// productive band (0.8–1.3×) marked.
class LoadGaugeCard extends StatelessWidget {
  const LoadGaugeCard({super.key, required this.t});
  final TodayData t;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final load = t.load;
    final learning = load.status == sc.LoadStatus.learning || t.firstDay;
    final color = learning ? c.text3 : loadColor(context, load.status);
    return TempoCard(
      padding: const EdgeInsets.all(14),
      onTap: () => push(context, const CardioLoadScreen()),
      label: 'Cardio load',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cardio load', style: TempoType.caption.c(c.text2)),
          const SizedBox(height: 12),
          Semantics(
            label: learning
                ? 'Cardio load: learning'
                : 'Cardio load ${load.ratio.toStringAsFixed(2)} times your normal, ${loadWord(load.status)}',
            child: SizedBox(
              height: 74,
              child: CustomPaint(
                painter: _GaugePainter(
                  learning ? 0 : load.ratio / 2,
                  color,
                  c.trackOff,
                  c.text2,
                ),
                child: Align(
                  alignment: const Alignment(0, .9),
                  child: Text(
                    learning ? '—' : '${load.ratio.toStringAsFixed(2)}×',
                    style: TempoType.titleM
                        .copyWith(fontWeight: FontWeight.w300, color: c.text1)
                        .tnum,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            learning
                ? 'Needs 7 days'
                : '${loadGlyph(load.status)} ${loadWord(load.status)}',
            style: TempoType.caption.c(color),
          ),
          Text('7 days vs your 28', style: TempoType.caption.c(c.text3)),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.f, this.color, this.track, this.mark);
  final double f;
  final Color color, track, mark;
  @override
  void paint(Canvas canvas, Size size) {
    const w = 10.0;
    final r = math.min(size.width / 2, size.height) - w / 2;
    final o = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: o, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    final ff = f.clamp(0.0, 1.0);
    if (ff > 0) {
      canvas.drawArc(rect, math.pi, ff * math.pi, false, p..color = color);
    }
    // Productive band edges at 0.8× and 1.3× (of a 0–2× dial).
    for (final x in [.4, .65]) {
      final a = math.pi + x * math.pi;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        o + d * (r - w / 2 - 3),
        o + d * (r + w / 2 + 3),
        Paint()
          ..strokeWidth = 1.5
          ..color = mark,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.f != f || old.color != color;
}

/// Last night: duration, sleep performance, the stages in order as one
/// strip, and tonight's bedtime.
class LastNightStrip extends ConsumerWidget {
  const LastNightStrip({super.key, required this.t});
  final TodayData t;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final night = ref.watch(nightProvider(t.day)).value;
    Color stageColor(sc.Stage st) => switch (st) {
      sc.Stage.deep => s.sleepDeep,
      sc.Stage.rem => s.sleepRem,
      sc.Stage.light => s.sleepLight,
      _ => s.sleepAwake,
    };
    // Runs of the same stage, in time order.
    final runs = <(sc.Stage, int)>[];
    for (final m in night?.minutes ?? const <sc.Minute>[]) {
      final stg = m.stage.asleep ? m.stage : sc.Stage.wake;
      if (runs.isNotEmpty && runs.last.$1 == stg) {
        runs[runs.length - 1] = (stg, runs.last.$2 + 1);
      } else {
        runs.add((stg, 1));
      }
    }
    final empty = night == null || night.empty;
    String dur(sc.Stage st) => hmShort(night!.stage(st).inMinutes / 60);
    return TempoCard(
      color: Color.alphaBlend(s.tintSleep, c.surface1),
      onTap: () => push(context, const SleepScreen()),
      label: 'Last night',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  empty
                      ? 'Last night'
                      : 'Last night · ${hmShort(t.slept ?? night.session.asleep.inMinutes / 60)}',
                  style: TempoType.label.c(c.text1).tnum,
                ),
              ),
              if (t.sleepPerf != null)
                Text(
                  '${t.sleepPerf!.round()}%',
                  style: TempoType.label.c(s.sleepChannel).tnum,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (empty)
            Text(
              'No sleep yet. Wear your band tonight.',
              style: TempoType.bodyS.c(c.text2),
            )
          else ...[
            Semantics(
              label:
                  'Stages: deep ${dur(sc.Stage.deep)}, REM ${dur(sc.Stage.rem)}, light ${dur(sc.Stage.light)}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (stg, n) in runs)
                        Expanded(
                          flex: n,
                          child: ColoredBox(color: stageColor(stg)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (name, stg) in [
                  ('Deep', sc.Stage.deep),
                  ('REM', sc.Stage.rem),
                  ('Light', sc.Stage.light),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stageColor(stg),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$name ${dur(stg)}',
                        style: TempoType.caption.c(c.text2).tnum,
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Tonight: bed by ${clock12(t.bedtimeMinute)} · need ${hmShort(t.needTonight)}',
            style: TempoType.caption.c(c.text2).tnum,
          ),
        ],
      ),
    );
  }
}
