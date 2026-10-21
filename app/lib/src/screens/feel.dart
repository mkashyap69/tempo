import 'package:flutter/material.dart';
import 'package:scoring/scoring.dart' as sc;

import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';

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
