import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/score_check.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

final _scoreCheckProvider = dbQuery((db, ref) => loadScoreCheck(db));

/// Profile → Developer → Score check: how this phone's scores spread, how
/// noisy they are day to day, and whether Recovery agrees with how you
/// felt and with your body signals (docs/research/Algorithm review.md §11).
class ScoreCheckScreen extends ConsumerWidget {
  const ScoreCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final r = ref.watch(_scoreCheckProvider).value;
    String f(double v) => v.toStringAsFixed(1);
    return TempoPage(
      gap: 16,
      bottom: 48,
      children: [
        const DetailHeader(title: 'Score check'),
        Text(
          'Your last $scoreCheckDays days of scores, checked the way the algorithm review checks them. Read-only; nothing leaves the phone.',
          style: TempoType.body.c(c.text1),
        ),
        if (r == null)
          const SizedBox.shrink()
        else if (r.days == 0)
          const TempoEmpty('No scored days yet.')
        else ...[
          const Overline('Spread and day-to-day noise'),
          CardList(
            children: [
              for (final k in r.spread.keys)
                ListRow(
                  k,
                  chevron: false,
                  value: r.spread[k] == null
                      ? '—'
                      : 'median ${f(r.spread[k]!.p50)} · ${f(r.spread[k]!.p10)}–${f(r.spread[k]!.p90)}',
                  sub: r.noise[k] == null
                      ? 'Needs 10 days in a row to judge noise'
                      : 'Moves ±${f(r.noise[k]!.typicalError)} a day; '
                            'a change over ${f(r.noise[k]!.mdc95)} is real',
                ),
            ],
          ),
          const Overline('Does Recovery track you?'),
          CardList(
            children: [
              ListRow(
                'Recovery colours',
                chevron: false,
                value:
                    '${_pct(r.colours[sc.RecoveryColor.green]!)} green · '
                    '${_pct(r.colours[sc.RecoveryColor.yellow]!)} yellow · '
                    '${_pct(r.colours[sc.RecoveryColor.red]!)} red',
              ),
              ListRow(
                'Against morning feel',
                chevron: false,
                value: r.feel.rho == null
                    ? '—'
                    : 'ρ ${r.feel.rho!.toStringAsFixed(2)}',
                sub: r.feel.n < sc.feelMinPairs
                    ? '${r.feel.n} of ${sc.feelMinPairs} rated mornings so far'
                    : '${r.feel.agree} of ${r.feel.n} mornings in the same band',
              ),
              ListRow(
                'Body-signal days',
                chevron: false,
                value: r.offDaysBelow == null
                    ? '—'
                    : '${_pct(r.offDaysBelow!)} below usual',
                sub: r.offDaysBelow == null
                    ? '${r.offDays} so far; needs 3'
                    : 'Recovery before the vitals penalty, on ${r.offDays} days with night vitals off',
              ),
            ],
          ),
          const Overline('Algorithm'),
          CardList(
            children: [
              for (final e in r.algoVersions.entries)
                ListRow(
                  'Algo ${e.key}',
                  chevron: false,
                  value: '${e.value} days',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _pct(double x) => '${(x * 100).round()} %';
