import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/what_tempo_uses.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';

final whatTempoUsesProvider = FutureProvider<List<InputGroup>>((ref) async {
  ref.watch(dbTickProvider);
  final t = await ref.watch(todayProvider.future);
  return whatTempoUses(ref.read(dbProvider), t);
});

/// You → What Tempo uses (D2): every input behind the plan and the scores,
/// with where it came from. Nothing here is new data: it's a view over
/// settings and baselines, so it stays on the phone.
class WhatTempoUsesScreen extends ConsumerWidget {
  const WhatTempoUsesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final groups = ref.watch(whatTempoUsesProvider).value;
    if (groups == null) return Scaffold(backgroundColor: c.bg);
    final all = [for (final g in groups) ...g.items];
    final yours = all.where((i) => i.origin == Origin.you).length;
    final measured = all.where((i) => i.origin == Origin.measured).length;
    final open = all
        .where(
          (i) => i.origin == Origin.learning || i.origin == Origin.standard,
        )
        .length;
    return TempoPage(
      gap: 22,
      children: [
        const DetailHeader(title: 'What Tempo uses'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Everything the plan and your scores are built from. '
              'Tap anything you set to change it.',
              style: TempoType.body.c(c.text2),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Count('You set', yours)),
                Expanded(child: _Count('Measured', measured)),
                Expanded(child: _Count('Default or learning', open)),
              ],
            ),
          ],
        ),
        for (final g in groups)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Overline(g.title),
              ),
              const SizedBox(height: 8),
              CardList(
                children: [
                  for (final (i, x) in g.items.indexed) ...[
                    if (i > 0) const Hair(),
                    ListRow(
                      x.text,
                      sub: '${x.origin.label} · ${x.how}',
                      chevron: x.editable,
                      onTap: x.editable
                          ? () => Navigator.of(context).maybePop()
                          : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
        TempoButton(
          'How Tempo plans',
          kind: ButtonKind.secondary,
          expand: true,
          onTap: () => push(context, const RulesScreen()),
        ),
        Text(
          'All of this stays on this phone.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.n);
  final String label;
  final int n;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TempoType.caption.c(c.text2)),
        const SizedBox(height: 2),
        Text('$n', style: TempoType.titleM.c(c.text1).tnum),
      ],
    );
  }
}

/// The plan's rules in plain words (D2). Each is a rule the code follows;
/// see docs/decisions.md for the source of each.
const tempoRules = <(String, String)>[
  (
    'You against your own normal',
    'Every score compares you with your own last weeks, never with other people. Recovery starts after 14 nights; until then the plan is general.',
  ),
  (
    'No data is not a miss',
    'A day Tempo can’t see is left out, never counted against you.',
  ),
  (
    'Rest when the body says so',
    'Low recovery or an overreaching cardio load makes today a rest day: light movement only.',
  ),
  (
    'Resting heart rate is a warning light',
    'Five beats above your normal across the week eases the plan off. 10 % above, or three nights at +5, means rest and a health check prompt.',
  ),
  (
    'No hard day after a hard day',
    'Quality sessions only come on a go day, with no hard day in the last 48 hours and fewer than two this week.',
  ),
  (
    'Hard work ends early',
    'A hard session ends at least 4 hours before bed, an easy one 1 hour, a walk 30 minutes.',
  ),
  (
    'Missed sessions',
    'A missed easy session drops. A missed hard or long one carries forward.',
  ),
  (
    'Moved sessions',
    'A moved session never goes to tomorrow, or next to a hard or strength day.',
  ),
  (
    'How sessions felt',
    'When your last three rated sessions felt heavier than planned, the next hard one eases; lighter, and an easy one steps up.',
  ),
  (
    'Bedtime moves slowly',
    'Tonight’s bedtime moves earlier at most 15 minutes at a time from your usual, toward what your need asks for. It never asks for later.',
  ),
  (
    'Sleep debt has a cap',
    'Debt counts against your base need over 14 nights, fades as you sleep, and is capped at 2 hours.',
  ),
  (
    'Quiet by default',
    'One nudge a day unless you ask for more, none between bedtime and wake, and no streaks.',
  ),
  (
    'Read, never written',
    'Tempo reads Apple Health or Health Connect and never writes back what it read.',
  ),
];

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'How Tempo plans'),
        Text(
          'The plan changes every day, always by these rules.',
          style: TempoType.body.c(c.text2),
        ),
        CardList(
          children: [
            for (final (i, (title, body)) in tempoRules.indexed) ...[
              if (i > 0) const Hair(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TempoType.label.c(c.text1)),
                    const SizedBox(height: 4),
                    Text(body, style: TempoType.bodyS.c(c.text2)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
