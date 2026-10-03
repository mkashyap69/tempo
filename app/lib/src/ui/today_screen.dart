import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import 'format.dart';
import 'live_workout_screen.dart';
import 'providers.dart';
import 'recovery_detail.dart';
import 'sleep_detail.dart';
import 'strain_detail.dart';
import 'widgets.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dayOf(DateTime.now());
    final score = ref.watch(scoreProvider(today));
    final sync = ref.watch(syncProvider);
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: sync.running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: sync.running
                ? null
                : () => ref.read(syncProvider.notifier).syncNow(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(const LiveWorkoutScreen()),
        icon: const Icon(Icons.favorite),
        label: const Text('Workout'),
      ),
      body: score.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          final rec = s?.recovery;
          final calibrating = s?.calibrating ?? true;
          final coaching = s == null
              ? 'No data yet. Sync your band.'
              : calibrating || rec == null
              ? 'Calibrating: recovery needs 14 nights of data.'
              : () {
                  final t = sc.targetStrain(sc.recoveryColor(rec));
                  return 'Recovery ${rec.round()}%, aim for strain '
                      '${t.low.round()}–${t.high.round()}.';
                }();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Dial(
                    label: 'Recovery',
                    value: calibrating || rec == null ? '–' : '${rec.round()}%',
                    caption: calibrating ? 'Calibrating' : null,
                    fraction: (rec ?? 0) / 100,
                    color: recoveryColour(calibrating ? null : rec),
                    onTap: () => open(RecoveryDetail(day: today)),
                  ),
                  Dial(
                    label: 'Strain',
                    value: n1(s?.strain),
                    fraction: (s?.strain ?? 0) / 21,
                    color: strainColour,
                    onTap: () => open(StrainDetail(day: today)),
                  ),
                  Dial(
                    label: 'Sleep',
                    value: s?.sleepPerf == null
                        ? '–'
                        : '${s!.sleepPerf!.round()}%',
                    caption: hm(s?.sleptHours),
                    fraction: (s?.sleepPerf ?? 0) / 100,
                    color: sleepColour,
                    onTap: () => open(SleepDetail(day: today)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                coaching,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (sync.message != null)
                Text(
                  sync.message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          );
        },
      ),
    );
  }
}
