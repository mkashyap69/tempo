import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Ring dial: [fraction] of a 270° arc filled.
class Dial extends StatelessWidget {
  const Dial({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    this.caption,
    this.onTap,
  });
  final String label, value;
  final String? caption;
  final double fraction;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 96,
              child: CustomPaint(
                painter: _Arc(
                  fraction.clamp(0, 1),
                  color,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Center(child: Text(value, style: t.headlineSmall)),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: t.labelLarge),
            if (caption != null) Text(caption!, style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Arc extends CustomPainter {
  _Arc(this.f, this.color, this.track);
  final double f;
  final Color color, track;

  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    const start = 0.75 * pi, sweep = 1.5 * pi;
    c.drawArc(rect.deflate(6), start, sweep, false, p..color = track);
    if (f > 0) {
      c.drawArc(rect.deflate(6), start, sweep * f, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_Arc o) => o.f != f || o.color != color;
}

/// Minimal line chart over (x, y) points.
class SimpleLine extends StatelessWidget {
  const SimpleLine({
    super.key,
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.height = 160,
    this.xLabel,
    this.step = false,
  });
  final List<FlSpot> points;
  final Color color;
  final double? minY, maxY;
  final double height;
  final String Function(double x)? xLabel;
  final bool step;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No data')),
      );
    }
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: xLabel != null,
                reservedSize: 22,
                getTitlesWidget: (x, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    xLabel?.call(x) ?? '',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points,
              color: color,
              dotData: FlDotData(show: points.length < 2),
              isStepLineChart: step,
              barWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section(this.title, this.children, {super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class Kv extends StatelessWidget {
  const Kv(this.k, this.v, {super.key});
  final String k, v;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        Text(v),
      ],
    ),
  );
}

/// White card from the screenshot. [blob] paints the orange glow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.blob = false,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final VoidCallback? onTap;
  final bool blob;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (blob)
              const Positioned(
                left: 0,
                right: 0,
                bottom: -28,
                child: Center(child: _Glow()),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow();
  @override
  Widget build(BuildContext context) => Container(
    width: 110,
    height: 70,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [Color(0xBFFF5A1F), Color(0x00FF5A1F)]),
    ),
  );
}

/// Strain 0–21 with the recovery target band drawn on top.
class StrainTrack extends StatelessWidget {
  const StrainTrack({
    super.key,
    required this.strain,
    required this.low,
    required this.high,
  });
  final double strain, low, high;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: CustomPaint(
        painter: _TrackPainter(strain.clamp(0, 21), low, high),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.strain, this.low, this.high);
  final double strain, low, high;

  @override
  void paint(Canvas c, Size s) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(6),
    );
    c.drawRRect(track, Paint()..color = const Color(0xFFEEEEF3));
    final fillW = s.width * (strain / 21);
    if (fillW > 0) {
      c.save();
      c.clipRRect(track);
      c.drawRect(
        Rect.fromLTWH(0, 0, fillW, s.height),
        Paint()..color = const Color(0xFFFF5A1F),
      );
      c.restore();
    }
    final x0 = s.width * (low / 21);
    final x1 = s.width * (high / 21);
    c.drawRect(
      Rect.fromLTRB(x0, 0, x1, s.height),
      Paint()..color = const Color(0x33FF5A1F),
    );
    final tick = Paint()
      ..color = const Color(0xFF111113)
      ..strokeWidth = 2;
    c.drawLine(Offset(x0, 0), Offset(x0, s.height), tick);
    c.drawLine(Offset(x1, 0), Offset(x1, s.height), tick);
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.strain != strain || o.low != low || o.high != high;
}
