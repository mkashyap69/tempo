import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'strain.dart' show ActivityRow, mmssShort;

/// Every workout, newest first: recorded on the band, live in Tempo, or
/// auto-detected from heart rate and steps.
final allWorkoutsProvider = StreamProvider<List<st.Workout>>(
  (ref) => ref.watch(dbProvider).watchAllWorkouts(),
);

class WorkoutsScreen extends ConsumerStatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  ConsumerState<WorkoutsScreen> createState() => _WorkoutsState();
}

class _WorkoutsState extends ConsumerState<WorkoutsScreen> {
  String? _sport; // null = all

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(allWorkoutsProvider).value;
    if (all == null) return Scaffold(backgroundColor: c.bg);
    final sports = <String>{
      for (final w in all)
        if (w.sport != null) w.sport!,
    };
    final shown = _sport == null
        ? all
        : all.where((w) => w.sport == _sport).toList();
    final mon = mondayOf(DateTime.now());
    final weekAgo = dayOf(DateTime.now()).subtract(const Duration(days: 6));

    // Group by week (Monday first), newest week first.
    final weeks = <DateTime, List<st.Workout>>{};
    for (final w in shown) {
      weeks.putIfAbsent(mondayOf(st.fromTs(w.start)), () => []).add(w);
    }

    return TempoPage(
      gap: 16,
      bottom: 48,
      children: [
        const DetailHeader(title: 'Workouts'),
        WeekSportBars(
          from: weekAgo,
          workouts: [
            for (final w in all)
              if (!st.fromTs(w.start).isBefore(weekAgo)) w,
          ],
        ),
        if (sports.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TempoChip(
                  'All',
                  height: 36,
                  selected: _sport == null,
                  onTap: () => setState(() => _sport = null),
                ),
                for (final sp in sportOrder)
                  if (sports.contains(sp.name)) ...[
                    const SizedBox(width: 8),
                    TempoChip(
                      sportLabel(sp),
                      height: 36,
                      selected: _sport == sp.name,
                      onTap: () => setState(() => _sport = sp.name),
                    ),
                  ],
              ],
            ),
          ),
        if (shown.isEmpty)
          const TempoEmpty(
            'No workouts yet. Workouts your band or watch records arrive with the next sync; ones you start with the play button, and walks or rides Tempo spots, show here too.',
          )
        else
          for (final e in weeks.entries)
            Section(
              title: _weekTitle(e.key, mon),
              trailing: Text(
                '${e.value.length} ${e.value.length == 1 ? 'session' : 'sessions'} · ${mmssShort(e.value.fold<int>(0, (a, w) => a + ((w.end - w.start) / 60).round()))}',
                style: TempoType.caption.c(c.text2).tnum,
              ),
              child: CardList(
                children: [
                  for (final (i, w) in e.value.indexed) ...[
                    if (i > 0) const Hair(),
                    ActivityRow(w: w, showDay: true),
                  ],
                ],
              ),
            ),
      ],
    );
  }

  static String _weekTitle(DateTime monday, DateTime thisMonday) {
    final weeks = thisMonday.difference(monday).inDays ~/ 7;
    return switch (weeks) {
      0 => 'This week',
      1 => 'Last week',
      _ => 'Week of ${dm(monday)}',
    };
  }
}

/// Training minutes for the 7 days from [from], stacked by sport colour,
/// with totals and a legend.
class WeekSportBars extends StatelessWidget {
  const WeekSportBars({super.key, required this.from, required this.workouts});
  final DateTime from;
  final List<st.Workout> workouts;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final perDay = List.generate(7, (_) => <String?, double>{});
    var total = 0.0, strain = 0.0;
    for (final w in workouts) {
      final i = dayOf(st.fromTs(w.start)).difference(from).inDays;
      if (i < 0 || i > 6) continue;
      final m = (w.end - w.start) / 60;
      perDay[i][w.sport] = (perDay[i][w.sport] ?? 0) + m;
      total += m;
      strain += w.strain;
    }
    final peak = perDay
        .map((d) => d.values.fold<double>(0, (a, b) => a + b))
        .fold<double>(30, (a, b) => b > a ? b : a);
    const today = 6;
    final used = <String?>{for (final d in perDay) ...d.keys};
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('Last 7 days', style: TempoType.label.c(c.text1)),
              ),
              Text(
                workouts.isEmpty
                    ? 'No sessions yet'
                    : '${workouts.length} ${workouts.length == 1 ? 'session' : 'sessions'} · ${mmssShort(total.round())} · +${n1(strain)} strain',
                style: TempoType.caption.c(c.text2).tnum,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Semantics(
                      label:
                          '${dayShort(from.add(Duration(days: i)))}: ${perDay[i].values.fold<double>(0, (a, b) => a + b).round()} minutes',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final e in perDay[i].entries)
                            Container(
                              width: 18,
                              height: (e.value / peak * 60).clamp(3, 60),
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: sportColor(e.key, dark: c.dark),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          if (perDay[i].isEmpty)
                            Container(
                              width: 18,
                              height: 3,
                              decoration: BoxDecoration(
                                color: c.trackOff,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            'MTWTFSS'[from.add(Duration(days: i)).weekday - 1],
                            style: TempoType.caption.c(
                              i == today ? c.text1 : c.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (used.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final sp in used)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: sportColor(sp, dark: c.dark),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sportLabelFor(sp),
                        style: TempoType.caption.c(c.text2),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
