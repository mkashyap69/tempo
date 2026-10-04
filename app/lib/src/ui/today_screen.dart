import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import 'format.dart';
import 'providers.dart';
import 'recovery_detail.dart';
import 'sleep_detail.dart';
import 'strain_detail.dart';
import 'theme.dart';
import 'widgets.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dayOf(DateTime.now());
    final score = ref.watch(scoreProvider(today));
    final steps = ref.watch(stepsProvider(today));
    final week = ref.watch(recentScoresProvider(7));
    final sync = ref.watch(syncProvider);
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      body: SafeArea(
        child: score.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (s) {
            final rec = s?.recovery;
            final calibrating = s?.calibrating ?? true;
            final ready = s != null && !calibrating && rec != null;
            final band = ready ? sc.targetStrain(sc.recoveryColor(rec)) : null;
            final coaching = s == null
                ? 'No data yet. Sync your band.'
                : !ready
                ? 'Calibrating: recovery needs 14 nights of data.'
                : _call(rec, s.strain, band!);
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 108),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today, ${_months[today.month - 1]} ${today.day}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sync now',
                      onPressed: sync.running
                          ? null
                          : () => ref.read(syncProvider.notifier).syncNow(),
                      icon: sync.running
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                    ),
                  ],
                ),
                if (sync.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      sync.message!,
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    _Metric(
                      title: 'Activity',
                      value: _stepsLabel(steps),
                      blob: true,
                      onTap: () => open(StrainDetail(day: today)),
                    ),
                    _Metric(
                      title: 'Strain',
                      value: n1(s?.strain),
                      unit: s?.strain == null ? null : '/ 21',
                      onTap: () => open(StrainDetail(day: today)),
                      footer: _Bars(
                        values: [
                          for (final d in week.value ?? const []) d.strain,
                        ],
                      ),
                    ),
                    _Metric(
                      title: 'Sleep',
                      value: s?.sleepPerf == null
                          ? '–'
                          : '${s!.sleepPerf!.round()}%',
                      caption: hm(s?.sleptHours),
                      onTap: () => open(SleepDetail(day: today)),
                    ),
                    _Metric(
                      title: 'Recovery',
                      value: rec == null ? '–' : '${rec.round()}%',
                      caption: calibrating ? 'Calibrating' : null,
                      onTap: () => open(RecoveryDetail(day: today)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SoftCard(
                  onTap: () => open(RecoveryDetail(day: today)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        coaching,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      if (band != null && s?.strain != null) ...[
                        const SizedBox(height: 10),
                        StrainTrack(
                          strain: s!.strain,
                          low: band.low,
                          high: band.high,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Target ${band.low.toStringAsFixed(0)}–${band.high.toStringAsFixed(0)}'
                          ' · ${(band.high - s.strain).clamp(0, 21).toStringAsFixed(1)} left',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  onTap: () => open(SleepDetail(day: today)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last night',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s?.sleptHours == null
                            ? 'No sleep yet'
                            : '${hm(s!.sleptHours)} asleep',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (s?.needHours != null)
                        Text(
                          'Need was ${hm(s!.needHours)}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _stepsLabel(AsyncValue<int> steps) => steps.maybeWhen(
  data: (n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n',
  orElse: () => '–',
);

String _call(double rec, double strain, ({double low, double high}) band) {
  final verb = switch (sc.recoveryColor(rec)) {
    sc.RecoveryColor.green => 'Train',
    sc.RecoveryColor.yellow => 'Go easy',
    sc.RecoveryColor.red => 'Rest',
  };
  return '$verb. Recovery ${rec.round()}%, strain ${strain.toStringAsFixed(1)}.';
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    this.unit,
    this.caption,
    this.onTap,
    this.blob = false,
    this.footer,
  });
  final String title, value;
  final String? unit, caption;
  final VoidCallback? onTap;
  final bool blob;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      blob: blob,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          if (caption != null)
            Text(caption!, style: const TextStyle(fontSize: 11, color: muted)),
          ?footer,
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV = values.fold<double>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 4 + 16 * (v / maxV),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
