import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/stages.dart';
import 'format.dart';
import 'providers.dart';
import 'widgets.dart';

final _nightProvider =
    FutureProvider.family<
      (st.DailyScore?, List<st.MinuteSample>, List<st.DailyScore>),
      DateTime
    >((ref, day) async {
      final db = ref.watch(dbProvider);
      final s = await db.scoreFor(day);
      final mins = s?.sleepStart == null
          ? <st.MinuteSample>[]
          : await db.minutesBetween(
              st.fromTs(s!.sleepStart!),
              st.fromTs(s.sleepEnd!),
            );
      return (s, mins, await db.scoresBefore(day, limit: 7));
    });

double _level(sc.Stage s) => switch (s) {
  sc.Stage.wake || sc.Stage.unknown => 3,
  sc.Stage.rem => 2,
  sc.Stage.light => 1,
  sc.Stage.deep => 0,
};

class SleepDetail extends ConsumerWidget {
  const SleepDetail({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_nightProvider(day));
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final (s, mins, prev) = d;
          if (s == null || s.sleepStart == null) {
            return const Center(child: Text('No sleep found for last night.'));
          }
          final session = sc.SleepSession([
            for (final m in mins)
              sc.Minute(st.fromTs(m.ts), stage: stageForKind(m.kind)),
          ]);
          final t0 = mins.first.ts;
          final debt = sc.sleepDebtHours([
            for (final p in prev)
              if (p.needHours != null && p.sleptHours != null)
                sc.NightRecord(
                  needHours: p.needHours!,
                  sleptHours: p.sleptHours!,
                ),
          ]);
          final asleep = session.asleep.inMinutes;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Section('Performance ${n0(s.sleepPerf)}%', [
                Kv('Slept', hm(s.sleptHours)),
                Kv('Needed', hm(s.needHours)),
                Kv('Debt carried in (7 nights, cap 2h)', hm(debt)),
                Kv(
                  'In bed',
                  '${clock(st.fromTs(s.sleepStart!))} – ${clock(st.fromTs(s.sleepEnd!))}',
                ),
                Kv('Efficiency', '${(session.efficiency * 100).round()}%'),
                Kv(
                  'Deep share',
                  asleep == 0
                      ? '–'
                      : '${(100 * session.stage(sc.Stage.deep).inMinutes / asleep).round()}%',
                ),
              ]),
              Section('Hypnogram', [
                SimpleLine(
                  step: true,
                  minY: 0,
                  maxY: 3,
                  color: sleepColour,
                  points: [
                    for (final m in session.minutes)
                      FlSpot(
                        (m.ts.millisecondsSinceEpoch ~/ 1000 - t0) / 3600,
                        _level(m.stage),
                      ),
                  ],
                  xLabel: (h) => clock(st.fromTs(t0 + (h * 3600).round())),
                ),
                const Text(
                  '0 deep · 1 light · 2 REM · 3 awake',
                  style: TextStyle(fontSize: 12),
                ),
              ]),
              Section('Stages', [
                for (final stage in [
                  sc.Stage.deep,
                  sc.Stage.light,
                  sc.Stage.rem,
                  sc.Stage.wake,
                ])
                  Kv(stage.name, hm(session.stage(stage).inMinutes / 60)),
              ]),
            ],
          );
        },
      ),
    );
  }
}
