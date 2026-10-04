import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

class _StressData {
  _StressData(this.day, this.samples, this.sleepEnd, this.pairs, this.last);
  final DateTime day;
  final List<st.StressSample> samples;
  final DateTime? sleepEnd;

  /// (overnight stress, next-morning recovery) for the last 60 nights.
  final List<(double, double)> pairs;
  final (double, double)? last;
}

final _stressProvider = FutureProvider<_StressData>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final day = dayOf(DateTime.now());
  final samples = await db.stressBetween(day, day.add(const Duration(days: 1)));
  final s = await db.scoreFor(day);
  final hist = await db.scoresBetween(
    day.subtract(const Duration(days: 59)),
    day,
  );
  final pairs = [
    for (final h in hist)
      if (h.hrvProxy != null && h.recovery != null && !h.calibrating)
        (h.hrvProxy!, h.recovery!),
  ];
  final last = s?.hrvProxy != null && s?.recovery != null && !(s!.calibrating)
      ? (s.hrvProxy!, s.recovery!)
      : null;
  return _StressData(
    day,
    samples,
    s?.sleepEnd == null ? null : st.fromTs(s!.sleepEnd!),
    pairs,
    last,
  );
});

class StressScreen extends ConsumerWidget {
  const StressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(_stressProvider).value;
    if (d == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final vals = [
      for (final x in d.samples)
        if (x.value > 0) x,
    ];
    final avg = vals.isEmpty
        ? null
        : vals.map((e) => e.value).reduce((a, b) => a + b) / vals.length;
    final awake = vals
        .where(
          (x) => d.sleepEnd == null || !st.fromTs(x.ts).isBefore(d.sleepEnd!),
        )
        .toList();
    final calm = awake.where((x) => x.value < 40).length,
        med = awake.where((x) => x.value >= 40 && x.value < 60).length,
        high = awake.where((x) => x.value >= 60).length;
    // Busiest hour while awake.
    String busiest = '';
    if (awake.isNotEmpty) {
      final byHour = <int, List<int>>{};
      for (final x in awake) {
        byHour.putIfAbsent(st.fromTs(x.ts).hour, () => []).add(x.value);
      }
      final top = byHour.entries.reduce(
        (a, b) =>
            a.value.reduce((p, q) => p + q) / a.value.length >=
                b.value.reduce((p, q) => p + q) / b.value.length
            ? a
            : b,
      );
      final h = top.key;
      busiest =
          ' The busiest stretch was around ${clock12(h * 60).replaceAll(':00', '')}.';
    }
    final calmCut = sc.quantile(d.pairs.map((p) => p.$1), .33),
        stressCut = sc.quantile(d.pairs.map((p) => p.$1), .67);
    double? avgRec(bool Function(double) f) {
      final x = [
        for (final p in d.pairs)
          if (f(p.$1)) p.$2,
      ];
      return x.length < 3 ? null : x.reduce((a, b) => a + b) / x.length;
    }

    final calmRec = calmCut == null ? null : avgRec((v) => v < calmCut),
        hiRec = stressCut == null ? null : avgRec((v) => v > stressCut);

    return TempoPage(
      children: [
        DetailHeader(
          title: 'Stress index',
          subtitle: dayShort(d.day),
          trailing: const TempoBadge('≈ proxy'),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: avg == null ? '—' : '${avg.round()}',
                    style: TempoType.hero.c(c.text1),
                  ),
                  TextSpan(
                    text: '  day avg',
                    style: TempoType.titleM.c(c.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              avg == null
                  ? 'No stress readings today yet. The band measures every few minutes while worn.'
                  : '${avg < 40
                        ? 'A calm day overall.'
                        : avg < 60
                        ? 'A medium day overall.'
                        : 'A high-stress day.'}$busiest',
              style: TempoType.body.c(c.text2),
            ),
          ],
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Through the day', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 10),
              SvgChart(
                height: 200,
                semantics: 'Stress index through the day',
                draw: (ink, box) {
                  double y(num v) => 196 - v.clamp(0, 100) / 100 * 192;
                  double x(int ts) {
                    final t = st.fromTs(ts);
                    return (t.hour * 60 + t.minute) / 1440 * 490;
                  }

                  ink.rect(
                    Rect.fromLTRB(0, 0, 490, y(60)),
                    ink.c.surface3,
                    opacity: .9,
                  );
                  ink.rect(
                    Rect.fromLTRB(0, y(60), 490, y(40)),
                    ink.c.surface3,
                    opacity: .45,
                  );
                  ink.text(
                    'High',
                    const Offset(520, 20),
                    align: TextAlign.right,
                  );
                  ink.text(
                    'Med',
                    Offset(520, (y(40) + y(60)) / 2 + 5),
                    align: TextAlign.right,
                  );
                  ink.text(
                    'Calm',
                    const Offset(520, 190),
                    align: TextAlign.right,
                  );
                  if (d.sleepEnd != null) {
                    final se = d.sleepEnd!;
                    ink.rect(
                      Rect.fromLTWH(
                        0,
                        0,
                        (se.hour * 60 + se.minute) / 1440 * 490,
                        200,
                      ),
                      ink.s.sleepChannel,
                      opacity: .08,
                    );
                  }
                  final pts = <Offset?>[];
                  int? prev;
                  for (final v in vals) {
                    if (prev != null && v.ts - prev > 1800) pts.add(null);
                    pts.add(Offset(x(v.ts), y(v.value)));
                    prev = v.ts;
                  }
                  ink.gappedLine(pts, ink.c.text1, w: 2.5);
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('12 am · asleep', style: TempoType.caption.c(c.text3)),
                  Text('12 pm', style: TempoType.caption.c(c.text3)),
                  Text('now', style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Awake time, by level', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 10),
              SegmentBar(
                height: 16,
                parts: [
                  (calm, c.text3.withValues(alpha: .35)),
                  (med, c.text3.withValues(alpha: .7)),
                  (high, c.text1),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (k, n) in [
                    ('Calm', calm),
                    ('Medium', med),
                    ('High', high),
                  ])
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$k '),
                            TextSpan(
                              text: _dur(n, awake),
                              style: TextStyle(color: c.text2),
                            ),
                          ],
                        ),
                        style: TempoType.bodyS.c(c.text1).tnum,
                      ),
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
              Text(
                'Sleep-time stress and your recovery',
                style: TempoType.label.c(c.text1),
              ),
              const SizedBox(height: 4),
              Text(
                'Last 60 nights. Calmer nights are usually followed by greener mornings.',
                style: TempoType.bodyS.c(c.text2),
              ),
              const SizedBox(height: 12),
              if (d.pairs.length < 7)
                const TempoEmpty(
                  'This chart fills in after a week of scored mornings.',
                  kind: EmptyKind.trend,
                )
              else
                SvgChart(
                  height: 230,
                  semantics: 'Overnight stress against next-morning recovery',
                  draw: (ink, box) {
                    final lo =
                            d.pairs
                                .map((p) => p.$1)
                                .reduce((a, b) => a < b ? a : b) -
                            2,
                        hi =
                            d.pairs
                                .map((p) => p.$1)
                                .reduce((a, b) => a > b ? a : b) +
                            2;
                    double px(double v) => 40 + (v - lo) / (hi - lo) * 480;
                    double py(double r) => 200 - r * 2;
                    ink.line(
                      const Offset(40, 200),
                      const Offset(520, 200),
                      ink.c.line,
                    );
                    ink.line(
                      const Offset(40, 0),
                      const Offset(40, 200),
                      ink.c.line,
                    );
                    for (final p in d.pairs) {
                      ink.dot(
                        Offset(px(p.$1), py(p.$2)),
                        6,
                        ink.s.recoveryFor(p.$2),
                        opacity: .9,
                      );
                    }
                    if (d.last != null) {
                      ink.ring(
                        Offset(px(d.last!.$1), py(d.last!.$2)),
                        11,
                        ink.c.text1,
                        w: 2.5,
                      );
                    }
                    ink.text('${lo.round()} calm', const Offset(40, 222));
                    ink.text(
                      '${hi.round()} stressed',
                      const Offset(520, 222),
                      align: TextAlign.right,
                    );
                    ink.text(
                      '100',
                      const Offset(34, 14),
                      align: TextAlign.right,
                    );
                    ink.text(
                      '0',
                      const Offset(34, 200),
                      align: TextAlign.right,
                    );
                  },
                ),
              if (calmRec != null && hiRec != null) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Nights under ${calmCut!.round()}: recovery averages ',
                      ),
                      TextSpan(
                        text: '${calmRec.round()}%',
                        style: TextStyle(color: s.recoveryFor(calmRec)),
                      ),
                      TextSpan(text: '. Over ${stressCut!.round()}: '),
                      TextSpan(
                        text: '${hiRec.round()}%',
                        style: TextStyle(color: s.recoveryFor(hiRec)),
                      ),
                      const TextSpan(text: '. Ringed = last night.'),
                    ],
                  ),
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ],
          ),
        ),
        Text(
          'The band computes this index from beat-to-beat heart-rate variation. Tempo treats it as a stand-in for HRV and only compares it with your own history.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  /// Readings are spread through the awake time; scale counts to duration.
  static String _dur(int n, List<st.StressSample> awake) {
    if (awake.isEmpty) return '0m';
    final span = (awake.last.ts - awake.first.ts) / 3600;
    return hmShort(span * n / awake.length);
  }
}
