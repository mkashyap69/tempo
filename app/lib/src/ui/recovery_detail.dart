import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'format.dart';
import 'providers.dart';
import 'widgets.dart';

final _recoveryProvider =
    FutureProvider.family<(st.DailyScore?, List<st.DailyScore>), DateTime>((
      ref,
      day,
    ) async {
      final db = ref.watch(dbProvider);
      return (await db.scoreFor(day), await db.scoresBefore(day, limit: 30));
    });

class RecoveryDetail extends ConsumerWidget {
  const RecoveryDetail({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_recoveryProvider(day));
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final (s, prev) = d;
          Widget input(
            String name,
            double? v,
            Iterable<double?> hist,
            bool higherBetter,
            double w,
            String unit,
          ) {
            final b = sc.Baseline.of(hist);
            final z = sc.RecoveryInput(
              value: v,
              baseline: b,
              higherIsBetter: higherBetter,
              weight: w,
            ).z;
            return Section('$name · weight ${(w * 100).round()}%', [
              Kv(
                'Last night',
                v == null ? '–' : '${v.toStringAsFixed(1)} $unit',
              ),
              Kv(
                '30-day baseline',
                b == null
                    ? '–'
                    : '${b.mean.toStringAsFixed(1)} ± ${b.sd.toStringAsFixed(1)}',
              ),
              Kv(
                'Score (z, + is better)',
                z == null ? '–' : z.toStringAsFixed(2),
              ),
              Text(
                higherBetter ? 'Higher is better' : 'Lower is better',
                style: const TextStyle(fontSize: 12),
              ),
            ]);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Section(
                'Recovery ${s?.calibrating ?? true ? 'calibrating' : '${n0(s?.recovery)}%'}',
                [
                  Text(
                    'Built from last night against your own 30-day baseline. '
                    'HRV is a proxy from the band\'s stress index; the band does not expose raw HRV.',
                  ),
                  Kv(
                    'Nights of history',
                    '${prev.where((p) => p.sleptHours != null).length} (need 14)',
                  ),
                ],
              ),
              input(
                'HRV proxy (stress during sleep)',
                s?.hrvProxy,
                prev.map((p) => p.hrvProxy),
                false,
                0.4,
                '',
              ),
              input(
                'Resting HR',
                s?.rhr,
                prev.map((p) => p.rhr),
                false,
                0.3,
                'bpm',
              ),
              input(
                'Sleep performance',
                s?.sleepPerf,
                prev.map((p) => p.sleepPerf),
                true,
                0.3,
                '%',
              ),
            ],
          );
        },
      ),
    );
  }
}
