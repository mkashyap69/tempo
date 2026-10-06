import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../design/components.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'insight_detail.dart';
import 'nav.dart';

class JournalTag {
  const JournalTag(this.key, this.name, this.sub);
  final String key, name, sub;
}

const journalTags = [
  JournalTag('alcohol', 'Alcohol', 'Any amount'),
  JournalTag('late_meal', 'Late meal', 'Within 2 h of bed'),
  JournalTag('caffeine_late', 'Caffeine late', 'After 2 pm'),
  JournalTag('stressful_day', 'Stressful day', 'Your call'),
  JournalTag('travel', 'Travel', 'New place or time zone'),
];

/// Pairs each tagged day with the next morning's recovery.
class InsightData {
  InsightData(this.tag, this.insight, this.nights);
  final JournalTag tag;
  final sc.TagInsight insight;

  /// (date, tagged, next-morning score)
  final List<(DateTime, bool, st.DailyScore)> nights;
}

class JournalState {
  JournalState(this.count, this.yesterday, this.insights);
  final int count;
  final Map<String, bool> yesterday;
  final List<InsightData> insights;
}

final journalProvider = FutureProvider<JournalState>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final all = await db.watchJournal().first;
  final dates = {for (final j in all) j.date};
  final y = dayOf(DateTime.now()).subtract(const Duration(days: 1));
  final yesterday = {
    for (final j in all)
      if (j.date == st.dateKey(y)) j.tag: j.value,
  };
  final insights = <InsightData>[];
  for (final t in journalTags) {
    final nights = <(DateTime, bool, st.DailyScore)>[];
    for (final j in all.where((j) => j.tag == t.key)) {
      final d = DateTime.parse(j.date);
      final next = await db.scoreFor(d.add(const Duration(days: 1)));
      if (next?.recovery == null || next!.calibrating) continue;
      nights.add((d, j.value, next));
    }
    insights.add(
      InsightData(
        t,
        sc.tagInsight([
          for (final n in nights) sc.TaggedNight(n.$2, n.$3.recovery!),
        ]),
        nights,
      ),
    );
  }
  insights.sort((a, b) => b.insight.diff.abs().compareTo(a.insight.diff.abs()));
  return JournalState(dates.length, yesterday, insights);
});

String confidenceLabel(sc.Confidence c) => switch (c) {
  sc.Confidence.high => 'High',
  sc.Confidence.moderate => 'Moderate',
  sc.Confidence.low => 'Low',
  sc.Confidence.none => 'No clear effect',
  sc.Confidence.notEnough => 'Not enough data',
};

String insightText(InsightData d) {
  final i = d.insight;
  if (i.confidence == sc.Confidence.notEnough ||
      i.confidence == sc.Confidence.none) {
    return 'No clear effect yet. Keep tagging.';
  }
  final pts = i.diff.abs().round();
  final name = d.tag.name.toLowerCase();
  return i.diff < 0
      ? 'After $name, your recovery averages $pts points lower.'
      : 'After $name, your recovery averages $pts points higher.';
}

/// On Today until yesterday's check-in is done.
class JournalNudge extends ConsumerWidget {
  const JournalNudge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(journalProvider).value;
    if (j == null || j.yesterday.length >= journalTags.length) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    return TempoCard(
      label: 'Journal check-in',
      onTap: () => push(context, const JournalScreen(standalone: true)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Journal'),
                const SizedBox(height: 6),
                Text('Yesterday, quickly', style: TempoType.titleM.c(c.text1)),
                const SizedBox(height: 2),
                Text(
                  'Five taps. Tempo matches them against your recovery.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TempoButton(
            'Check in',
            small: true,
            onTap: () => push(context, const JournalScreen(standalone: true)),
          ),
        ],
      ),
    );
  }
}

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key, this.standalone = false});

  /// Pushed (back button) rather than a tab.
  final bool standalone;
  @override
  ConsumerState<JournalScreen> createState() => _JournalState();
}

class _JournalState extends ConsumerState<JournalScreen> {
  bool _insights = false;
  final _draft = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final j = ref.watch(journalProvider).value;
    final c = context.c, s = context.s;
    if (j == null) return Scaffold(backgroundColor: c.bg);
    final answers = {...j.yesterday, ..._draft};
    final locked = j.count < sc.insightsUnlockAt;
    return TempoPage(
      gap: 18,
      bottom: widget.standalone ? 48 : 100,
      children: [
        if (widget.standalone)
          DetailHeader(
            title: 'Journal',
            trailing: TempoBadge('${j.count} check-ins'),
          )
        else
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text('Journal', style: TempoType.pageTitle.c(c.text1)),
                ),
                TempoBadge('${j.count} check-ins'),
              ],
            ),
          ),
        TempoSegmented<bool>(
          values: const [false, true],
          labels: const ['Check-in', 'Insights'],
          selected: _insights,
          onChanged: (v) => setState(() => _insights = v),
        ),
        if (!_insights) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yesterday, quickly', style: TempoType.titleM.c(c.text1)),
              const SizedBox(height: 4),
              Text(
                'Five taps. Tempo matches these against your recovery.',
                style: TempoType.bodyS.c(c.text2),
              ),
            ],
          ),
          CardList(
            children: [
              for (final t in journalTags)
                Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: TempoType.body.c(c.text1)),
                            Text(t.sub, style: TempoType.caption.c(c.text3)),
                          ],
                        ),
                      ),
                      YesNo(
                        label: t.name,
                        value: answers[t.key],
                        onChanged: (v) => setState(() => _draft[t.key] = v),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          TempoButton(
            j.yesterday.length == journalTags.length && _draft.isEmpty
                ? 'Saved for yesterday'
                : 'Save check-in',
            expand: true,
            onTap: answers.isEmpty || (_draft.isEmpty && j.yesterday.isNotEmpty)
                ? null
                : () async {
                    final db = ref.read(dbProvider);
                    final y = dayOf(DateTime.now())
                        .subtract(const Duration(days: 1));
                    for (final e in answers.entries) {
                      await db.setJournal(y, e.key, e.value);
                    }
                    setState(_draft.clear);
                    if (context.mounted) {
                      showTempoToast(context, 'Check-in saved');
                    }
                  },
          ),
        ] else if (locked) ...[
          TempoCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TickRow(count: 30, filled: j.count, color: c.text1, height: 40),
                const SizedBox(height: 16),
                Text(
                  'Insights unlock at ${sc.insightsUnlockAt} check-ins',
                  style: TempoType.titleM.c(c.text1),
                ),
                const SizedBox(height: 4),
                Text(
                  '${j.count} so far. Patterns need enough nights with and without each tag to be worth showing — otherwise they’d be noise.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          TempoCard(
            color: Colors.transparent,
            border: c.line,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('What you’ll see'),
                const SizedBox(height: 10),
                Text(
                  '“On nights after alcohol, your recovery averages X points lower” — with the evidence, sample size and how confident Tempo is.',
                  style: TempoType.body.c(c.text2),
                ),
              ],
            ),
          ),
        ] else
          for (final d in j.insights)
            Opacity(
              opacity: d.insight.confidence.index <= sc.Confidence.none.index
                  ? .6
                  : 1,
              child: TempoCard(
                onTap: () => push(context, InsightDetailScreen(tag: d.tag.key)),
                label: d.tag.name,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Overline(d.tag.name)),
                        TempoBadge(confidenceLabel(d.insight.confidence)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      insightText(d),
                      style: TempoType.body.copyWith(
                        color: c.text1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 14,
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final w = (d.insight.diff.abs() / 60).clamp(
                                  .02,
                                  .5,
                                );
                                final col =
                                    d.insight.confidence.index <=
                                        sc.Confidence.none.index
                                    ? c.text3
                                    : d.insight.diff < -10
                                    ? s.recLow
                                    : s.recMid;
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 4,
                                      height: 6,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: c.trackOff,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left:
                                          box.maxWidth *
                                          (d.insight.diff < 0 ? .5 - w : .5),
                                      width: box.maxWidth * w,
                                      top: 4,
                                      height: 6,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: col,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: box.maxWidth / 2 - 1,
                                      top: 0,
                                      width: 2,
                                      height: 14,
                                      child: ColoredBox(color: c.text2),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${d.insight.nWith} vs ${d.insight.nWithout} nights',
                          style: TempoType.caption.c(c.text3).tnum,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
