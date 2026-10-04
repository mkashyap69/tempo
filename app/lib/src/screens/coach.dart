import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/today.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'cardio_load.dart';
import 'learn.dart';
import 'nav.dart';
import 'shared.dart';
import 'today.dart' show WorkoutCard;
import 'weekly_plan.dart';
import 'workout_detail.dart';

/// The current week: plan rows and actual strain per day.
class WeekView {
  WeekView(this.monday, this.rows, this.scores);
  final DateTime monday;
  final List<st.PlanDay> rows;
  final Map<String, st.DailyScore> scores;

  sc.Session session(int i) =>
      sc.Session.fromJson(jsonDecode(rows[i].session) as Map<String, dynamic>);
  sc.Session? original(int i) => rows[i].original == null
      ? null
      : sc.Session.fromJson(
          jsonDecode(rows[i].original!) as Map<String, dynamic>,
        );
  double? actual(int i) => scores[rows[i].date]?.strain;
  DateTime date(int i) => monday.add(Duration(days: i));
}

final weekProvider = FutureProvider<WeekView>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final today = dayOf(DateTime.now());
  final rows = await CoachService(db).ensureWeek(today);
  final mon = mondayOf(today);
  final scores = await db.scoresBetween(mon, mon.add(const Duration(days: 6)));
  return WeekView(mon, rows, {for (final s in scores) s.date: s});
});

final loadHistoryProvider =
    FutureProvider<List<({double acute, double chronic})>>((ref) async {
      ref.watch(dbTickProvider);
      return sc.loadHistory(
        await dailyTrimp(
          ref.watch(dbProvider),
          dayOf(DateTime.now()),
          days: 28 * 5,
        ),
        weeks: 12,
      );
    });

class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key, this.standalone = false});

  /// Pushed from a detail screen (shows a back button, no tab padding).
  final bool standalone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    final w = ref.watch(weekProvider).value;
    if (t == null || w == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final general = t.planRow?.general ?? t.calibrating;
    final (lead, leadColor, rest) = _readiness(context, t);
    final adds = planAdds(t);
    final change = w.rows.where((r) => r.reason != null).toList();
    final hist = ref.watch(loadHistoryProvider).value ?? const [];
    final todayIdx = t.day.weekday - 1;

    return TempoPage(
      bottom: standalone ? 48 : 100,
      children: [
        if (standalone)
          const DetailHeader(title: 'Coach')
        else
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text('Coach', style: TempoType.pageTitle.c(c.text1)),
                ),
                TempoBadge(general ? 'General plan' : 'Personal plan'),
              ],
            ),
          ),
        if (t.stale)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TempoRadii.md),
            ),
            child: Row(
              children: [
                TempoIcon(TempoIcons.clock, size: 18, color: c.text1),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Plan is from ${t.lastSync == null ? 'before your last sync' : clockOf(t.lastSync!)}. Sync to adapt it to last night.',
                    style: TempoType.bodyS.c(c.text2),
                  ),
                ),
                const SizedBox(width: 12),
                TempoButton(
                  'Sync',
                  small: true,
                  kind: ButtonKind.secondary,
                  onTap: () => ref.read(syncProvider.notifier).syncNow(),
                ),
              ],
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Today’s readiness'),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: lead,
                    style: TextStyle(color: leadColor),
                  ),
                  TextSpan(text: rest),
                ],
              ),
              style: TempoType.titleL.c(c.text1),
            ),
          ],
        ),
        if (t.restDay || (t.plan?.isRest ?? false))
          TempoCard(
            color: t.restDay ? s.tintRecLow : c.surface1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Overline(
                  t.restDay ? '▼ Rest day' : 'Rest day',
                  color: t.restDay ? s.recLow : null,
                ),
                const SizedBox(height: 10),
                Text(
                  'Walk, stretch, sleep early',
                  style: TempoType.titleM.c(c.text1),
                ),
                const SizedBox(height: 10),
                Text(
                  'Strain cap ${t.target.cap ? t.target.hi.round() : 7} · bedtime ${clock12(t.bedtimeMinute)}.${_carriedNote(w, todayIdx)}',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          )
        else if (t.plan != null)
          WorkoutCard(
            session: t.plan!,
            general: general,
            adds: adds,
            overline: 'Suggested workout',
            why: _why(t, general),
            onTap: () => push(context, const WorkoutDetailScreen()),
          ),
        TempoCard(
          onTap: () => push(context, const WeeklyPlanScreen()),
          label: 'This week',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Overline('This week')),
                  Legend(c.text3, 'Planned', outline: true, height: 8),
                  const SizedBox(width: 8),
                  Legend(s.strain[1], 'Actual', height: 8),
                ],
              ),
              const SizedBox(height: 14),
              WeekBars(week: w, today: todayIdx, height: 64, labels: true),
              const SizedBox(height: 12),
              Hair(),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: TempoIcon(
                      TempoIcons.swap,
                      size: 16,
                      color: c.text2,
                      stroke: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      change.isEmpty
                          ? general
                                ? 'General plan from your goals and ${t.profile.days.length} days a week. It personalises after night 14.'
                                : 'No changes this week — the plan still fits your recovery.'
                          : _changeLine(w, change.last),
                      style: TempoType.bodyS.c(c.text2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          onTap: () => push(context, const CardioLoadScreen()),
          label: 'Cardio load',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Overline('Cardio load')),
                  Text('8 weeks', style: TempoType.caption.c(c.text3)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${loadGlyph(t.load.status)} ${loadWord(t.load.status)}',
                          style: TempoType.titleM.c(
                            loadColor(context, t.load.status),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.load.status == sc.LoadStatus.learning
                              ? 'Status appears after 7 days of data.'
                              : '${loadSub(t.load)}.',
                          style: TempoType.bodyS.c(c.text2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 110,
                    height: 44,
                    child: MiniLoad(
                      history: hist.length > 8
                          ? hist.sublist(hist.length - 8)
                          : hist,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(TempoRadii.sm),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'This week · ',
                        style: TextStyle(color: c.text3),
                      ),
                      TextSpan(text: loadAdvice(t.load.status).first),
                    ],
                  ),
                  style: TempoType.bodyS.c(c.text1),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Overline('Learn')),
                Pressable(
                  onTap: () => push(context, const LearnScreen()),
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text('All 6', style: TempoType.label.c(c.text2)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: [
                  for (final (i, l) in learnItems(
                    context,
                    t,
                  ).take(3).indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Pressable(
                      label: l.title,
                      onTap: () => push(
                        context,
                        LearnCardsScreen(
                          initial: i == 2
                              ? 2
                              : i == 1
                              ? 3
                              : 0,
                        ),
                      ),
                      child: Container(
                        width: 150,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.surface1,
                          borderRadius: BorderRadius.circular(TempoRadii.lg),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TempoIcon(l.icon, size: 28, color: l.color),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.title,
                                  style: TempoType.label.c(c.text1),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l.short,
                                  style: TempoType.caption.c(c.text3),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _carriedNote(WeekView w, int today) {
    for (var i = today + 1; i < 7; i++) {
      final r = w.rows[i];
      if (r.reason != null && w.session(i).isHard) {
        return ' ${w.session(i).title} has moved to ${dayShort(w.date(i)).substring(0, 3)}.';
      }
    }
    return '';
  }

  static String _changeLine(WeekView w, st.PlanDay r) {
    final i = w.rows.indexOf(r);
    final from = w.original(i), to = w.session(i);
    final day = dayShort(w.date(i)).substring(0, 3);
    final why = r.reason!.replaceFirst(RegExp(r'^[▲■▼·] '), '');
    return '$day: ${from?.title ?? 'plan'} → ${to.title}. $why';
  }

  static String _why(TodayData t, bool general) {
    if (general) return 'General · built from your goal';
    final parts = [
      if (t.recovery != null) 'Recovery ${t.recovery!.round()}%',
      if (t.load.status != sc.LoadStatus.learning)
        'load ${loadWord(t.load.status).toLowerCase()}',
    ];
    return parts.join(' · ');
  }

  static (String, Color, String) _readiness(BuildContext context, TodayData t) {
    final c = context.c, s = context.s;
    if (t.stale) {
      return (
        'Yesterday’s plan.',
        c.text2,
        ' Sync first — today’s session depends on last night’s recovery.',
      );
    }
    if (t.firstDay) {
      return (
        'First day.',
        c.text1,
        ' Wear the band tonight; the plan stays general and moderate until Tempo knows you.',
      );
    }
    if (t.calibrating) {
      return (
        'Night ${t.nights} of 14.',
        c.text1,
        ' Until Tempo knows your baseline, sessions stay moderate and general.',
      );
    }
    final r = t.recovery;
    if (r == null) {
      return (
        'Waiting for last night.',
        c.text1,
        ' Sync near your band to adapt today’s plan.',
      );
    }
    if (t.restDay) {
      return (
        'Rest today.',
        s.recLow,
        ' Recovery ${r.round()}%${t.load.status == sc.LoadStatus.overreaching ? ' and your load is overreaching' : ''} — the most productive thing today is nothing hard.',
      );
    }
    if (r >= 67) {
      final building = t.load.status == sc.LoadStatus.building;
      return (
        building ? 'Primed and building.' : 'Primed.',
        s.recHigh,
        ' Recovery ${r.round()}%${building ? ' with room in your load' : ''} — make today the hard one, keep tomorrow easy.',
      );
    }
    return (
      'Steady.',
      s.recMid,
      ' Recovery ${r.round()}% — keep it aerobic today; save intensity for a greener morning.',
    );
  }
}

/// Planned (outline) vs actual (filled) strain per day.
class WeekBars extends StatelessWidget {
  const WeekBars({
    super.key,
    required this.week,
    required this.today,
    required this.height,
    this.labels = false,
    this.values = false,
  });
  final WeekView week;
  final int today;
  final double height;
  final bool labels, values;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final k = height / 21;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Builder(
              builder: (context) {
                final ses = week.session(i);
                final a = week.actual(i);
                final lo = ses.strainLo, hi = ses.strainHi;
                final inR = a != null && a >= lo && a <= hi + .5;
                final col = i == today
                    ? s.strain[0]
                    : a == null
                    ? c.trackOff
                    : a > hi + .5
                    ? s.strain[3]
                    : inR
                    ? s.strain[1]
                    : s.strain[0];
                return Column(
                  children: [
                    if (values) ...[
                      Text(
                        a == null ? '–' : n1(a),
                        style: TempoType.caption.c(c.text2).tnum,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: i == today ? c.surface2 : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [
                            Positioned(
                              left: box.maxWidth * (values ? .2 : .25),
                              right: box.maxWidth * (values ? .2 : .25),
                              bottom: lo * k,
                              height: ((hi - lo) * k).clamp(0, height),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    values ? 4 : 3,
                                  ),
                                  border: Border.all(
                                    color: c.text3,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            if (a != null)
                              Positioned(
                                left: box.maxWidth * (values ? .36 : .38),
                                right: box.maxWidth * (values ? .36 : .38),
                                bottom: 0,
                                height: (a * k).clamp(0, height),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: col,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'MTWTFSS'[i],
                      style: TempoType.label.c(i == today ? c.text1 : c.text2),
                    ),
                    if (labels) ...[
                      const SizedBox(height: 6),
                      Text(
                        ses.isRest ? 'Rest' : shortTitle(ses),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: TempoType.family,
                          fontSize: 10,
                          height: 1.2,
                          color: c.text3,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Small acute vs chronic sparkline for the Coach card.
class MiniLoad extends StatelessWidget {
  const MiniLoad({super.key, required this.history});
  final List<({double acute, double chronic})> history;
  @override
  Widget build(BuildContext context) => SvgChart(
    width: 110,
    height: 44,
    semantics: 'Cardio load trend',
    draw: (ink, box) {
      if (history.length < 2) {
        ink.line(
          const Offset(0, 30),
          const Offset(40, 28),
          ink.c.text3,
          w: 1.5,
          dash: [3, 3],
        );
        return;
      }
      final all = [
        for (final h in history) ...[h.acute, h.chronic * 1.3, h.chronic * .8],
      ];
      final hi = all.reduce((a, b) => a > b ? a : b),
          lo = all.reduce((a, b) => a < b ? a : b);
      double y(double v) => 40 - (v - lo) / (hi - lo == 0 ? 1 : hi - lo) * 36;
      double x(int i) => i / (history.length - 1) * 110;
      ink.area(
        [
          for (final (i, h) in history.indexed)
            Offset(x(i), y(h.chronic * 1.3)),
        ],
        [for (final (i, h) in history.indexed) Offset(x(i), y(h.chronic * .8))],
        ink.s.loadBuilding,
        .12,
      );
      ink.polyline(
        [for (final (i, h) in history.indexed) Offset(x(i), y(h.chronic))],
        ink.c.text3,
        w: 1.5,
        dash: [3, 3],
      );
      ink.polyline(
        [for (final (i, h) in history.indexed) Offset(x(i), y(h.acute))],
        ink.c.text1,
        w: 2,
      );
    },
  );
}

/// One word for the week strip: "Intervals", "Long", "Strength".
String shortTitle(sc.Session s) => switch (s.key) {
  'threshold_run' || 'vo2_run' || 'hiit' => 'Intervals',
  'tempo_ride' => 'Tempo',
  'long_run' || 'long_ride' => 'Long Z2',
  'easy_run' || 'aerobic_run' || 'steady_run' => 'Easy run',
  'easy_ride' => 'Easy ride',
  'easy_walk' => 'Walk',
  'strength_full' || 'strength_lower' => 'Strength',
  'mobility' || 'yoga' => 'Yoga',
  'rest' => 'Rest',
  _ => s.title.split(' ').first,
};
