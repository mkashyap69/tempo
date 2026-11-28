import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/body.dart' show loadWeightTrend;
import '../core/coach_service.dart' show dayOf;
import '../core/format.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'cardio_load.dart';
import 'labs.dart' show LabsScreen, labsProvider;
import 'nav.dart';
import 'shared.dart' show loadColor;
import 'sleep.dart';
import 'trends.dart' show TrendsScreen;

final _weightProvider = FutureProvider<sc.WeightTrend?>((ref) {
  ref.watch(dbTickProvider);
  return loadWeightTrend(ref.watch(dbProvider));
});

/// The last 30 days of scores, oldest first.
final scores30Provider = FutureProvider<List<st.DailyScore>>((ref) {
  ref.watch(dbTickProvider);
  final today = dayOf(DateTime.now());
  return ref
      .watch(dbProvider)
      .scoresBetween(today.subtract(const Duration(days: 29)), today);
});

/// v3 Health (canvas "Health"): sleep, fitness, weight and blood as four
/// tiles, each opening its screen.
class HealthTiles extends ConsumerWidget {
  const HealthTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final t = ref.watch(todayProvider).value;
    final w = ref.watch(_weightProvider).value;
    final labs = ref.watch(labsProvider).value?.$1 ?? const [];
    final nights = [
      for (final d in t?.last7 ?? const <st.DailyScore>[]) d.sleptHours,
    ];
    final slept = [
      for (final h in nights)
        if (h != null && h > 0) h,
    ];
    final avg = slept.isEmpty
        ? null
        : slept.reduce((a, b) => a + b) / slept.length;
    final load = t?.load.status;

    Widget tile({
      required String label,
      required String value,
      required String sub,
      Widget? art,
      Color? subColor,
      required VoidCallback onTap,
    }) => Expanded(
      child: TempoCard(
        label: label,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          height: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TempoType.caption.c(c.text2)),
              const SizedBox(height: 2),
              Text(value, style: TempoType.titleM.c(c.text1).tnum),
              const Spacer(),
              ?art,
              const SizedBox(height: 6),
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TempoType.caption.c(subColor ?? c.text3),
              ),
            ],
          ),
        ),
      ),
    );

    final maxH = slept.isEmpty ? 1.0 : slept.reduce(math.max);
    final bars = SizedBox(
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in nights) ...[
            Expanded(
              child: Container(
                height: h == null || h <= 0 ? 2 : 30 * (h / maxH),
                decoration: BoxDecoration(
                  color: h == null || h <= 0 ? c.surface3 : s.sleepChannel,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
    final latest = labs.isEmpty
        ? null
        : (labs.toList()..sort((a, b) => b.date.compareTo(a.date))).first;
    return Column(
      key: const ValueKey('health-tiles'),
      children: [
        Row(
          children: [
            tile(
              label: 'Sleep · 7 nights',
              value: avg == null ? '—' : hmShort(avg),
              sub: avg == null ? 'No nights yet' : 'average a night',
              art: bars,
              onTap: () => push(context, const SleepScreen()),
            ),
            const SizedBox(width: 10),
            tile(
              label: 'Fitness',
              value: load == null ? '—' : loadWord(load),
              sub: load == null || load == sc.LoadStatus.learning
                  ? 'Learning your normal load'
                  : 'training load vs your usual',
              subColor: load == null ? null : loadColor(context, load),
              onTap: () => push(context, const CardioLoadScreen()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile(
              label: 'Weight',
              value: w == null ? '—' : '${w.weekMean.toStringAsFixed(1)} kg',
              sub: w == null
                  ? 'Add a scale to Health'
                  : w.change4w == null
                  ? '7-day average'
                  : '${w.change4w! >= 0 ? '+' : '−'}${w.change4w!.abs().toStringAsFixed(1)} kg in 4 weeks',
              onTap: () => push(context, const TrendsScreen()),
            ),
            const SizedBox(width: 10),
            tile(
              label: 'Blood',
              value: latest == null ? '—' : dm(latest.date),
              sub: latest == null ? 'Add a blood test' : 'latest test',
              onTap: () => push(context, const LabsScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

/// v3 Metric: the last 30 days of [values] with your normal as a band
/// ([lo]–[hi]) and the latest day as a dot.
class NormalBandChart extends StatelessWidget {
  const NormalBandChart({
    super.key,
    required this.values,
    this.lo,
    this.hi,
    this.height = 140,
  });
  final List<double?> values;
  final double? lo, hi;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BandPainter(
          values: values,
          lo: lo,
          hi: hi,
          band: c.text2.withValues(alpha: .16),
          line: s.recHigh,
          dot: c.text1,
          grid: c.line,
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.values,
    required this.lo,
    required this.hi,
    required this.band,
    required this.line,
    required this.dot,
    required this.grid,
  });
  final List<double?> values;
  final double? lo, hi;
  final Color band, line, dot, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final (i, v) in values.indexed)
        if (v != null) (i, v),
    ];
    if (pts.isEmpty) return;
    var mn = pts.map((p) => p.$2).reduce(math.min);
    var mx = pts.map((p) => p.$2).reduce(math.max);
    if (lo != null) mn = math.min(mn, lo!);
    if (hi != null) mx = math.max(mx, hi!);
    final pad = (mx - mn).abs() < 1e-6 ? 1.0 : (mx - mn) * .15;
    mn -= pad;
    mx += pad;
    double y(double v) => size.height - (v - mn) / (mx - mn) * size.height;
    double x(int i) =>
        values.length <= 1 ? 0 : i / (values.length - 1) * size.width;
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()..color = grid,
    );
    if (lo != null && hi != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(hi!), size.width, y(lo!)),
        Paint()..color = band,
      );
    }
    final path = Path()..moveTo(x(pts.first.$1), y(pts.first.$2));
    for (final p in pts.skip(1)) {
      path.lineTo(x(p.$1), y(p.$2));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = line,
    );
    final last = pts.last;
    canvas.drawCircle(
      Offset(x(last.$1), y(last.$2)),
      4.5,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.values != values || old.lo != lo || old.hi != hi;
}
