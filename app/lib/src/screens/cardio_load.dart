import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach.dart' show loadHistoryProvider;
import 'shared.dart';

List<String> loadAdvice(sc.LoadStatus s) => switch (s) {
  sc.LoadStatus.building => [
    'Two hard sessions at most this week.',
    'Keep easy days truly easy: under 10 strain.',
    'Protect sleep: aim for your bedtime target 5 of 7 nights.',
  ],
  sc.LoadStatus.maintaining => [
    'Add one session in Z3–Z4 if recovery is green.',
    'Or lengthen one Z2 session by 15 minutes.',
    'Nothing to change if this week is meant to be light.',
  ],
  sc.LoadStatus.detraining => [
    'Restart with three easy 30-minute sessions.',
    'Hold intensity until load is back near normal.',
    'If you’re ill or travelling, ignore this — rest is right.',
  ],
  sc.LoadStatus.overreaching => [
    'Two easy days before any intensity.',
    'Cap each day at 10 strain until load drops back into range.',
    'Go to bed by your target — sleep is the fastest fix.',
  ],
  sc.LoadStatus.learning => [
    'Wear the band through every session so load starts counting.',
    'Status appears after 7 days of data.',
    'Until then, the plan stays general and moderate.',
  ],
};

class CardioLoadScreen extends ConsumerStatefulWidget {
  const CardioLoadScreen({super.key});
  @override
  ConsumerState<CardioLoadScreen> createState() => _CardioLoadState();
}

class _CardioLoadState extends ConsumerState<CardioLoadScreen> {
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(todayProvider).value;
    final all = ref.watch(loadHistoryProvider).value;
    if (t == null || all == null) {
      return Scaffold(backgroundColor: context.c.bg);
    }
    final c = context.c, s = context.s;
    final l = t.load;
    final col = loadColor(context, l.status);
    final hist = all.length > _weeks ? all.sublist(all.length - _weeks) : all;
    final idx = switch (l.status) {
      sc.LoadStatus.detraining => 0,
      sc.LoadStatus.maintaining => 1,
      sc.LoadStatus.building => 2,
      sc.LoadStatus.overreaching => 3,
      sc.LoadStatus.learning => -1,
    };
    final pos = l.status == sc.LoadStatus.learning ? null : _markerPos(l.ratio);
    final p = l.percentVsNormal;
    final lead = switch (l.status) {
      sc.LoadStatus.learning => 'Tempo needs 7 days of heart rate to compare your week with your normal.',
      sc.LoadStatus.building =>
        'Your last 7 days are $p% above your 28-day normal. That’s the productive zone: fitness grows if recovery keeps up.',
      sc.LoadStatus.maintaining => 'Your week matches your normal. Fitness holds steady — fine for a busy week, slow for progress.',
      sc.LoadStatus.detraining =>
        'Your last 7 days are ${p.abs()}% below your normal. A week or two is a useful rest; longer and fitness starts to fade.',
      sc.LoadStatus.overreaching =>
        'Your last 7 days are $p% above your normal. That’s more than your body is used to; recovery usually dips next.',
    };
    return TempoPage(
      children: [
        DetailHeader(
          title: 'Cardio load',
          trailing: TempoIconButton(
            TempoIcons.info,
            label: 'What is cardio load?',
            stroke: 1.75,
            onTap: () => _explain(context, l),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${loadGlyph(l.status)} ${loadWord(l.status)}',
              style: TempoType.scoreL.copyWith(
                fontSize: 44,
                height: 48 / 44,
                fontWeight: FontWeight.w400,
                letterSpacing: -1.3,
                color: col,
              ),
            ),
            const SizedBox(height: 8),
            Text(lead, style: TempoType.body.c(c.text2)),
          ],
        ),
        Semantics(
          label: 'Status scale',
          child: Column(
            children: [
              SizedBox(
                height: 20,
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 6,
                        child: Row(
                          children: [
                            for (final (i, col2) in [
                              s.loadDetraining,
                              s.loadMaintaining,
                              s.loadBuilding,
                              s.loadOverreaching,
                            ].indexed) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                child: Opacity(
                                  opacity: i == idx ? 1 : .28,
                                  child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: col2,
                                      borderRadius: BorderRadius.horizontal(
                                        left: Radius.circular(i == 0 ? 4 : 0),
                                        right: Radius.circular(i == 3 ? 4 : 0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (pos != null)
                        Positioned(
                          left: pos * box.maxWidth - 2,
                          top: 0,
                          width: 4,
                          height: 20,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final x in [
                    '↘ Detraining',
                    '● Maintaining',
                    '↗ Building',
                    '⚠ Overreaching',
                  ])
                    Expanded(
                      child: Text(x, style: TempoType.caption.c(c.text3)),
                    ),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Last $_weeks weeks',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  TempoSegmented<int>(
                    width: 102,
                    height: 32,
                    values: const [8, 12],
                    labels: const ['8w', '12w'],
                    selected: _weeks,
                    onChanged: (v) => setState(() => _weeks = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (hist.length < 2)
                const TempoEmpty(
                  'Trends appear after 7 days.',
                  kind: EmptyKind.trend,
                )
              else
                SvgChart(
                  height: 220,
                  semantics: '7-day load against your productive range',
                  draw: (ink, box) {
                    final vals = [
                      for (final h in hist) ...[
                        h.acute,
                        h.chronic * 1.3,
                        h.chronic * .8,
                      ],
                    ];
                    final hi = vals.reduce((a, b) => a > b ? a : b) * 1.05,
                        lo = vals.reduce((a, b) => a < b ? a : b) * .9;
                    double y(double v) =>
                        206 - (v - lo) / (hi - lo == 0 ? 1 : hi - lo) * 190;
                    double x(int i) => i * 520 / (hist.length - 1);
                    ink.area(
                      [
                        for (final (i, h) in hist.indexed)
                          Offset(x(i), y(h.chronic * 1.3)),
                      ],
                      [
                        for (final (i, h) in hist.indexed)
                          Offset(x(i), y(h.chronic * .8)),
                      ],
                      ink.s.loadBuilding,
                      .12,
                    );
                    ink.polyline(
                      [
                        for (final (i, h) in hist.indexed)
                          Offset(x(i), y(h.chronic)),
                      ],
                      ink.c.text3,
                      w: 2,
                      dash: [6, 6],
                    );
                    ink.polyline(
                      [
                        for (final (i, h) in hist.indexed)
                          Offset(x(i), y(h.acute)),
                      ],
                      ink.c.text1,
                      w: 3,
                    );
                    ink.ring(
                      Offset(x(hist.length - 1), y(hist.last.acute)),
                      9,
                      col,
                      w: 3,
                      inside: ink.c.surface1,
                    );
                    ink.line(
                      const Offset(0, 216),
                      const Offset(520, 216),
                      ink.c.line,
                    );
                    ink.text(
                      dm(
                        DateTime.now().subtract(
                          Duration(days: 7 * (hist.length - 1)),
                        ),
                      ),
                      const Offset(0, 210),
                      size: 16,
                    );
                    ink.text(
                      'This week',
                      const Offset(520, 210),
                      size: 16,
                      align: TextAlign.right,
                    );
                  },
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  Legend(c.text1, 'Last 7 days', width: 14, height: 2),
                  Legend(
                    c.text3,
                    'Your 28-day normal',
                    width: 14,
                    dashed: true,
                  ),
                  Legend(
                    s.loadBuilding.withValues(alpha: .3),
                    'Productive range',
                    width: 14,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Hair(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Stat(
                      'Last 7 days',
                      '${l.acute.round()}',
                      unit: ' /day',
                    ),
                  ),
                  Expanded(
                    child: Stat(
                      '28-day normal',
                      '${l.chronic.round()}',
                      unit: ' /day',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'What to do this week',
          child: CardList(
            children: [
              for (final (i, a) in loadAdvice(l.status).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 14,
                        child: Text(
                          '${i + 1}',
                          style: TempoType.label.c(c.text3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(a, style: TempoType.body.c(c.text1)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TempoButton(
            'What is cardio load?',
            kind: ButtonKind.ghost,
            icon: TempoIcons.info,
            onTap: () => _explain(context, l),
          ),
        ),
      ],
    );
  }

  /// Ratio → marker position across the four equal segments.
  static double _markerPos(double r) {
    if (r < .8) return (r / .8 * .25).clamp(.03, .25);
    if (r < 1) return .25 + (r - .8) / .2 * .25;
    if (r <= 1.3) return .5 + (r - 1) / .3 * .25;
    return (.75 + (r - 1.3) / .4 * .25).clamp(.75, .97);
  }

  static void _explain(
    BuildContext context,
    sc.CardioLoad l,
  ) => showTempoSheet<void>(
    context,
    builder: (ctx) {
      final c = ctx.c, s = ctx.s;
      Widget box(String o, String v, String sub) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface3,
            borderRadius: BorderRadius.circular(TempoRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(o),
              const SizedBox(height: 4),
              Text(v, style: TempoType.scoreS.c(c.text1)),
              const SizedBox(height: 4),
              Text(sub, style: TempoType.caption.c(c.text2)),
            ],
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What is cardio load?', style: TempoType.titleL.c(c.text1)),
          const SizedBox(height: 16),
          Text(
            'Every minute your heart works above rest adds load, and harder minutes count for more. Tempo adds this up from your band’s heart rate each day.',
            style: TempoType.body.c(c.text2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              box(
                'Last 7 days',
                '${l.acute.round()}/day',
                'How tired you might be',
              ),
              const SizedBox(width: 10),
              box(
                'Last 28 days',
                '${l.chronic.round()}/day',
                'What you’re used to',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text:
                      'When the week runs a little above your normal, you’re ',
                ),
                TextSpan(
                  text: 'building',
                  style: TextStyle(
                    color: s.loadBuilding,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(text: '. Far above it, you’re '),
                TextSpan(
                  text: 'overreaching',
                  style: TextStyle(
                    color: s.loadOverreaching,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(
                  text: ' and recovery usually drops. Well below, fitness slowly fades.',
                ),
              ],
            ),
            style: TempoType.body.c(c.text2),
          ),
          const SizedBox(height: 16),
          Text(
            'Estimated from heart rate (TRIMP). It doesn’t see weight lifted or terrain.',
            style: TempoType.caption.c(c.text3),
          ),
          const SizedBox(height: 16),
          TempoButton('Got it', expand: true, onTap: () => Navigator.pop(ctx)),
        ],
      );
    },
  );
}
