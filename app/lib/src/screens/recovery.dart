import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../core/today.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'baselines.dart';
import 'calendar.dart';
import 'coach.dart';
import 'learn.dart';
import 'nav.dart';
import 'shared.dart';
import 'sleep.dart';
import 'stress.dart';

class RecoveryScreen extends ConsumerWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final r = t.recovery;
    final calib = t.calibrating;
    final cs = contributors(context, t);
    final color = calib || r == null ? c.text2 : s.recoveryFor(r);
    final state = calib
        ? 'Calibrating'
        : r == null
        ? 'No score'
        : '${recoveryGlyph(r)} ${recoveryWord(r)}';
    final series = [
      for (final d in [...t.history.take(29).toList().reversed, ?t.score]) d,
    ];
    final recs = [for (final d in series) d.calibrating ? null : d.recovery];
    final known = recs.whereType<double>().toList();
    final base = sc.Baseline.of(known);
    final complete = t.history
        .take(30)
        .where(
          (d) => d.rhr != null && d.hrvProxy != null && d.sleepPerf != null,
        )
        .length;
    final today = t.target;

    return TempoPage(
      gap: 22,
      children: [
        DetailHeader(
          title: 'Recovery',
          subtitle: dayShort(t.day),
          trailing: InfoButton(
            label: 'How recovery works',
            onTap: () => push(context, const LearnCardsScreen(initial: 0)),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: calib
                            ? '${t.nights}'
                            : r == null
                            ? '—'
                            : '${r.round()}',
                        style: TempoType.hero.c(c.text1),
                      ),
                      TextSpan(
                        text: calib
                            ? '/14 nights'
                            : r == null
                            ? ''
                            : '%',
                        style: TempoType.titleM.c(c.text3),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(state, style: TempoType.titleM.c(color)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            calib
                ? TickRow(
                    count: 14,
                    filled: t.nights,
                    color: c.text2,
                    calibration: true,
                  )
                : TickRow(
                    count: 20,
                    filled: ((r ?? 0) / 5).round(),
                    color: color,
                  ),
            const SizedBox(height: 14),
            Text(recoveryWhy(t, cs), style: TempoType.body.c(c.text2)),
          ],
        ),
        Section(
          title: 'What drove it · vs your 30-day baseline',
          child: CardList(
            children: [
              for (final x in cs)
                Pressable(
                  label: x.name,
                  onTap: () => push(context, switch (x.key) {
                    'stress' => const StressScreen(),
                    'rhr' => const BaselinesScreen(),
                    _ => const SleepScreen(),
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      x.name,
                                      style: TempoType.label.c(c.text1),
                                    ),
                                  ),
                                  if (x.proxy) ...[
                                    const SizedBox(width: 8),
                                    const TempoBadge('≈ proxy', small: true),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: x.value,
                                      style: TextStyle(color: c.text1),
                                    ),
                                    TextSpan(text: ' · normal ${x.base}'),
                                  ],
                                ),
                                style: TempoType.bodyS.c(c.text2).tnum,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${x.glyph} ${x.verdict}'.trim(),
                                style: TempoType.caption.copyWith(
                                  color: x.color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 112,
                          child: DeviationBar(
                            left: x.left,
                            width: x.width,
                            color: x.color,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      'Last 30 days',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  Pressable(
                    onTap: () => push(context, const CalendarScreen()),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          'Calendar',
                          style: TempoType.label.c(c.text2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (known.isEmpty)
                const TempoEmpty(
                  'Trend starts after night 14.',
                  kind: EmptyKind.trend,
                )
              else
                RecoveryTrend(
                  values: recs,
                  band: base == null
                      ? null
                      : (base.mean - base.sd, base.mean + base.sd),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    series.isEmpty ? '' : dm(DateTime.parse(series.first.date)),
                    style: TempoType.caption.c(c.text3),
                  ),
                  Text(
                    known.isEmpty
                        ? 'Trend starts after night 14'
                        : 'avg ${(known.reduce((a, b) => a + b) / known.length).round()}% · best ${known.reduce((a, b) => a > b ? a : b).round()}%',
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                  Text('Today', style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          onTap: () => push(context, const CoachScreen(standalone: true)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('What it means today'),
                    const SizedBox(height: 4),
                    Text(
                      today.cap
                          ? 'Rest day. Keep strain under ${today.hi.round()} and be in bed by ${clock12(t.bedtimeMinute)}.'
                          : today.general
                          ? 'General target ${today.lo.round()}–${today.hi.round()}. Moderate effort.'
                          : 'Strain target ${today.lo.round()}–${today.hi.round()}.${(r ?? 0) >= 67 ? ' A good day for intervals.' : ''}',
                      style: TempoType.body.c(c.text1),
                    ),
                  ],
                ),
              ),
              TempoIcon(
                TempoIcons.chevron,
                size: 18,
                color: c.text3,
                stroke: 2,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TempoRadii.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TempoIcon(TempoIcons.estimate, size: 16, color: c.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  calib
                      ? 'Baseline building: ${t.nights} of 14 nights. Scores start the morning after night 14.'
                      : 'Stress index stands in for HRV (≈ proxy). Baseline: ${t.history.take(30).length} nights, $complete with complete data. ${complete >= 24
                            ? 'High'
                            : complete >= 14
                            ? 'Moderate'
                            : 'Low'} confidence.',
                  style: TempoType.caption.c(c.text3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// TempoTrendChart for recovery: normal band, text-2 line, state dots.
class RecoveryTrend extends StatelessWidget {
  const RecoveryTrend({
    super.key,
    required this.values,
    this.band,
    this.hollowLast = false,
  });
  final List<double?> values;
  final (double, double)? band;
  final bool hollowLast;
  @override
  Widget build(BuildContext context) => SvgChart(
    height: 210,
    semantics: 'Recovery over ${values.length} days',
    draw: (ink, box) {
      double y(double v) => 200 - v * 1.85;
      final n = values.length;
      double x(int i) => n <= 1 ? 520 : i * (520 / (n - 1));
      if (band != null) {
        ink.rect(
          Rect.fromLTRB(
            0,
            y(band!.$2.clamp(0, 100)),
            520,
            y(band!.$1.clamp(0, 100)),
          ),
          ink.c.surface3,
          opacity: .7,
        );
        ink.text(
          'your normal',
          Offset(4, y(band!.$2.clamp(0, 100)) - 8),
          size: 15,
        );
      }
      ink.gappedLine(
        [
          for (final (i, v) in values.indexed)
            v == null ? null : Offset(x(i), y(v)),
        ],
        ink.c.text2,
        w: 2,
      );
      for (final (i, v) in values.indexed) {
        if (v == null) continue;
        final last = i == n - 1;
        if (last && hollowLast) {
          ink.ring(
            Offset(x(i), y(v)),
            7,
            ink.s.recoveryFor(v),
            w: 2.5,
            inside: ink.c.surface1,
          );
        } else {
          ink.dot(Offset(x(i), y(v)), last ? 7 : 4, ink.s.recoveryFor(v));
        }
      }
      ink.line(const Offset(0, 200), const Offset(520, 200), ink.c.line);
    },
  );
}

/// Shared provider: daily scores for the last [days] days, oldest first.
final scoresLastProvider = FutureProvider.family<List<st.DailyScore>, int>((
  ref,
  days,
) async {
  ref.watch(dbTickProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref
      .watch(dbProvider)
      .scoresBetween(today.subtract(Duration(days: days - 1)), today);
});

/// Convenience for screens that only need TodayData.
TodayData? todayOf(WidgetRef ref) => ref.watch(todayProvider).value;
