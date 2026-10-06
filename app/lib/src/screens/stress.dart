import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/stages.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

class _StressData {
  _StressData(this.day, this.split, this.sleeps, this.pairs, this.last);
  final DateTime day;

  /// The day's readings, awake and asleep kept apart.
  final sc.StressDay split;

  /// Every sleep (night or nap) touching the day.
  final List<sc.SleepSession> sleeps;

  /// (overnight stress, next-morning recovery) for the last 60 nights.
  final List<(double, double)> pairs;
  final (double, double)? last;
}

final _stressProvider = FutureProvider.family<_StressData, DateTime>((
  ref,
  day,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final readings = [
    for (final x in await db.stressBetween(
      day,
      day.add(const Duration(days: 1)),
    ))
      sc.StressReading(st.fromTs(x.ts), x.value),
  ];
  // Sleeps as scoring finds them, naps included (≥ 20 min asleep).
  final mins = decodeMinutes(
    await db.minutesBetween(
      day.subtract(const Duration(hours: 12)),
      day.add(const Duration(hours: 36)),
    ),
  ).minutes;
  final sleeps = sc.detectSessions(
    mins,
    sc.SleepParams(minSessionMinutes: const sc.SleepParams().minNapMinutes),
  );
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
    sc.splitStress(readings, sleeps),
    sleeps,
    pairs,
    last,
  );
});

/// Zoom on the day: all of it, or one 6-hour quarter.
const _windows = [(0, 24), (0, 6), (6, 12), (12, 18), (18, 24)];
const _windowLabels = ['Day', '12–6a', '6–12', '12–6p', '6–12p'];

class StressScreen extends ConsumerStatefulWidget {
  const StressScreen({super.key, this.day});

  /// Day to open on; today when null.
  final DateTime? day;

  @override
  ConsumerState<StressScreen> createState() => _StressScreenState();
}

class _StressScreenState extends ConsumerState<StressScreen> {
  late DateTime _day = dayOf(widget.day ?? DateTime.now());
  var _window = _windows.first;

  /// Reading picked by tapping or dragging on the chart.
  (sc.StressReading, bool)? _picked;

  void _shift(int days) => setState(() {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _picked = null;
  });

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(_stressProvider(_day)).value;
    if (d == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final split = d.split;
    final avg = split.awakeAvg;
    final isToday = !_day.isBefore(dayOf(DateTime.now()));
    final h = split.busiestHour;
    final busiest = h == null
        ? ''
        : ' The busiest stretch was around ${clock12(h * 60).replaceAll(':00', '')}.';
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
    final picked = _picked;

    return TempoPage(
      children: [
        DetailHeader(
          title: 'Stress index',
          subtitle: dayShort(_day),
          trailing: const TempoBadge('≈ proxy'),
        ),
        Row(
          children: [
            TempoIconButton(
              TempoIcons.back,
              label: 'Previous day',
              onTap: () => _shift(-1),
            ),
            Expanded(
              child: Text(
                isToday ? 'Today' : dayShort(_day),
                textAlign: TextAlign.center,
                style: TempoType.label.c(c.text1),
              ),
            ),
            TempoIconButton(
              TempoIcons.chevron,
              label: 'Next day',
              onTap: isToday ? null : () => _shift(1),
            ),
          ],
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
                    text: '  awake avg',
                    style: TempoType.titleM.c(c.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              avg == null
                  ? (isToday
                        ? 'No awake stress readings today yet. The band measures about every 5 minutes while you\'re still.'
                        : 'No awake stress readings this day.')
                  : '${switch (_level(avg.round())) {
                      'calm' => 'A calm day overall.',
                      'medium' => 'A medium day overall.',
                      _ => 'A high-stress day.',
                    }}$busiest',
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
              TempoSegmented<(int, int)>(
                values: _windows,
                labels: _windowLabels,
                selected: _window,
                height: 32,
                onChanged: (w) => setState(() {
                  _window = w;
                  _picked = null;
                }),
              ),
              const SizedBox(height: 12),
              Text(
                picked == null
                    ? 'Tap or drag on the chart to read a value.'
                    : '${clockOf(picked.$1.ts)} · ${picked.$1.value}'
                          '${picked.$2 ? ' asleep (sleep scale)' : ' · ${_level(picked.$1.value)}'}',
                style: TempoType.bodyS
                    .c(picked == null ? c.text3 : c.text1)
                    .tnum,
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => _pick(e.localPosition.dx, box.maxWidth, d),
                  onHorizontalDragUpdate: (e) =>
                      _pick(e.localPosition.dx, box.maxWidth, d),
                  child: _StressChart(
                    data: d,
                    window: _window,
                    picked: picked?.$1,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    clock12(_window.$1 * 60),
                    style: TempoType.caption.c(c.text3),
                  ),
                  Text(
                    clock12(((_window.$1 + _window.$2) ~/ 2) * 60),
                    style: TempoType.caption.c(c.text3),
                  ),
                  Text(
                    clock12((_window.$2 % 24) * 60),
                    style: TempoType.caption.c(c.text3),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                children: [
                  Legend(c.text1, 'Awake', height: 3),
                  Legend(s.sleepChannel, 'Asleep (sleep scale)', height: 3),
                ],
              ),
              if (split.asleep.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Asleep avg ${split.asleepAvg!.round()}. While you sleep the band stores a lower sleep-stress value, so those readings are left out of the awake average and levels.',
                  style: TempoType.caption.c(c.text2),
                ),
              ],
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
                  (split.calmMinutes, c.text3.withValues(alpha: .35)),
                  (split.mediumMinutes, c.text3.withValues(alpha: .7)),
                  (split.highMinutes, c.text1),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (k, n) in [
                    ('Calm', split.calmMinutes),
                    ('Medium', split.mediumMinutes),
                    ('High', split.highMinutes),
                  ])
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$k '),
                            TextSpan(
                              text: hmShort(n / 60),
                              style: TextStyle(color: c.text2),
                            ),
                          ],
                        ),
                        style: TempoType.bodyS.c(c.text1).tnum,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Measured time: each reading stands for the band\'s 5-minute step.',
                style: TempoType.caption.c(c.text3),
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

  static String _level(int v) => v < sc.stressMedium
      ? 'calm'
      : v < sc.stressHigh
      ? 'medium'
      : 'high';

  /// Picks the reading nearest to [dx] (in a chart [width] px wide).
  void _pick(double dx, double width, _StressData d) {
    final (a, b) = _window;
    final at = a * 60 + (dx / width).clamp(0, 1) * (b - a) * 60;
    (sc.StressReading, bool)? best;
    var gap = double.infinity;
    for (final (list, asleep) in [
      (d.split.awake, false),
      (d.split.asleep, true),
    ]) {
      for (final r in list) {
        final m = (r.ts.hour * 60 + r.ts.minute).toDouble();
        if (m < a * 60 || m > b * 60) continue;
        final g = (m - at).abs();
        if (g < gap) {
          gap = g;
          best = (r, asleep);
        }
      }
    }
    // Nothing within 20 minutes: leave the readout as it was.
    if (best == null || gap > 20) return;
    setState(() => _picked = best);
  }
}

/// The day's readings in [window] (hours): awake as a line, asleep as a
/// separate line on the sleep colour, sleeps shaded, breaks over
/// [sc.stressGapMinutes].
class _StressChart extends StatelessWidget {
  const _StressChart({
    required this.data,
    required this.window,
    required this.picked,
  });
  final _StressData data;
  final (int, int) window;
  final sc.StressReading? picked;

  @override
  Widget build(BuildContext context) => SvgChart(
    height: 200,
    width: 490,
    animate: false,
    semantics: 'Stress index through the day',
    draw: (ink, box) {
      final (a, b) = window;
      final from = data.day.add(Duration(hours: a)),
          to = data.day.add(Duration(hours: b));
      final span = to.difference(from).inMinutes;
      double y(num v) => 196 - v.clamp(0, 100) / 100 * 192;
      double x(DateTime t) => t.difference(from).inMinutes / span * 490;
      bool inside(DateTime t) => !t.isBefore(from) && !t.isAfter(to);
      ink.rect(
        Rect.fromLTRB(0, 0, 490, y(sc.stressHigh)),
        ink.c.surface3,
        opacity: .9,
      );
      ink.rect(
        Rect.fromLTRB(0, y(sc.stressHigh), 490, y(sc.stressMedium)),
        ink.c.surface3,
        opacity: .45,
      );
      for (final sl in data.sleeps) {
        if (!sl.end.isAfter(from) || !sl.start.isBefore(to)) continue;
        final l = x(sl.start.isBefore(from) ? from : sl.start);
        final r = x(sl.end.isAfter(to) ? to : sl.end);
        ink.rect(Rect.fromLTRB(l, 0, r, 200), ink.s.sleepChannel, opacity: .12);
      }
      void series(List<sc.StressReading> rs, Color col) {
        final pts = <Offset?>[];
        DateTime? prev;
        for (final r in rs) {
          if (!inside(r.ts)) continue;
          if (prev != null &&
              r.ts.difference(prev).inMinutes > sc.stressGapMinutes) {
            pts.add(null);
          }
          pts.add(Offset(x(r.ts), y(r.value)));
          prev = r.ts;
        }
        ink.gappedLine(pts, col, w: 2.5);
        // Dots when zoomed in, or for readings with no neighbour.
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          if (p == null) continue;
          final lone =
              (i == 0 || pts[i - 1] == null) &&
              (i == pts.length - 1 || pts[i + 1] == null);
          if (lone || b - a <= 6) ink.dot(p, 3, col);
        }
      }

      series(data.split.asleep, ink.s.sleepChannel);
      series(data.split.awake, ink.c.text1);
      final p = picked;
      if (p != null && inside(p.ts)) {
        final o = Offset(x(p.ts), y(p.value));
        ink.line(Offset(o.dx, 0), Offset(o.dx, 200), ink.c.lineStrong);
        ink.ring(o, 6, ink.c.text1, w: 2.5, inside: ink.c.surface1);
      }
    },
  );
}
