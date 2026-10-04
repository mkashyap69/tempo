import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'journal.dart';

class InsightDetailScreen extends ConsumerWidget {
  const InsightDetailScreen({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(journalProvider).value;
    final c = context.c, s = context.s;
    final d = j?.insights.where((x) => x.tag.key == tag).firstOrNull;
    if (d == null) return Scaffold(backgroundColor: c.bg);
    final i = d.insight;
    final yes = [
      for (final n in d.nights)
        if (n.$2) n.$3,
    ];
    final no = [
      for (final n in d.nights)
        if (!n.$2) n.$3,
    ];
    double? mean(Iterable<double?> x) {
      final v = x.whereType<double>().toList();
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    String diff(double? a, double? b, String unit, {int dp = 0}) {
      if (a == null || b == null) return '—';
      final x = a - b;
      return '${x >= 0 ? '+' : '−'}${x.abs().toStringAsFixed(dp)}$unit';
    }

    final untagged = j!.count - d.nights.length;
    final strong = i.confidence.index >= sc.Confidence.low.index;
    Widget group(String name, List<st.DailyScore> xs) {
      final vals = [for (final x in xs) x.recovery!];
      final avg = vals.isEmpty
          ? 0.0
          : vals.reduce((a, b) => a + b) / vals.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: TempoType.bodyS.c(c.text1))),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'avg '),
                    TextSpan(
                      text: '${avg.round()}%',
                      style: TextStyle(color: c.text1),
                    ),
                    TextSpan(text: ' · ${vals.length} nights'),
                  ],
                ),
                style: TempoType.bodyS.c(c.text2).tnum,
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) => Container(
              height: 34,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (k, v) in vals.indexed)
                    Positioned(
                      left: v / 100 * box.maxWidth - 4,
                      top: 6.0 + (k % 3) * 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: s.recoveryFor(v),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (vals.isNotEmpty)
                    Positioned(
                      left: avg / 100 * box.maxWidth - 1.5,
                      top: -4,
                      width: 3,
                      height: 42,
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.text1,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return TempoPage(
      children: [
        const DetailHeader(title: 'Insight'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(
              '${d.tag.name} · last ${d.nights.isEmpty ? 0 : DateTime.now().difference(d.nights.map((n) => n.$1).reduce((a, b) => a.isBefore(b) ? a : b)).inDays} days',
            ),
            const SizedBox(height: 8),
            Text.rich(
              strong
                  ? TextSpan(
                      children: [
                        TextSpan(
                          text:
                              'On nights after ${d.tag.name.toLowerCase()}, your recovery averages ',
                        ),
                        TextSpan(
                          text:
                              '${i.diff.abs().round()} points ${i.diff < 0 ? 'lower' : 'higher'}',
                          style: TextStyle(
                            color: i.diff < 0 ? s.recLow : s.recHigh,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    )
                  : TextSpan(
                      text:
                          'No clear link yet between ${d.tag.name.toLowerCase()} and your recovery.',
                    ),
              style: TempoType.titleL.copyWith(
                fontSize: 26,
                height: 32 / 26,
                color: c.text1,
              ),
            ),
          ],
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Next-morning recovery', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 14),
              group('Without ${d.tag.name.toLowerCase()}', no),
              const SizedBox(height: 14),
              group('After ${d.tag.name.toLowerCase()}', yes),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in ['0%', '50%', '100%'])
                    Text(t, style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TempoCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Overline('Confidence'),
                    const SizedBox(height: 8),
                    Text(
                      confidenceLabel(i.confidence),
                      style: TempoType.titleM.c(c.text1),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var k = 0; k < 3; k++) ...[
                          if (k > 0) const SizedBox(width: 3),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: k < (i.confidence.index - 1).clamp(0, 3)
                                    ? c.text1
                                    : c.trackOff,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${i.diff < 0 ? 'Lower' : 'Higher'} on ${i.consistent} of ${i.nWith} ${d.tag.name.toLowerCase()} nights',
                      style: TempoType.caption.c(c.text2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TempoCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('Sample'),
                    const SizedBox(height: 8),
                    Text(
                      '${i.nWith} vs ${i.nWithout}',
                      style: TempoType.titleM.c(c.text1).tnum,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'nights with / without.${untagged > 0 ? ' $untagged nights untagged are excluded.' : ''}',
                      style: TempoType.caption.c(c.text2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        CardList(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('What moved', style: TempoType.label.c(c.text1)),
            ),
            for (final (k, v, badge) in [
              (
                'Resting HR',
                diff(
                  mean(yes.map((x) => x.rhr)),
                  mean(no.map((x) => x.rhr)),
                  ' bpm',
                ),
                false,
              ),
              (
                'Overnight stress',
                diff(
                  mean(yes.map((x) => x.hrvProxy)),
                  mean(no.map((x) => x.hrvProxy)),
                  '',
                ),
                true,
              ),
              (
                'Sleep',
                diff(
                  mean(
                    yes.map(
                      (x) => x.sleptHours == null ? null : x.sleptHours! * 60,
                    ),
                  ),
                  mean(
                    no.map(
                      (x) => x.sleptHours == null ? null : x.sleptHours! * 60,
                    ),
                  ),
                  ' min',
                ),
                false,
              ),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(k, style: TempoType.bodyS.c(c.text1)),
                    if (badge) ...[
                      const SizedBox(width: 6),
                      const TempoBadge('≈', small: true),
                    ],
                    const Spacer(),
                    Text(v, style: TempoType.bodyS.c(c.text2).tnum),
                  ],
                ),
              ),
          ],
        ),
        Text(
          'A pattern in your own data, not a medical finding. Other things often happen on the same nights (late meals, late nights), so treat it as a strong hint.',
          style: TempoType.caption.c(c.text3),
        ),
        if (d.nights.isNotEmpty)
          Text(
            'Nights from ${dm(d.nights.first.$1)} to ${dm(d.nights.last.$1)}.',
            style: TempoType.caption.c(c.text3),
          ),
      ],
    );
  }
}
