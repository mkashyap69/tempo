import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'format.dart';
import 'providers.dart';
import 'widgets.dart';

final _dayMinutesProvider =
    FutureProvider.family<(st.DailyScore?, List<st.MinuteSample>), DateTime>((
      ref,
      day,
    ) async {
      final db = ref.watch(dbProvider);
      final s = await db.scoreFor(day);
      final from = s?.sleepEnd != null ? st.fromTs(s!.sleepEnd!) : day;
      return (
        s,
        await db.minutesBetween(from, from.add(const Duration(hours: 18))),
      );
    });

class StrainDetail extends ConsumerWidget {
  const StrainDetail({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dayMinutesProvider(day));
    return Scaffold(
      appBar: AppBar(title: const Text('Strain')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final (score, minutes) = d;
          final rest = score?.rhr ?? 60;
          final max = (score?.hrMax ?? 190).toDouble();
          final withHr = minutes.where((m) => m.hr != null).toList();
          final t0 = withHr.isEmpty ? 0 : withHr.first.ts;
          double x(int ts) => (ts - t0) / 3600;
          final zones = List.filled(6, 0);
          var cum = 0.0;
          final build = <FlSpot>[];
          for (final m in withHr) {
            zones[zoneFor(m.hr!, rest, max)]++;
            cum += sc.minuteTrimp(m.hr!, hrRest: rest, hrMax: max);
            build.add(FlSpot(x(m.ts), sc.strainFromTrimp(cum)));
          }
          String label(double h) => clock(st.fromTs(t0 + (h * 3600).round()));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Section('Day strain ${n1(score?.strain)}', [
                Kv('TRIMP', n1(score?.trimp)),
                Kv('HR max used', '${max.round()} bpm'),
                Kv('Resting HR used', '${rest.round()} bpm'),
                const Text(
                  'Wrist HR lags in intervals and lifting: treat workout strain as an estimate.',
                  style: TextStyle(fontSize: 12),
                ),
              ]),
              Section('Heart rate', [
                SimpleLine(
                  points: [
                    for (final m in withHr) FlSpot(x(m.ts), m.hr!.toDouble()),
                  ],
                  color: Colors.red,
                  xLabel: label,
                ),
              ]),
              Section('Strain build-up', [
                SimpleLine(
                  points: build,
                  color: strainColour,
                  minY: 0,
                  maxY: 21,
                  xLabel: label,
                ),
              ]),
              Section('Time in zones (% HR reserve)', [
                for (var z = 5; z >= 0; z--)
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          z == 0
                              ? '< 50%'
                              : 'Z$z ${(zoneBounds[z - 1] * 100).round()}%+',
                        ),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: withHr.isEmpty ? 0 : zones[z] / withHr.length,
                          color: zoneColours[z],
                          minHeight: 10,
                        ),
                      ),
                      SizedBox(width: 56, child: Text(' ${zones[z]} min')),
                    ],
                  ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
