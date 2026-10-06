import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'activity_detail.dart';
import 'coach.dart';
import 'goal.dart';
import 'nav.dart';
import 'onboarding.dart' show AvailabilityEditor;
import 'workout_detail.dart';

final _weekWorkoutsProvider = FutureProvider<List<st.Workout>>((ref) async {
  ref.watch(dbTickProvider);
  final mon = mondayOf(DateTime.now());
  return ref
      .watch(dbProvider)
      .workoutsBetween(mon, mon.add(const Duration(days: 7)));
});

class WeeklyPlanScreen extends ConsumerWidget {
  const WeeklyPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(weekProvider).value;
    final prof = ref.watch(profileProvider).value;
    final ws = ref.watch(_weekWorkoutsProvider).value ?? const [];
    if (w == null || prof == null) {
      return Scaffold(backgroundColor: context.c.bg);
    }
    final c = context.c, s = context.s;
    final today = DateTime.now().weekday - 1;
    final sessions = [for (var i = 0; i < 7; i++) w.session(i)];
    final rest = sessions.where((x) => x.isRest).length;
    final mins = sessions.fold(0, (a, x) => a + x.minutes);
    final changes = [
      for (var i = 0; i < 7; i++)
        if (w.rows[i].original != null) i,
    ];
    final adaptedAt = w.rows
        .map((r) => r.adaptedAt)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

    return TempoPage(
      children: [
        DetailHeader(
          title: 'Weekly plan',
          trailing: TempoIconButton(
            TempoIcons.edit,
            label: 'Edit availability',
            stroke: 1.75,
            onTap: () async {
              final next = await showTempoSheet<Profile>(
                context,
                builder: (ctx) =>
                    AvailabilityEditor(profile: prof, sheet: true),
              );
              if (next == null) return;
              final db = ref.read(dbProvider);
              await saveAppProfile(db, next);
              await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
              if (context.mounted) {
                showTempoToast(
                  context,
                  'Plan rebuilt for ${next.days.length} days · up to ${next.maxMinutes} min',
                );
              }
            },
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dm(w.monday)} – ${dm(w.date(6))}',
              style: TempoType.pageTitle.c(c.text1),
            ),
            const SizedBox(height: 4),
            Text(
              '${7 - rest} sessions + $rest rest ${rest == 1 ? 'day' : 'days'} · ${mins ~/ 60} h ${mins % 60} m planned',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ),
        const GoalCard(),
        if (changes.isNotEmpty)
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Overline('What changed')),
                    if (adaptedAt != null)
                      Text(
                        'Adapted ${clockOf(st.fromTs(adaptedAt))}',
                        style: TempoType.caption.c(c.text3),
                      ),
                  ],
                ),
                for (final i in changes) ...[
                  const SizedBox(height: 12),
                  Hair(),
                  const SizedBox(height: 12),
                  Text(
                    '${dayShort(w.date(i))}${i == today ? ' · today' : ''}',
                    style: TempoType.caption.c(c.text3),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        w.original(i)?.title ?? '—',
                        style: TempoType.body.copyWith(
                          color: c.text3,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: c.text3,
                        ),
                      ),
                      TempoIcon(
                        TempoIcons.arrow,
                        size: 14,
                        color: c.text2,
                        stroke: 2,
                      ),
                      Text(
                        '${w.session(i).title}${w.session(i).minutes > 0 ? ' ${w.session(i).minutes}′' : ''}',
                        style: TempoType.body.copyWith(
                          color: c.text1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final r = w.rows[i].reason ?? '';
                      final g = r.isEmpty ? '' : r.substring(0, 1);
                      final col = switch (g) {
                        '▲' => s.recHigh,
                        '■' => s.recMid,
                        '▼' => s.recLow,
                        _ => c.text2,
                      };
                      return Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$g ',
                              style: TextStyle(color: col),
                            ),
                            TextSpan(text: r.length > 2 ? r.substring(2) : r),
                          ],
                        ),
                        style: TempoType.bodyS.c(c.text2),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Overline('Planned vs actual strain')),
                  Legend(c.text3, 'plan', outline: true, height: 8),
                  const SizedBox(width: 8),
                  Legend(s.strain[1], 'actual', height: 8),
                ],
              ),
              const SizedBox(height: 12),
              WeekBars(week: w, today: today, height: 120, values: true),
            ],
          ),
        ),
        CardList(
          children: [
            for (var i = 0; i < 7; i++)
              Builder(
                builder: (context) {
                  final x = w.session(i);
                  final a = w.actual(i);
                  final live = i == today;
                  final future = i > today;
                  final inR =
                      a != null && a >= x.strainLo && a <= x.strainHi + .5;
                  final over = a != null && a > x.strainHi + .5;
                  final range = '${x.strainLo.round()}–${x.strainHi.round()}';
                  final verdict = future
                      ? 'Target $range'
                      : live
                      ? 'Live · target $range'
                      : a == null
                      ? 'No data'
                      : over
                      ? 'Over plan $range'
                      : inR
                      ? '✓ in plan $range'
                      : 'Under plan $range';
                  final dayWs = ws
                      .where(
                        (e) =>
                            DateUtils.isSameDay(st.fromTs(e.start), w.date(i)),
                      )
                      .toList();
                  return Pressable(
                    label: '${dayShort(w.date(i))} ${x.title}',
                    onTap: live
                        ? () => push(context, const WorkoutDetailScreen())
                        : dayWs.isEmpty
                        ? null
                        : () => push(
                            context,
                            ActivityDetailScreen(id: dayWs.first.id),
                          ),
                    child: Container(
                      color: live ? c.surface2 : null,
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dayShort(w.date(i)).substring(0, 3),
                                  style: TempoType.label.c(c.text1),
                                ),
                                Text(
                                  '${w.date(i).day}',
                                  style: TempoType.caption.c(c.text3).tnum,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.title,
                                  style: TempoType.label.c(c.text1),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  x.isRest
                                      ? x.note
                                      : '${x.minutes}′ · ${x.note.isNotEmpty ? x.note : x.zones}${w.rows[i].original != null ? ' · swapped' : ''}${live ? ' · today' : ''}',
                                  style: TempoType.caption.c(c.text2).tnum,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                a == null ? '–' : n1(a),
                                style: TempoType.label.c(c.text1).tnum,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                verdict,
                                style: TempoType.caption
                                    .c(live ? s.strain[1] : c.text3)
                                    .tnum,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        Text(
          'Each morning after sync, Tempo re-checks recovery and load and adjusts the plan. It always says what changed and why. It never plans beyond the days and minutes you said you have (${prof.days.length} days · up to ${prof.maxMinutes} min).',
          style: TempoType.bodyS.c(c.text3),
        ),
      ],
    );
  }
}
