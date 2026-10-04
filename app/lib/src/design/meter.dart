import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';
import 'type.dart';

/// One tick of a ladder.
class Tick {
  const Tick(this.color, {this.long = false, this.inTarget = false});
  final Color color;
  final bool long;
  final bool inTarget;
}

/// TempoScoreMeter: a tick ladder read bottom-up like a level meter. One tick
/// = 5 % (recovery, sleep) or 1 strain unit; every 5th tick is long. The
/// bracket on the right marks the target range. Counts up on first show
/// (m-count, out-quart), ticks lit in lock-step with the number.
class ScoreMeter extends StatefulWidget {
  const ScoreMeter({
    super.key,
    required this.label,
    required this.value,
    required this.decimals,
    this.unit = '',
    required this.state,
    this.glyph = '',
    required this.stateColor,
    required this.ticks,
    required this.filled,
    required this.fillColor,
    this.caption = '',
    this.numColor,
    this.dim = false,
    this.onTap,
    this.placeholder,
    this.tickWidth = 42,
    this.longTickWidth = 58,
    this.onSettled,
  });

  final String label;

  /// Numeric value that counts up; ignored when [placeholder] is set.
  final double value;
  final int decimals;
  final String unit, state, glyph, caption;
  final Color stateColor, fillColor;
  final Color? numColor;

  /// Ladder length (20, 21 or 14 while calibrating).
  final int ticks;

  /// Filled ticks at the final value.
  final int filled;

  final bool dim;
  final VoidCallback? onTap;

  /// Shown instead of a number ("—").
  final String? placeholder;
  final double tickWidth, longTickWidth;
  final VoidCallback? onSettled;

  @override
  State<ScoreMeter> createState() => _ScoreMeterState();
}

class _ScoreMeterState extends State<ScoreMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: TempoMotion.count,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _a,
    curve: TempoMotion.outQuart,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (context.reduceMotion) {
        _a.value = 1;
      } else {
        _a.forward().whenComplete(() => widget.onSettled?.call());
      }
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget;
    return Pressable(
      onTap: w.onTap,
      label:
          '${w.label} ${w.placeholder ?? w.value.toStringAsFixed(w.decimals)}${w.unit}, ${w.state}',
      child: AnimatedOpacity(
        duration: TempoMotion.base,
        opacity: w.dim ? .55 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(TempoRadii.lg),
          ),
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value;
              final shown = w.value * t;
              final lit = (w.filled * t).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Overline(w.label),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Opacity(
                          opacity: w.placeholder != null
                              ? 1
                              : .35 + .65 * math.min(1, t * 3),
                          child: Text(
                            w.placeholder ?? shown.toStringAsFixed(w.decimals),
                            style: TempoType.scoreM.c(w.numColor ?? c.text1),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(w.unit, style: TempoType.label.c(c.text3).tnum),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (w.glyph.isNotEmpty)
                          TextSpan(
                            text: '${w.glyph} ',
                            style: const TextStyle(fontSize: 9),
                          ),
                        TextSpan(text: w.state),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TempoType.caption.copyWith(
                      color: w.stateColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 168,
                    child: _Ladder(meter: w, lit: lit),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    w.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Ladder extends StatelessWidget {
  const _Ladder({required this.meter, required this.lit});
  final ScoreMeter meter;
  final int lit;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = meter;
    final target = m is TargetMeter ? m.targetRange : null;
    final colorFor = m is TargetMeter ? m.tickColor : null;
    return LayoutBuilder(
      builder: (context, box) {
        final scale = math.min(1.0, (box.maxWidth - 8) / m.longTickWidth);
        return Column(
          verticalDirection: VerticalDirection.up,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < m.ticks; i++)
              SizedBox(
                height: 8,
                child: Row(
                  children: [
                    _TickBar(
                      width:
                          ((i + 1) % 5 == 0 && m.ticks != 14
                              ? m.longTickWidth
                              : (m.ticks == 14 ? 50 : m.tickWidth)) *
                          scale,
                      color: i < lit
                          ? (colorFor?.call(i) ?? m.fillColor)
                          : c.trackOff,
                      grow: i == lit - 1 && m is TargetMeter && m.liveGrow,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 2,
                      height: 8,
                      color: target != null && i >= target.$1 && i < target.$2
                          ? c.text2
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TickBar extends StatelessWidget {
  const _TickBar({required this.width, required this.color, this.grow = false});
  final double width;
  final Color color;
  final bool grow;
  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    if (!grow || context.reduceMotion) return bar;
    // m-live: the newest tick scales 0.6 → 1 on a soft spring.
    return TweenAnimationBuilder<double>(
      key: ValueKey(color),
      tween: Tween(begin: .6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(
        scaleX: s,
        alignment: Alignment.centerLeft,
        child: child,
      ),
      child: bar,
    );
  }
}

/// Meter with a target bracket and per-tick colour (strain).
class TargetMeter extends ScoreMeter {
  const TargetMeter({
    super.key,
    required super.label,
    required super.value,
    required super.decimals,
    super.unit,
    required super.state,
    super.glyph,
    required super.stateColor,
    required super.ticks,
    required super.filled,
    required super.fillColor,
    super.caption,
    super.numColor,
    super.dim,
    super.onTap,
    super.placeholder,
    super.onSettled,
    this.targetRange,
    this.tickColor,
    this.liveGrow = false,
  });
  final (int, int)? targetRange;
  final Color Function(int i)? tickColor;
  final bool liveGrow;
}

/// Horizontal tick row used in detail heroes (flex ticks, long every 5th).
class TickRow extends StatelessWidget {
  const TickRow({
    super.key,
    required this.count,
    required this.filled,
    required this.color,
    this.calibration = false,
    this.colorFor,
    this.height = 28,
  });
  final int count, filled;
  final Color color;
  final bool calibration;
  final Color Function(int)? colorFor;
  final double height;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: context.reduceMotion ? 1 : 0, end: 1),
    duration: TempoMotion.count,
    curve: TempoMotion.outQuart,
    builder: (context, t, _) {
      final lit = (filled * t).round();
      return SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: calibration
                      ? 20
                      : ((i + 1) % 5 == 0 ? height : height * 18 / 28),
                  decoration: BoxDecoration(
                    color: i < lit
                        ? (colorFor?.call(i) ?? color)
                        : context.c.trackOff,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Track with a filled value, a target bracket and an optional marker.
/// Used by the Today strain strip, live workout tiles and plan landing.
class TargetStrip extends StatelessWidget {
  const TargetStrip({
    super.key,
    required this.value,
    required this.max,
    this.lo,
    this.hi,
    required this.color,
    this.marker = true,
    this.height = 12,
    this.track = 4,
    this.extra,
    this.extraColor,
  });
  final double value, max;
  final double? lo, hi;
  final Color color;
  final bool marker;
  final double height, track;

  /// Projected addition drawn after the value (55 % opacity).
  final double? extra;
  final Color? extraColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    double f(double v) => (v / max).clamp(0, 1);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final top = (height - track) / 2;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: track,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.trackOff,
                    borderRadius: BorderRadius.circular(track / 2),
                  ),
                ),
              ),
              if (lo != null && hi != null)
                Positioned(
                  left: f(lo!) * w,
                  width: (f(hi!) - f(lo!)) * w,
                  top: 0,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: c.text2, width: 1.5),
                    ),
                  ),
                ),
              if (extra != null)
                Positioned(
                  left: f(value) * w,
                  width: (f(value + extra!) - f(value)) * w,
                  top: top,
                  height: track,
                  child: Container(
                    color: (extraColor ?? color).withValues(alpha: .55),
                  ),
                ),
              Positioned(
                left: 0,
                width: f(value) * w,
                top: top,
                height: track,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(track / 2),
                  ),
                ),
              ),
              if (marker)
                Positioned(
                  left: f(value) * w - 2,
                  top: -2,
                  width: 4,
                  height: height + 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.text1,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Deviation bar centred on baseline (contributor rows).
class DeviationBar extends StatelessWidget {
  const DeviationBar({
    super.key,
    required this.left,
    required this.width,
    required this.color,
    this.height = 24,
  });

  /// Fractions 0..1 of the track.
  final double left, width;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final top = (height - 4) / 2;
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: context.c.trackOff,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: left * w,
              width: width * w,
              top: top,
              height: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: w / 2 - 1,
              top: 2,
              width: 2,
              height: height - 4,
              child: Container(color: context.c.text2),
            ),
          ],
        ),
      );
    },
  );
}

/// Simple progress bar with rounded track.
class Bar extends StatelessWidget {
  const Bar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 6,
    this.left = 0,
  });
  final double fraction, left;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Container(
      height: height,
      decoration: BoxDecoration(
        color: context.c.trackOff,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Stack(
        children: [
          Positioned(
            left: left.clamp(0, 1) * box.maxWidth,
            width: fraction.clamp(0, 1) * box.maxWidth,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Flex-segmented bar (zones, stages, need breakdown) with 2 px gaps.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.parts,
    this.height = 14,
    this.radius = 4,
  });
  final List<(num, Color)> parts;
  final double height, radius;
  @override
  Widget build(BuildContext context) {
    final nonzero = parts.where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: nonzero.isEmpty
            ? Container(color: context.c.trackOff)
            : Row(
                children: [
                  for (final (i, p) in nonzero.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (p.$1 * 100).round()),
                      child: Container(color: p.$2),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// TempoIntervalTimeline: height = zone, done segments at 40 %, playhead.
class IntervalBars extends StatelessWidget {
  const IntervalBars({
    super.key,
    required this.segments,
    this.height = 36,
    this.base = 8,
    this.step = 6,
    this.doneMinutes,
    this.playhead,
  });

  /// (minutes, zone)
  final List<(int, int)> segments;
  final double height, base, step;
  final double? doneMinutes;

  /// Fraction 0..1 for the playhead line.
  final double? playhead;

  @override
  Widget build(BuildContext context) {
    var acc = 0;
    final bars = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, (m, z)) in segments.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Builder(
            builder: (context) {
              final done = doneMinutes != null && acc + m <= doneMinutes!;
              acc += m;
              return Expanded(
                flex: m,
                child: Opacity(
                  opacity: done ? .4 : 1,
                  child: Container(
                    height: math.min(height, base + z * step),
                    decoration: BoxDecoration(
                      color: context.s.zoneColor(z),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: bars),
            if (playhead != null)
              Positioned(
                left: playhead!.clamp(0, 1) * box.maxWidth - 1.5,
                top: -6,
                bottom: -6,
                width: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.c.text1,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
