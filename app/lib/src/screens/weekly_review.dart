import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../core/week_review.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach_parts.dart' show statusColor, statusGlyph;
import 'longevity.dart' show leverName, leverValue;
import 'nav.dart';
import 'weekly_report.dart';

final weekReviewProvider = FutureProvider<WeekReview>((ref) async {
  ref.watch(dbTickProvider);
  return loadWeekReview(ref.watch(dbProvider));
});

/// Coach's look back at the week: planned vs done, the WHO minimums,
/// load, the focus lever and how the nudges landed.
class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(weekReviewProvider).value;
    final c = context.c, s = context.s;
    if (r == null) return Scaffold(backgroundColor: c.bg);
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
          title: 'Your week',
          subtitle: 'From ${dayShort(r.monday)}',
        ),
        Text(r.headline, style: TempoType.titleL.c(c.text1)),
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
              onTap: () => push(context, const WeeklyReportScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
