import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

final _baselineProvider = FutureProvider.family<List<st.DailyScore>, int>((
  ref,
  days,
) async {
  ref.watch(dbTickProvider);
  final today = dayOf(DateTime.now());
  return ref
      .watch(dbProvider)
      .scoresBetween(today.subtract(Duration(days: days - 1)), today);
});

/// "Your normal" = the middle 80 % of your own nights.
class BaselinesScreen extends ConsumerStatefulWidget {
  const BaselinesScreen({super.key});
  @override
  ConsumerState<BaselinesScreen> createState() => _BaselinesState();
}

class _BaselinesState extends ConsumerState<BaselinesScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(_baselineProvider(_days)).value;
    final c = context.c;
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Your baselines'),
        Text(
          'Your “normal” is the middle 80% of your own nights. Recovery compares each morning with these bands.',
          style: TempoType.body.c(c.text2),
        ),
        TempoSegmented<int>(
          values: const [30, 90],
          labels: const ['30 days', '90 days'],
          selected: _days,
          onChanged: (v) => setState(() => _days = v),
        ),
        if (rows != null) ...[
          _card(
            context,
            'Resting heart rate',
            false,
            [for (final r in rows) r.rhr],
            'bpm',
            'lower is better',
            (v) => '${v.round()}',
            (last, lo, hi, med) {
              final edge = last <= lo + 1
                  ? ' — at the low edge of normal'
                  : last >= hi - 1
                  ? ' — at the high edge of normal'
                  : ' — inside your normal';
              return 'Last night ${last.round()}$edge.';
            },
          ),
          _card(
            context,
            'Stress index, overnight',
            true,
            [for (final r in rows) r.hrvProxy],
            '',
            'lower is better',
            (v) => '${v.round()}',
            (last, lo, hi, med) {
              return 'Last night ${last.round()}. ${last > hi ? 'Above your normal — late meals and alcohol often do this (see Journal insights).' : 'Inside or below your normal.'}';
            },
          ),
          _card(
            context,
            'Sleep duration',
            false,
            [for (final r in rows) r.sleptHours],
            '',
            'need est. ${hmShort(const sc.SleepParams().baseNeedHours)}',
            hmShort,
            (last, lo, hi, med) {
              return 'Last night ${hmShort(last)}. Baseline need is estimated at ${hmShort(const sc.SleepParams().baseNeedHours)} and adjusts with strain and debt.';
            },
          ),
        ],
        Text(
          'Baselines update every morning. One unusual night barely moves them; a week of change does.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    String name,
    bool proxy,
    List<double?> vals,
    String unit,
    String dir,
    String Function(double) fmt,
    String Function(double last, double lo, double hi, double med) note,
  ) {
    final c = context.c;
    final known = vals.whereType<double>().toList();
    final lo = sc.quantile(known, .1),
        hi = sc.quantile(known, .9),
        med = sc.quantile(known, .5);
    final last = vals.isEmpty ? null : vals.last;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(name, style: TempoType.label.c(c.text1)),
              if (proxy) ...[
                const SizedBox(width: 8),
                const TempoBadge('≈ proxy', small: true),
              ],
              const Spacer(),
              Text(dir, style: TempoType.caption.c(c.text3)),
            ],
          ),
          const SizedBox(height: 10),
          if (known.length < 5)
            TempoEmpty(
              'Your normal appears after ${5 - known.length} more nights.',
              kind: EmptyKind.trend,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${fmt(lo!)}–${fmt(hi!)}',
                  style: TempoType.scoreS.c(c.text1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${unit.isEmpty ? '' : '$unit '}normal · median ${fmt(med!)}',
                    style: TempoType.caption.c(c.text3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SvgChart(
              height: 120,
              semantics: '$name with normal range',
              draw: (ink, box) {
                final mn = known.reduce((a, b) => a < b ? a : b),
                    mx = known.reduce((a, b) => a > b ? a : b);
                final pad = (mx - mn) * .2 + .01;
                double y(double v) =>
                    114 - (v - (mn - pad)) / ((mx + pad) - (mn - pad)) * 108;
                final n = vals.length;
                double x(int i) => n <= 1 ? 520 : i / (n - 1) * 520;
                ink.rect(Rect.fromLTRB(0, y(hi), 520, y(lo)), ink.c.surface3);
                ink.line(
                  Offset(0, y(med)),
                  Offset(520, y(med)),
                  ink.c.text3,
                  dash: [4, 4],
                );
                ink.gappedLine(
                  [
                    for (final (i, v) in vals.indexed)
                      v == null ? null : Offset(x(i), y(v)),
                  ],
                  ink.c.text1,
                  w: 2.5,
                );
                if (last != null) ink.dot(Offset(520, y(last)), 6, ink.c.text1);
              },
            ),
            if (last != null) ...[
              const SizedBox(height: 10),
              Text(note(last, lo, hi, med), style: TempoType.bodyS.c(c.text2)),
            ],
          ],
        ],
      ),
    );
  }
}
