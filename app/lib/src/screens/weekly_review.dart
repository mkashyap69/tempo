import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart' show mondayOf;
import '../core/format.dart';
import '../core/profile.dart' show Keys;
import '../core/week_review.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach.dart' show weekProvider;
import 'coach_parts.dart' show statusColor, statusGlyph;
import 'coach_settings.dart';
import 'highlight.dart' show DiscoveriesSection;
import 'longevity.dart';
import 'nav.dart';
import 'weekly_report.dart';

/// The review of the week starting [monday] (a date key). A past week is
/// read as of its Sunday night, so every day counts as done or missed.
final weekReviewProvider = FutureProvider.family<WeekReview, String>((
  ref,
  monday,
) async {
  ref.watch(dbTickProvider);
  final mon = DateTime.parse(monday);
  final end = mon.add(const Duration(days: 6, hours: 23, minutes: 59));
  final now = DateTime.now();
  return loadWeekReview(
    ref.watch(dbProvider),
    at: now.isAfter(end) ? end : now,
  );
});

/// Monday reviews last week; any other day, the week so far.
DateTime reviewMonday(DateTime now) {
  final mon = mondayOf(now);
  return now.weekday == DateTime.monday
      ? mon.subtract(const Duration(days: 7))
      : mon;
}

/// Week in review: the week in three lines, planned vs done, the health
/// minimums, Tempo Age, what the journal found, and (on Mondays) the week
/// ahead to confirm. One ritual for the week.
class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key, this.monday});

  /// The week to review; null picks it from today ([reviewMonday]).
  final DateTime? monday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mon = monday ?? reviewMonday(DateTime.now());
    final key = st.dateKey(mon);
    final r = ref.watch(weekReviewProvider(key)).value;
    final report = ref.watch(weekReportProvider(key)).value;
    final c = context.c, s = context.s;
    if (r == null) return Scaffold(backgroundColor: c.bg);
    final past = mondayOf(DateTime.now()).isAfter(mon);
    String status(ReviewDay d) => switch (d.status) {
      null => 'Ahead',
      sc.DayStatus.rest => 'Rest',
      sc.DayStatus.done => 'Done',
      sc.DayStatus.doneEasier => 'Done, easier',
      sc.DayStatus.partial => 'Partly',
      sc.DayStatus.skipped => 'Skipped',
      sc.DayStatus.missedDay || sc.DayStatus.missedSlot => 'Missed',
      sc.DayStatus.pending || sc.DayStatus.moved => 'Today',
    };
    Widget bar(String label, double value, double target, String text) {
      final f = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: TempoType.label.c(c.text1))),
              Text(text, style: TempoType.label.c(c.text2).tnum),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(TempoRadii.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: c.surface3),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(color: f >= 1 ? s.recHigh : c.text1),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final f = r.focus, p = r.progress;
    return TempoPage(
      gap: 18,
      children: [
        DetailHeader(
          title: 'Week in review',
          subtitle: past
              ? 'Last week, from ${dayShort(r.monday)}'
              : 'This week so far, from ${dayShort(r.monday)}',
        ),
        Text(r.headline, style: TempoType.titleL.c(c.text1)),
        if (report != null)
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Your week in three lines'),
                const SizedBox(height: 8),
                Text(report.summary(), style: TempoType.body.c(c.text1)),
              ],
            ),
          ),
        CardList(
          children: [
            for (final d in r.days)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        dayShort(d.date).substring(0, 3),
                        style: TempoType.label.c(c.text2),
                      ),
                    ),
                    Text(
                      statusGlyph(d.status),
                      style: TempoType.label.c(
                        d.status == null
                            ? c.text3
                            : statusColor(context, d.status!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        d.session.isRest
                            ? 'Rest'
                            : '${d.session.title} ${d.session.minutes}′',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TempoType.label.c(c.text1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${status(d)}${d.strain == null || d.status == null ? '' : ' · ${d.strain!.toStringAsFixed(1)}'}',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                  ],
                ),
              ),
          ],
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Overline('Minimums for health (WHO)'),
              const SizedBox(height: 14),
              bar(
                'Moderate or harder',
                r.moderateMinutes.toDouble(),
                150,
                '${r.moderateMinutes} / 150 min',
              ),
              const SizedBox(height: 16),
              bar(
                'Strength days',
                r.strengthDays.toDouble(),
                2,
                '${r.strengthDays} / 2',
              ),
            ],
          ),
        ),
        if (f != null && p != null)
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Overline(
                  'Focus · week ${f.weekOn(DateTime.now())} of ${f.weeks}',
                ),
                const SizedBox(height: 14),
                bar(
                  leverName(f.lever),
                  p.$1,
                  p.$2,
                  '${leverValue(f.lever, p.$1)} / ${leverValue(f.lever, p.$2)}',
                ),
              ],
            ),
          ),
        const _AgeThisWeek(),
        const DiscoveriesSection(),
        if (past)
          _NextWeek(onAdjust: () => push(context, const CoachSettingsScreen())),
        CardList(
          children: [
            ListRow(
              'Cardio load',
              value: '${loadGlyph(r.load.status)} ${loadWord(r.load.status)}',
              chevron: false,
            ),
            ListRow(
              'Coach notifications',
              value: r.nudgesPosted == 0
                  ? 'None yet'
                  : '${r.nudgesAnswered} of ${r.nudgesPosted} answered',
              chevron: false,
            ),
            ListRow(
              'Share card',
              sub: 'Recovery, strain and sleep for the week',
              onTap: () => push(context, WeeklyReportScreen(monday: mon)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tempo Age this week: the change and the lever that moved it most.
class _AgeThisWeek extends ConsumerWidget {
  const _AgeThisWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(longevityProvider).value;
    final l = d?.latest, w = d?.weekAgo;
    if (d == null || l == null || w == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final delta = l.tempoAge - w.tempoAge;
    final top = d.changes.isEmpty ? null : d.changes.first;
    return TempoCard(
      label: 'Tempo Age this week',
      onTap: () => push(context, const LongevityScreen(standalone: true)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Tempo Age this week'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l.tempoAge.toStringAsFixed(1),
                style: TempoType.scoreS.c(c.text1),
              ),
              const SizedBox(width: 10),
              Text(
                '${delta <= 0 ? '−' : '+'}${delta.abs().toStringAsFixed(1)} years',
                style: TempoType.bodyS
                    .c(
                      delta <= -.05
                          ? s.recHigh
                          : delta >= .05
                          ? s.recLow
                          : c.text2,
                    )
                    .tnum,
              ),
            ],
          ),
          if (top != null) ...[
            const SizedBox(height: 4),
            Text(
              'Moved most by ${leverName(top.$1).toLowerCase()}.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ],
      ),
    );
  }
}

/// Monday: this week's plan, to confirm or adjust.
class _NextWeek extends ConsumerWidget {
  const _NextWeek({required this.onAdjust});
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(weekProvider).value;
    final done = ref.watch(settingProvider(Keys.weekPlanOk)).value;
    if (w == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final key = st.dateKey(w.monday);
    return TempoCard(
      label: 'This week’s plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('This week’s plan'),
          const SizedBox(height: 10),
          for (var i = 0; i < 7; i++)
            if (!w.session(i).isRest)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        dayShort(w.date(i)).substring(0, 3),
                        style: TempoType.bodyS.c(c.text3),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${w.session(i).title} · ${w.session(i).minutes} min',
                        style: TempoType.bodyS.c(c.text1),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          if (done == key)
            Text(
              'Week set. Each morning adapts it to the night before.',
              style: TempoType.bodyS.c(s.recHigh),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TempoButton(
                    'Looks good',
                    expand: true,
                    onTap: () =>
                        ref.read(dbProvider).putSetting(Keys.weekPlanOk, key),
                  ),
                ),
                const SizedBox(width: 10),
                TempoButton('Adjust', kind: ButtonKind.ghost, onTap: onAdjust),
              ],
            ),
        ],
      ),
    );
  }
}
