import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/score_service.dart';
import 'format.dart';
import 'providers.dart';
import 'widgets.dart';

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});
  @override
  ConsumerState<TrendsScreen> createState() => _TrendsState();
}

class _TrendsState extends ConsumerState<TrendsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final scores = ref.watch(recentScoresProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 d')),
              ButtonSegment(value: 30, label: Text('30 d')),
              ButtonSegment(value: 90, label: Text('90 d')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 12),
          ...scores.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text('$e')],
            data: (rows) {
              final t0 = DateTime.now().subtract(Duration(days: _days - 1));
              final start = DateTime(t0.year, t0.month, t0.day);
              double x(st.DailyScore d) =>
                  parseDateKey(d.date).difference(start).inDays.toDouble();
              List<FlSpot> pts(double? Function(st.DailyScore) f) => [
                for (final d in rows)
                  if (f(d) != null) FlSpot(x(d), f(d)!),
              ];
              String label(double v) =>
                  shortDate(start.add(Duration(days: v.round())));
              Widget chart(
                String title,
                List<FlSpot> p,
                Color c, {
                double? min,
                double? max,
              }) => Section(title, [
                SimpleLine(
                  points: p,
                  color: c,
                  minY: min,
                  maxY: max,
                  xLabel: label,
                ),
              ]);
              return [
                chart(
                  'Recovery %',
                  pts((d) => d.calibrating ? null : d.recovery),
                  const Color(0xFF16A34A),
                  min: 0,
                  max: 100,
                ),
                chart(
                  'Strain',
                  pts((d) => d.strain),
                  strainColour,
                  min: 0,
                  max: 21,
                ),
                chart(
                  'Sleep performance %',
                  pts((d) => d.sleepPerf),
                  sleepColour,
                  min: 0,
                  max: 100,
                ),
                chart('Resting HR', pts((d) => d.rhr), Colors.red),
                chart(
                  'Stress during sleep (HRV proxy)',
                  pts((d) => d.hrvProxy),
                  Colors.orange,
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}
