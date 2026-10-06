import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// Morning check-in: how you feel, 1–5, before you read the day's call.
class FeelCard extends ConsumerWidget {
  const FeelCard({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    Widget option(int v) => Expanded(
      child: Pressable(
        label: 'Feel $v of 5: ${sc.feelWords[v - 1]}',
        onTap: () {
          TempoHaptics.selection();
          ref.read(dbProvider).setFeel(day, v);
        },
        child: Container(
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TempoRadii.md),
            border: Border.all(color: c.lineStrong),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$v', style: TempoType.titleM.c(c.text1).tnum),
                Text(sc.feelWords[v - 1], style: TempoType.caption.c(c.text2)),
              ],
            ),
          ),
        ),
      ),
    );
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('Morning check-in'),
          const SizedBox(height: 10),
          Text('How do you feel?', style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            'Answer before you look at your scores. Tempo checks whether Recovery matches how you feel.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 14),
          Row(children: [for (var v = 1; v <= 5; v++) option(v)]),
        ],
      ),
    );
  }
}

/// Recovery against the morning check-ins (Recovery screen).
class FeelVsRecoveryCard extends StatelessWidget {
  const FeelVsRecoveryCard({super.key, required this.cmp});
  final sc.FeelComparison cmp;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final (word, color, body) = switch (cmp.fit) {
      sc.FeelFit.learning => (
        'Learning',
        c.text2,
        cmp.n < sc.feelMinPairs
            ? '${cmp.n} of ${sc.feelMinPairs} rated mornings. Answer the check-in on Today each morning to see whether Recovery matches how you feel.'
            : 'Your ratings barely vary yet, so there’s nothing to compare. Keep answering honestly.',
      ),
      sc.FeelFit.tracks => (
        'Tracks',
        s.recHigh,
        'Better recovery mornings are the ones you feel better on. Trust the score.',
      ),
      sc.FeelFit.loose => (
        'Loosely',
        s.recMid,
        'Recovery and how you feel move together, but often disagree. Treat the score as one input, not the verdict.',
      ),
      sc.FeelFit.off => (
        'Doesn’t match',
        s.recLow,
        'Recovery doesn’t follow how you feel yet. Go by feel, and treat this as a sign the score needs retuning.',
      ),
    };
    final detail = [
      if (cmp.n > 0) 'Same colour on ${cmp.agree} of ${cmp.n} mornings',
      if (cmp.recoveryHigh > 0) 'green when you felt 1–2: ${cmp.recoveryHigh}',
      if (cmp.recoveryLow > 0) 'red when you felt 4–5: ${cmp.recoveryLow}',
    ].join(' · ');
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recovery vs how you feel',
                  style: TempoType.label.c(c.text1),
                ),
              ),
              Text(word, style: TempoType.label.c(color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: TempoType.bodyS.c(c.text2)),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detail, style: TempoType.caption.c(c.text3).tnum),
          ],
        ],
      ),
    );
  }
}
