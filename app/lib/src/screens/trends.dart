import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'baselines.dart';
import 'calendar.dart';
import 'data_health.dart';
import 'day_timeline.dart';
import 'nav.dart';
import 'night_detail.dart';
import 'recovery.dart';
import 'sleep.dart';
import 'strain.dart';
import 'stress.dart';
import 'workouts.dart';

/// One value per day for each metric, oldest first; null = no data.
class TrendSeries {
  TrendSeries(this.days, this.metrics);
  final List<DateTime> days;
  final Map<String, List<double?>> metrics;
}

Future<TrendSeries> loadSeries(
  st.TempoDb db,
  DateTime from,
  DateTime to,
) async {
  final scores = {for (final s in await db.scoresBetween(from, to)) s.date: s};
  final steps = <String, double>{};
  final rows = await db
      .customSelect(
        "SELECT date(ts, 'unixepoch', 'localtime') AS d, SUM(steps) AS s FROM minute_samples WHERE ts >= ? AND ts < ? GROUP BY d",
        variables: [
          Variable.withInt(st.toTs(from)),
          Variable.withInt(st.toTs(to.add(const Duration(days: 1)))),
        ],
      )
      .get();
  for (final r in rows) {
    steps[r.read<String>('d')] = r.read<int>('s').toDouble();
  }
  final spo2 = await db.spo2Between(
    from.subtract(const Duration(hours: 12)),
    to.add(const Duration(days: 1)),
  );
  final days = [
    for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
      d,
  ];
  double? nightSpo2(st.DailyScore? s) {
    if (s?.sleepStart == null) return null;
    final v = [
      for (final x in spo2)
        if (x.ts >= s!.sleepStart! && x.ts < s.sleepEnd! && x.value > 0)
          x.value,
    ];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final m = <String, List<double?>>{
    for (final k in [
      'recovery',
      'strain',
      'sleep',
      'rhr',
      'stress',
      'spo2',
      'steps',
    ])
      k: [],
  };
  for (final d in days) {
    final s = scores[st.dateKey(d)];
    m['recovery']!.add(s == null || s.calibrating ? null : s.recovery);
    m['strain']!.add(s?.strain);
    m['sleep']!.add(s?.sleepPerf);
    m['rhr']!.add(s?.rhr);
    m['stress']!.add(s?.hrvProxy);
    m['spo2']!.add(nightSpo2(s));
    m['steps']!.add(steps[st.dateKey(d)]);
  }
  return TrendSeries(days, m);
}

final trendsProvider = FutureProvider.family<(TrendSeries, TrendSeries), int>((
  ref,
  n,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final today = dayOf(DateTime.now());
  final from = today.subtract(Duration(days: n - 1));
  final prevTo = from.subtract(const Duration(days: 1));
  return (
    await loadSeries(db, from, today),
    await loadSeries(db, prevTo.subtract(Duration(days: n - 1)), prevTo),
  );
});

enum _Kind { dot, bar, line }

class _Spec {
  const _Spec(
    this.key,
    this.name,
    this.unit,
    this.kind,
    this.lo,
    this.hi,
    this.fmt,
    this.page, {
    this.badge,
    this.pbLabel,
    this.lowIsBest = false,
    this.color,
  });
  final String key, name, unit;
  final _Kind kind;
  final double lo, hi;
  final String Function(double) fmt;
  final Widget Function() page;
  final String? badge, pbLabel;
  final bool lowIsBest;
  final Color Function(BuildContext, double)? color;
}

final _specs = <_Spec>[
  _Spec(
    'recovery',
    'Recovery',
    '% avg',
    _Kind.dot,
    0,
    100,
    (a) => '${a.round()}',
    () => const RecoveryScreen(),
    pbLabel: 'Best',
    color: (c, v) => c.s.recoveryFor(v),
  ),
  _Spec(
    'strain',
    'Strain',
    'avg / day',
    _Kind.bar,
    0,
    21,
    (a) => a.toStringAsFixed(1),
    () => const StrainScreen(),
    pbLabel: 'Peak',
    color: (c, v) => c.s.strainFor(v),
  ),
  _Spec(
    'sleep',
    'Sleep performance',
    '% avg',
    _Kind.bar,
    40,
    105,
    (a) => '${a.round()}',
    () => const SleepScreen(),
    color: (c, v) => c.s.sleepChannel,
  ),
  _Spec(
    'rhr',
    'Resting HR',
    'bpm avg',
    _Kind.line,
    40,
    75,
    (a) => '${a.round()}',
    () => const BaselinesScreen(),
    pbLabel: 'Lowest',
    lowIsBest: true,
  ),
  _Spec(
    'stress',
    'Stress index',
    'overnight avg',
    _Kind.line,
    0,
    70,
    (a) => '${a.round()}',
    () => const StressScreen(),
    badge: '≈ proxy',
    pbLabel: 'Calmest',
    lowIsBest: true,
  ),
  _Spec(
    'spo2',
    'SpO₂',
    '% overnight',
    _Kind.line,
    88,
    100,
    (a) => '${a.round()}',
    () => NightDetailScreen(morning: dayOf(DateTime.now())),
    badge: 'Est.',
  ),
  _Spec(
    'steps',
    'Steps',
    'avg / day',
    _Kind.bar,
    0,
    18000,
    (a) => grouped(a.round()),
    () => const DayTimelineScreen(),
    pbLabel: 'Best',
    color: (c, v) => c.c.text3,
  ),
];

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});
  @override
  ConsumerState<TrendsScreen> createState() => _TrendsState();
}

class _TrendsState extends ConsumerState<TrendsScreen> {
  int _range = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = ref.watch(trendsProvider(_range)).value;
    final debt = ref.watch(todayProvider).value?.debt;
    return TempoPage(
      gap: 18,
      bottom: 100,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text('Trends', style: TempoType.pageTitle.c(c.text1)),
              ),
              Transform.translate(
                offset: const Offset(10, 0),
                child: TempoIconButton(
                  TempoIcons.calendar,
                  label: 'Calendar',
                  stroke: 1.75,
                  onTap: () => push(context, const CalendarScreen()),
                ),
              ),
            ],
          ),
        ),
        TempoSegmented<int>(
          values: const [7, 30, 90],
          labels: const ['7 days', '30 days', '90 days'],
          selected: _range,
          onChanged: (v) => setState(() => _range = v),
        ),
        if (data == null)
          const SizedBox(height: 400)
        else
          for (final sp in _specs)
            _TrendCard(
              spec: sp,
              cur: data.$1.metrics[sp.key]!,
              prev: data.$2.metrics[sp.key]!,
              debt: sp.key == 'sleep' ? debt : null,
            ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 165 / 56,
          children: [
            for (final (t, icon, page) in [
              ('Workouts', TempoIcons.run, () => const WorkoutsScreen()),
              (
                'Day timeline',
                TempoIcons.timeline,
                () => const DayTimelineScreen(),
              ),
              (
                'Baselines',
                TempoIcons.baselines,
                () => const BaselinesScreen(),
              ),
              ('Calendar', TempoIcons.calendar, () => const CalendarScreen()),
              ('Data health', TempoIcons.band, () => const DataHealthScreen()),
            ])
              Pressable(
                label: t,
                onTap: () => push(context, page()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.surface1,
                    borderRadius: BorderRadius.circular(TempoRadii.md),
                  ),
                  child: Row(
                    children: [
                      TempoIcon(icon, size: 18, color: c.text1),
                      const SizedBox(width: 10),
                      Text(t, style: TempoType.label.c(c.text1)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.spec,
    required this.cur,
    required this.prev,
    this.debt,
  });
  final _Spec spec;
  final List<double?> cur, prev;
  final double? debt;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final known = cur.whereType<double>().toList();
    final prevKnown = prev.whereType<double>().toList();
    double avg(List<double> x) => x.reduce((a, b) => a + b) / x.length;
    final enough = known.length >= (cur.length <= 7 ? 3 : 7);
    String delta = '';
    if (enough && prevKnown.isNotEmpty) {
      final d = avg(known) - avg(prevKnown);
      final txt = spec.key == 'strain'
          ? d.abs().toStringAsFixed(1)
          : spec.key == 'steps'
          ? grouped(d.abs().round())
          : '${d.abs().round()}';
      delta = d.abs() < (spec.key == 'strain' ? .05 : 0.5)
          ? 'steady'
          : '${d > 0 ? '+' : '−'}$txt vs previous';
    }
    String pb = '';
    if (spec.key == 'sleep' && debt != null) {
      pb = 'Debt now ${hmShort(debt!)}';
    } else if (spec.pbLabel != null && known.isNotEmpty) {
      final best = spec.lowIsBest
          ? known.reduce((a, b) => a < b ? a : b)
          : known.reduce((a, b) => a > b ? a : b);
      pb =
          '${spec.pbLabel} ${spec.fmt(best)}${spec.key == 'recovery' ? '%' : ''}';
    }
    final band = known.length < 3
        ? null
        : (sc.quantile(known, .2)!, sc.quantile(known, .8)!);
    return TempoCard(
      onTap: () => push(context, spec.page()),
      label: spec.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(spec.name, style: TempoType.label.c(c.text1)),
              if (spec.badge != null) ...[
                const SizedBox(width: 8),
                TempoBadge(spec.badge!, small: true),
              ],
              const Spacer(),
              Text(pb, style: TempoType.caption.c(c.text3).tnum),
            ],
          ),
          const SizedBox(height: 10),
          if (!enough)
            TempoEmpty(
              spec.key == 'recovery'
                  ? 'Recovery trend starts after night 14.'
                  : 'Appears after 7 days.',
              kind: EmptyKind.trend,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(spec.fmt(avg(known)), style: TempoType.scoreS.c(c.text1)),
                const SizedBox(width: 8),
                Text(spec.unit, style: TempoType.caption.c(c.text3)),
                const Spacer(),
                Text(delta, style: TempoType.caption.c(c.text2).tnum),
              ],
            ),
            const SizedBox(height: 10),
            SvgChart(
              height: 110,
              stretchHeight: 76,
              semantics: '${spec.name} trend',
              draw: (ink, box) {
                final n = cur.length;
                double y(double v) =>
                    104 -
                    ((v - spec.lo) / (spec.hi - spec.lo)).clamp(0, 1) * 100;
                final step = 520 / n;
                if (band != null) {
                  ink.rect(
                    Rect.fromLTRB(0, y(band.$2), 520, y(band.$1)),
                    ink.c.surface3,
                    opacity: .75,
                  );
                }
                switch (spec.kind) {
                  case _Kind.bar:
                    for (final (i, v) in cur.indexed) {
                      if (v == null) continue;
                      ink.rect(
                        Rect.fromLTWH(
                          i * step + step * .18,
                          y(v),
                          step * .64,
                          104 - y(v),
                        ),
                        spec.color!(context, v),
                        radius: 2,
                      );
                    }
                  case _Kind.dot:
                    ink.gappedLine(
                      [
                        for (final (i, v) in cur.indexed)
                          v == null ? null : Offset(i * step + step / 2, y(v)),
                      ],
                      ink.c.text1,
                      w: 2.5,
                    );
                    for (final (i, v) in cur.indexed) {
                      if (v != null) {
                        ink.rect(
                          Rect.fromLTWH(
                            i * step + step / 2 - 4,
                            y(v) - 4,
                            8,
                            8,
                          ),
                          spec.color!(context, v),
                          radius: 2,
                        );
                      }
                    }
                  case _Kind.line:
                    ink.gappedLine(
                      [
                        for (final (i, v) in cur.indexed)
                          v == null ? null : Offset(i * step + step / 2, y(v)),
                      ],
                      ink.c.text1,
                      w: 2.5,
                    );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
