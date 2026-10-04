import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/stages.dart';
import 'format.dart';
import 'providers.dart';
import 'theme.dart';
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

class SleepDetail extends ConsumerWidget {
  const SleepDetail({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_nightProvider(day));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sleep Performance',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final (s, mins, prev) = d;
          if (s == null || s.sleepStart == null) {
            return const Center(
              child: Text(
                'No sleep found for last night. Sync your band.',
                style: TextStyle(color: muted),
              ),
            );
          }
          final session = sc.SleepSession([
            for (final m in mins)
              sc.Minute(st.fromTs(m.ts), stage: stageForKind(m.kind)),
          ]);
          final debt = sc.sleepDebtHours([
            for (final p in prev)
              if (p.needHours != null && p.sleptHours != null)
                sc.NightRecord(
                  needHours: p.needHours!,
                  sleptHours: p.sleptHours!,
                ),
          ]);
          final asleep = session.asleep.inMinutes;

          // Stage durations in minutes
          final deepM = session.stage(sc.Stage.deep).inMinutes;
          final lightM = session.stage(sc.Stage.light).inMinutes;
          final remM = session.stage(sc.Stage.rem).inMinutes;
          final wakeM = session.stage(sc.Stage.wake).inMinutes;
          final totalM = (asleep + wakeM).clamp(1, 1440);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // 1. Hero Sleep Score Ring
              SoftCard(
                blob: true,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    const Text(
                      'CIRCADIAN SLEEP NEED',
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
                            value: (s.sleepPerf ?? 0) / 100,
                            strokeWidth: 9,
                            backgroundColor: const Color(0xFFF0F0F5),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF9D4EDD),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.sleepPerf == null
                                    ? '–'
                                    : '${s.sleepPerf!.round()}%',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: ink,
                                ),
                              ),
                              const Text(
                                'SCORE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${hm(s.sleptHours)} asleep',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${hm(s.needHours)} computed need · ${(session.efficiency * 100).round()}% efficiency',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Exact Sleep Need Breakdown Equation
              SoftCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Exact Sleep Need Formula',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Need = 7.5h baseline + 0.5 × 7d debt + 0.03h × yesterday strain',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 16),
                    _EquationRow(
                      label: 'Baseline physiological need',
                      value: '7h 30m',
                    ),
                    _EquationRow(
                      label: '7-day debt (50% carry-over)',
                      value: '+ ${hm(debt)}',
                      accent: true,
                    ),
                    _EquationRow(
                      label: 'Yesterday strain load',
                      value: '+ ${hm((s.needHours ?? 7.5) - 7.5 - debt * 0.5)}',
                      accent: true,
                    ),
                    const Divider(height: 20),
                    _EquationRow(
                      label: 'Total Target Need',
                      value: hm(s.needHours),
                      bold: true,
                    ),
                    _EquationRow(
                      label: 'Actual Time Asleep',
                      value: hm(s.sleptHours),
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Hypnogram Stages Segment Bar
              SoftCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sleep Stages Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 20,
                        child: Row(
                          children: [
                            if (wakeM > 0)
                              Expanded(
                                flex: wakeM,
                                child: Container(
                                  color: const Color(0xFFC8C8D0),
                                ),
                              ),
                            if (remM > 0)
                              Expanded(
                                flex: remM,
                                child: Container(
                                  color: const Color(0xFFE8EEF8),
                                ),
                              ),
                            if (lightM > 0)
                              Expanded(
                                flex: lightM,
                                child: Container(
                                  color: const Color(0xFFFFC7A8),
                                ),
                              ),
                            if (deepM > 0)
                              Expanded(
                                flex: deepM,
                                child: Container(
                                  color: const Color(0xFFFF5A1F),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StageItem(
                      color: const Color(0xFFFF5A1F),
                      name: 'Deep Sleep',
                      dur: hm(deepM / 60),
                      pct: '${(100 * deepM / totalM).round()}%',
                    ),
                    _StageItem(
                      color: const Color(0xFFFFC7A8),
                      name: 'Light Sleep',
                      dur: hm(lightM / 60),
                      pct: '${(100 * lightM / totalM).round()}%',
                    ),
                    _StageItem(
                      color: const Color(0xFFE8EEF8),
                      name: 'REM Sleep',
                      dur: hm(remM / 60),
                      pct: '${(100 * remM / totalM).round()}%',
                    ),
                    _StageItem(
                      color: const Color(0xFFC8C8D0),
                      name: 'Awake Time',
                      dur: hm(wakeM / 60),
                      pct: '${(100 * wakeM / totalM).round()}%',
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

class _EquationRow extends StatelessWidget {
  const _EquationRow({
    required this.label,
    required this.value,
    this.accent = false,
    this.bold = false,
  });
  final String label, value;
  final bool accent, bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? ink : muted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent
                  ? const Color(0xFFFF5A1F)
                  : bold
                  ? ink
                  : const Color(0xFF44444F),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageItem extends StatelessWidget {
  const _StageItem({
    required this.color,
    required this.name,
    required this.dur,
    required this.pct,
  });
  final Color color;
  final String name, dur, pct;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            dur,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(pct, style: const TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );
  }
}
