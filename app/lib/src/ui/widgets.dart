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
              dotData: const FlDotData(show: false),
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
