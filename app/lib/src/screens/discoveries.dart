import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/journal.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'highlight.dart' show InsightArchiveScreen;
import 'journal.dart';
import 'nav.dart';

/// v3 Discoveries (canvas "Discoveries and experiments"): what moves your
/// numbers, found in your own data, each with how sure Tempo is.
class DiscoveriesScreen extends ConsumerWidget {
  const DiscoveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final impacts = ref.watch(impactsProvider(sc.Outcome.recovery)).value;
    final j = ref.watch(journalProvider).value;
    final days = ref.watch(impactDaysProvider).value;
    final config = impacts?.$2;
    String name(String key) => config?.def(key)?.name ?? key;
    final judged = [
      for (final i in impacts?.$1 ?? const <sc.Impact>[])
        if (i.confidence == sc.ImpactConfidence.low ||
            i.confidence == sc.ImpactConfidence.moderate ||
            i.confidence == sc.ImpactConfidence.high)
          i,
    ]..sort((a, b) => b.effect.abs().compareTo(a.effect.abs()));
    final shown = judged.take(8).toList();
    final top = shown.isEmpty
        ? 1.0
        : shown.map((i) => i.effect.abs()).reduce(math.max);
    final e = j?.experiment;
    final ideas = e != null || impacts == null
        ? const <sc.ExperimentIdea>[]
        : sc.experimentSuggestions([
            for (final i in impacts.$1)
              if (impacts.$2.asked.any((d) => d.key == i.key)) i,
          ]);

    return TempoPage(
      children: [
        DetailHeader(
          title: 'Discoveries',
          subtitle: j == null ? null : 'From ${j.count} check-ins',
        ),
        Text('What moves your numbers', style: TempoType.titleL.c(c.text1)),
        Text(
          'Found in your own data, not general advice. Each says how sure Tempo is.',
          style: TempoType.body.c(c.text2),
        ),
        if (e != null)
          Container(
            key: const ValueKey('discoveries-experiment'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface1,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .8],
                colors: [
                  Color.alphaBlend(s.recMid.withValues(alpha: .10), c.surface1),
                  c.surface1,
                ],
              ),
              borderRadius: BorderRadius.circular(TempoRadii.lg),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Overline(
                        'Experiment · day ${e.dayOn(DateTime.now())} of ${e.days}',
                        color: s.recMid,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  experimentTitle(e, name(e.key)),
                  style: TempoType.titleM.c(c.text1),
                ),
                if (days != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    experimentSoFar(
                      sc.experimentResult(e, days, sc.Outcome.recovery),
                    ),
                    style: TempoType.bodyS.c(c.text2),
                  ),
                ],
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.dayOn(DateTime.now()) / e.days,
                    minHeight: 6,
                    backgroundColor: c.trackOff,
                    color: s.recMid,
                  ),
                ),
              ],
            ),
          ),
        Section(
          title: 'Effect on next-morning recovery',
          child: TempoCard(
            child: shown.isEmpty
                ? Text(
                    'Nothing clear yet. Check in each morning; patterns firm up over a few weeks.',
                    style: TempoType.bodyS.c(c.text2),
                  )
                : Column(
                    key: const ValueKey('impact-bars'),
                    children: [
                      for (final i in shown)
                        _ImpactRow(
                          name: name(i.key),
                          effect: i.effect,
                          top: top,
                          helps: i.helps,
                          confidence: i.confidence,
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Points of recovery the morning after, other things held equal. Fainter bars: less sure.',
                        style: TempoType.caption.c(c.text3),
                      ),
                    ],
                  ),
          ),
        ),
        if (ideas.isNotEmpty)
          Section(
            title: 'Try next',
            child: CardList(
              children: [
                for (final idea in ideas)
                  ListRow(
                    'Try 14 days ${idea.doIt ? 'of' : 'without'} ${name(idea.key).toLowerCase()}',
                    sub:
                        '${effectText(sc.Outcome.recovery, idea.effect)} recovery when you do',
                    value: 'Start',
                    onTap: () async {
                      await startExperiment(
                        ref.read(dbProvider),
                        idea.key,
                        idea.doIt,
                      );
                      if (context.mounted) {
                        showTempoToast(context, 'Experiment started');
                      }
                    },
                  ),
              ],
            ),
          ),
        CardList(
          children: [
            ListRow(
              'All insights',
              sub: 'Everything Today has shown you, by month',
              onTap: () => push(context, const InsightArchiveScreen()),
            ),
            ListRow(
              'Journal',
              sub: 'Check in and choose what it asks',
              onTap: () => push(context, const JournalScreen(standalone: true)),
            ),
          ],
        ),
      ],
    );
  }
}

/// One habit's effect as a bar from the middle: right helps, left hurts.
class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.name,
    required this.effect,
    required this.top,
    required this.helps,
    required this.confidence,
  });
  final String name;
  final double effect, top;
  final bool helps;
  final sc.ImpactConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final col = (helps ? s.recHigh : s.recLow).withValues(
      alpha: switch (confidence) {
        sc.ImpactConfidence.high => 1,
        sc.ImpactConfidence.moderate => .75,
        _ => .45,
      },
    );
    final frac = (effect.abs() / top).clamp(.04, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TempoType.bodyS.c(c.text1),
            ),
          ),
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: helps ? 0 : frac,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 16, color: c.text3),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: helps ? frac : 0,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              effectText(sc.Outcome.recovery, effect),
              textAlign: TextAlign.right,
              style: TempoType.bodyS.c(helps ? s.recHigh : s.recLow).tnum,
            ),
          ),
        ],
      ),
    );
  }
}
