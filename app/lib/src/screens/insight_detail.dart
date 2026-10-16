import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/journal.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'journal.dart';

final _pastProvider = FutureProvider<List<sc.Experiment>>((ref) async {
  ref.watch(dbTickProvider);
  return loadPastExperiments(ref.watch(dbProvider));
});

/// One journal entry across every outcome: the adjusted effect and its
/// likely range, the raw days behind it, experiments and a way to start
/// one.
class InsightDetailScreen extends ConsumerWidget {
  const InsightDetailScreen({
    super.key,
    required this.tag,
    this.outcome = sc.Outcome.recovery,
  });
  final String tag;
  final sc.Outcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final days = ref.watch(impactDaysProvider).value;
    final j = ref.watch(journalProvider).value;
    final rows = <sc.Outcome, sc.Impact>{
      for (final o in sc.Outcome.values)
        if (ref.watch(impactsProvider(o)).value case final v?)
          for (final i in v.$1)
            if (i.key == tag) o: i,
    };
    final def = j?.config.def(tag);
    final name = def?.name ?? tag;
    final main = rows[outcome];
    final past = [
      for (final e in ref.watch(_pastProvider).value ?? const <sc.Experiment>[])
        if (e.key == tag) e,
    ];
    return TempoPage(
      children: [
        DetailHeader(title: name),
        if (main == null || days == null)
          const SizedBox(height: 300)
        else ...[
          Text(
            main.shown
                ? '${outcomeName(outcome)} ${effectText(outcome, main.effect)}${def == null ? '' : doseWords(def)} after ${name.toLowerCase()}.'
                : 'No clear link yet between ${name.toLowerCase()} and your ${outcomeName(outcome).toLowerCase()}.',
            style: TempoType.titleL.c(c.text1),
          ),
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Every outcome', style: TempoType.label.c(c.text1)),
                const SizedBox(height: 4),
                Text(
                  'Adjusted for your other entries, the day’s strain and weekends. The bar is the likely range.',
                  style: TempoType.caption.c(c.text3),
                ),
                for (final o in sc.Outcome.values)
                  if (rows[o] case final i?) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            outcomeName(o),
                            style: TempoType.bodyS.c(c.text1),
                          ),
                        ),
                        Text(
                          i.confidence == sc.ImpactConfidence.notEnough
                              ? 'Not enough days'
                              : '${effectText(o, i.effect)} · ${confidenceWord(i.confidence)}',
                          style: TempoType.caption
                              .c(
                                i.shown
                                    ? (i.helps
                                          ? context.s.recHigh
                                          : context.s.recLow)
                                    : c.text2,
                              )
                              .tnum,
                        ),
                      ],
                    ),
                    if (i.confidence != sc.ImpactConfidence.notEnough) ...[
                      const SizedBox(height: 6),
                      EffectBar(i),
                    ],
                  ],
              ],
            ),
          ),
          _RawDays(tag: tag, outcome: outcome, days: days, name: name),
          if (def != null && !def.automatic && def.kind == sc.EntryKind.yesNo)
            TempoButton(
              'Try a 14-day experiment',
              kind: ButtonKind.secondary,
              expand: true,
              onTap: j?.experiment != null
                  ? null
                  : () => offerExperiment(
                      context,
                      ref,
                      def,
                      suggestAvoid: !(main.helps),
                    ),
            ),
          if (j?.experiment != null)
            Text(
              'One experiment runs at a time.',
              style: TempoType.caption.c(c.text3),
            ),
          for (final e in past) _PastExperiment(e: e, name: name, days: days),
        ],
      ],
    );
  }
}

class _RawDays extends StatelessWidget {
  const _RawDays({
    required this.tag,
    required this.outcome,
    required this.days,
    required this.name,
  });
  final String tag, name;
  final sc.Outcome outcome;
  final List<sc.ImpactDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final yes = <double>[], no = <double>[];
    for (final d in days) {
      final v = d.x[tag], y = d.y[outcome];
      if (v == null || y == null) continue;
      (v != 0 ? yes : no).add(y);
    }
    final all = [...yes, ...no];
    if (all.length < 2) return const SizedBox.shrink();
    final lo = all.reduce((a, b) => a < b ? a : b);
    final hi = all.reduce((a, b) => a > b ? a : b);
    Widget strip(String label, List<double> vs) {
      final avg = vs.isEmpty ? null : vs.reduce((a, b) => a + b) / vs.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label · ${vs.length} days', style: TempoType.bodyS.c(c.text1)),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (_, box) {
              double x(double v) => hi - lo < 1e-9
                  ? box.maxWidth / 2
                  : (v - lo) / (hi - lo) * (box.maxWidth - 8);
              return Container(
                height: 30,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    for (final (k, v) in vs.indexed)
                      Positioned(
                        left: x(v),
                        top: 5.0 + (k % 3) * 7,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.text2,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    if (avg != null)
                      Positioned(
                        left: x(avg) + 2,
                        top: 0,
                        width: 3,
                        height: 30,
                        child: ColoredBox(color: c.text1),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    }

    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The days behind it (${outcomeName(outcome).toLowerCase()}, not adjusted)',
            style: TempoType.label.c(c.text1),
          ),
          const SizedBox(height: 12),
          strip('Without ${name.toLowerCase()}', no),
          const SizedBox(height: 12),
          strip('With ${name.toLowerCase()}', yes),
        ],
      ),
    );
  }
}

class _PastExperiment extends StatelessWidget {
  const _PastExperiment({
    required this.e,
    required this.name,
    required this.days,
  });
  final sc.Experiment e;
  final String name;
  final List<sc.ImpactDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline('Experiment · ${experimentTitle(e, name)}'),
          for (final o in [
            sc.Outcome.recovery,
            sc.Outcome.sleepPerf,
            sc.Outcome.sleptHours,
          ])
            Builder(
              builder: (_) {
                final r = sc.experimentResult(e, days, o);
                final shown =
                    r.confidence.index >= sc.ImpactConfidence.low.index;
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          outcomeName(o),
                          style: TempoType.bodyS.c(c.text1),
                        ),
                      ),
                      Text(
                        r.confidence == sc.ImpactConfidence.notEnough
                            ? 'Not enough days'
                            : shown
                            ? '${effectText(o, r.effect)} (${effectText(o, r.low)} to ${effectText(o, r.high)})'
                            : 'No clear change',
                        style: TempoType.caption.c(c.text2).tnum,
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Text(
            'Kept to it on ${(sc.experimentResult(e, days, sc.Outcome.recovery).adherence * 100).round()} % of logged days.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}
