import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'format.dart';
import 'providers.dart';
import 'theme.dart';
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
      appBar: AppBar(
        title: const Text(
          'Recovery Engine',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final (s, prev) = d;
          final rec = s?.recovery;
          final calibrating = s?.calibrating ?? true;
          final color = recoveryColour(calibrating ? null : rec);
          final nights = prev.where((p) => p.sleptHours != null).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // 1. Hero Recovery Radial Ring
              SoftCard(
                blob: true,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    const Text(
                      'AUTONOMIC RECOVERY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox.square(
                      dimension: 110,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: (rec ?? 0) / 100,
                            strokeWidth: 9,
                            backgroundColor: const Color(0xFFF0F0F5),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rec == null ? '–' : '${rec.round()}%',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: color,
                                ),
                              ),
                              Text(
                                calibrating
                                    ? 'CALIBRATING'
                                    : sc.recoveryColor(rec!).name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      calibrating
                          ? '14-Day Baseline Calibration'
                          : rec! >= 67
                          ? 'Optimal Autonomic Capacity'
                          : rec >= 34
                          ? 'Moderate Capacity'
                          : 'Rest Recommended',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$nights of 14 nights required for full baseline calibration.',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Weighted Z-Score Decomposition Card
              SoftCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biomarker Z-Score Contributions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Each input is compared against your rolling 30-day mean.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 16),

                    // Metric 1: Sleep Stress Index (HRV proxy)
                    _ZScoreItem(
                      title: 'HRV Proxy (Sleep Stress)',
                      weight: 0.40,
                      val: s?.hrvProxy,
                      hist: prev.map((p) => p.hrvProxy),
                      higherBetter: false,
                      unit: '',
                    ),
                    const Divider(height: 24),

                    // Metric 2: Resting HR
                    _ZScoreItem(
                      title: 'Resting Heart Rate',
                      weight: 0.30,
                      val: s?.rhr,
                      hist: prev.map((p) => p.rhr),
                      higherBetter: false,
                      unit: 'bpm',
                    ),
                    const Divider(height: 24),

                    // Metric 3: Sleep Performance
                    _ZScoreItem(
                      title: 'Sleep Performance',
                      weight: 0.30,
                      val: s?.sleepPerf,
                      hist: prev.map((p) => p.sleepPerf),
                      higherBetter: true,
                      unit: '%',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Technical note
              const SoftCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How Mi Band 6 Recovery works',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'The Mi Band 6 does not stream raw beat-to-beat RR intervals. '
                      'Tempo uses the band\'s validated stress-during-sleep index as an autonomic HRV proxy. '
                      'Scores are derived through a logistic transformation of weighted z-scores.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ZScoreItem extends StatelessWidget {
  const _ZScoreItem({
    required this.title,
    required this.weight,
    required this.val,
    required this.hist,
    required this.higherBetter,
    required this.unit,
  });
  final String title, unit;
  final double weight;
  final double? val;
  final Iterable<double?> hist;
  final bool higherBetter;

  @override
  Widget build(BuildContext context) {
    final b = sc.Baseline.of(hist);
    final z = sc.RecoveryInput(
      value: val,
      baseline: b,
      higherIsBetter: higherBetter,
      weight: weight,
    ).z;

    final zScoreLabel = z == null
        ? '–'
        : '${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}';
    // Visual bar fraction (clamp z between -2.0 and +2.0)
    final barFraction = z == null ? 0.5 : ((z + 2.0) / 4.0).clamp(0.05, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$title (Weight ${(weight * 100).round()}%)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            Text(
              'z = $zScoreLabel',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: z == null
                    ? muted
                    : z >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: barFraction,
              backgroundColor: const Color(0xFFEEEEF3),
              valueColor: AlwaysStoppedAnimation(
                z == null
                    ? muted
                    : z >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              val == null
                  ? 'Last night: –'
                  : 'Last night: ${val!.toStringAsFixed(1)} $unit',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
            Text(
              b == null
                  ? 'Baseline: –'
                  : '30d mean: ${b.mean.toStringAsFixed(1)} ± ${b.sd.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      ],
    );
  }
}
