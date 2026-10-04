import 'dart:math' as math;

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
import 'nav.dart';
import 'shared.dart';

class LearnItem {
  const LearnItem(this.title, this.sub, this.short, this.icon, this.color);
  final String title, sub, short, icon;
  final Color color;
}

List<LearnItem> learnItems(BuildContext context, TodayData t) {
  final c = context.c, s = context.s;
  final r = t.recovery;
  final cs = contributors(context, t);
  final top = cs
      .where((x) => x.effect != 0)
      .fold<Contributor?>(
        null,
        (a, b) => a == null || b.effect.abs() > a.effect.abs() ? b : a,
      );
  return [
    LearnItem(
      'Recovery',
      r == null
          ? 'How Tempo learns your normal'
          : '${r.round()}% today${top == null ? '' : ' — ${top.name.toLowerCase().replaceAll(', overnight', '')} did most of the work'}',
      r == null ? 'Your normal' : 'Why ${r.round()}% today',
      TempoIcons.today,
      r == null ? c.text2 : s.recoveryFor(r),
    ),
    LearnItem(
      'Strain',
      'Why 18 → 19 is harder than 8 → 9',
      'Why it curves',
      TempoIcons.heartRate,
      s.strain[2],
    ),
    LearnItem(
      'Heart-rate zones',
      'Your five bands from a ${t.hrMax} max',
      'Your 5 zones',
      TempoIcons.zone,
      s.zone[3],
    ),
    LearnItem(
      'Cardio load',
      t.load.status == sc.LoadStatus.learning
          ? 'Acute vs chronic, after 7 days'
          : '${t.load.acute.round()} a day vs your normal ${t.load.chronic.round()}',
      'Acute vs chronic',
      TempoIcons.load,
      s.loadBuilding,
    ),
    LearnItem(
      'Sleep need & debt',
      'Why tonight’s target is ${hmShort(t.needTonight)}',
      'Tonight’s target',
      TempoIcons.sleep,
      s.sleepChannel,
    ),
    LearnItem(
      'Stress index',
      'Tempo’s stand-in for HRV',
      'HRV stand-in',
      TempoIcons.stress,
      c.text2,
    ),
  ];
}

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Learn'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How Tempo thinks', style: TempoType.pageTitle.c(c.text1)),
            const SizedBox(height: 6),
            Text(
              'Six cards, about 30 seconds each, all with your numbers.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        ),
        CardList(
          children: [
            for (final (i, it) in learnItems(context, t).indexed)
              Pressable(
                label: it.title,
                onTap: () => push(context, LearnCardsScreen(initial: i)),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: TempoIcon(it.icon, size: 22, color: it.color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.title, style: TempoType.label.c(c.text1)),
                            const SizedBox(height: 2),
                            Text(it.sub, style: TempoType.caption.c(c.text2)),
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
              ),
          ],
        ),
        Text(
          'Tempo is a wellness tool, not a medical device. Scores describe trends in your own data.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

final _nightStressProvider =
    FutureProvider.family<List<st.StressSample>, DateTime>((ref, day) async {
      ref.watch(dbTickProvider);
      final db = ref.watch(dbProvider);
      final s = await db.scoreFor(day);
      if (s?.sleepStart == null) return const [];
      return db.stressBetween(
        st.fromTs(s!.sleepStart!),
        st.fromTs(s.sleepEnd!),
      );
    });

/// Full-screen pager of six 350 × 600 cards, each with this morning's numbers.
class LearnCardsScreen extends ConsumerStatefulWidget {
  const LearnCardsScreen({super.key, this.initial = 0});
  final int initial;
  @override
  ConsumerState<LearnCardsScreen> createState() => _LearnCardsState();
}

class _LearnCardsState extends ConsumerState<LearnCardsScreen> {
  late final _pc = PageController(
    initialPage: widget.initial,
    viewportFraction: .9,
  );
  late int _page = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final stress = ref.watch(_nightStressProvider(t.day)).value ?? const [];
    final c = context.c;
    final cards = [
      _recovery(t),
      _strain(t),
      _zones(t),
      _load(t),
      _sleep(t),
      _stress(t, stress),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: DetailHeader(
                title: 'Learn',
                subtitle: '${_page + 1} of 6',
                leadingIcon: TempoIcons.close,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) {
                  TempoHaptics.selection();
                  setState(() => _page = i);
                },
                children: [
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: c.surface1,
                          borderRadius: BorderRadius.circular(TempoRadii.xl),
                        ),
                        child: card,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 6; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _page ? c.text1 : c.trackOff,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(
    String over,
    String title,
    String body,
    Widget middle,
    Widget foot, {
    Widget? badge,
  }) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Overline(over)),
            ?badge,
          ],
        ),
        const SizedBox(height: 16),
        Text(title, style: TempoType.titleL.c(c.text1)),
        const SizedBox(height: 16),
        Text(body, style: TempoType.bodyS.c(c.text2)),
        Expanded(child: Center(child: middle)),
        foot,
      ],
    );
  }

  Widget _foot(List<InlineSpan> spans) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.c.surface2,
      borderRadius: BorderRadius.circular(TempoRadii.md),
    ),
    child: Text.rich(
      TextSpan(children: spans),
      style: TempoType.bodyS.c(context.c.text2),
    ),
  );

  Widget _recovery(TodayData t) {
    final c = context.c;
    final cs = contributors(context, t);
    final r = t.recovery;
    final top = cs
        .where((x) => x.effect != 0)
        .fold<Contributor?>(
          null,
          (a, b) => a == null || b.effect.abs() > a.effect.abs() ? b : a,
        );
    return _frame(
      '1 / 6 · Recovery',
      'How ready you are, against your own normal',
      'Each morning Tempo compares last night with your last 30 nights. Lower resting HR, a calmer stress index and enough sleep push it up.',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final x in cs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      x.key == 'stress'
                          ? 'Stress ≈'
                          : x.key == 'rhr'
                          ? 'Resting HR'
                          : 'Sleep',
                      style: TempoType.caption.c(c.text2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Bar(fraction: x.width, left: x.left, color: x.color),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      x.value.split(' ').first,
                      textAlign: TextAlign.right,
                      style: TempoType.caption.c(c.text1).tnum,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      _foot(
        r == null
            ? [
                TextSpan(
                  text: 'Calibrating ${t.nights}/14. ',
                  style: TextStyle(color: c.text1),
                ),
                const TextSpan(
                  text: 'Your first score arrives the morning after night 14.',
                ),
              ]
            : [
                TextSpan(
                  text: '${r.round()}% ',
                  style: TempoType.scoreS.c(context.s.recoveryFor(r)),
                ),
                TextSpan(
                  text:
                      'this morning.${top == null ? '' : ' ${top.name.replaceAll(', overnight', '')} did most of the work.'}',
                ),
              ],
      ),
    );
  }

  Widget _strain(TodayData t) {
    final c = context.c;
    final hist =
        t.history.take(30).map((d) => d.strain).where((v) => v > 6).toList()
          ..sort();
    final typical = hist.isEmpty
        ? null
        : hist[(hist.length * .75).floor().clamp(0, hist.length - 1)];
    return _frame(
      '2 / 6 · Strain',
      'How hard your heart worked today, 0–21',
      'It climbs fast at first and slowly near the top: going from 18 to 19 takes far more work than going from 8 to 9.',
      SvgChart(
        width: 300,
        height: 160,
        semantics: 'Strain rises steeply then flattens',
        draw: (ink, box) {
          // Strain against TRIMP, the same curve the score uses.
          double x(double tr) => tr / 400 * 300;
          double y(double s) => 150 - s / 21 * 136;
          ink.polyline(
            [
              for (var tr = 0.0; tr <= 400; tr += 8)
                Offset(x(tr), y(sc.strainFromTrimp(tr))),
            ],
            ink.s.strain[2],
            w: 3,
          );
          ink.line(const Offset(0, 150), const Offset(300, 150), ink.c.line);
          double inv(double s) => -120 * math.log(1 - s / 21);
          final now = t.strain.clamp(0.0, 20.5);
          ink.dot(Offset(x(inv(now)), y(now)), 6, ink.c.text1);
          ink.text(
            'Now ${n1(t.strain)}',
            Offset(x(inv(now)) + 10, y(now) + 17),
            size: 12,
            color: ink.c.text2,
          );
          if (typical != null) {
            ink.ring(Offset(x(inv(typical)), y(typical)), 6, ink.c.text1);
            ink.text(
              'Typical training day ${n1(typical)}',
              Offset((x(inv(typical)) - 10).clamp(0, 140), y(typical) + 26),
              size: 12,
              color: ink.c.text2,
            );
          }
          ink.text('21', const Offset(0, 14), size: 11);
        },
      ),
      _foot([
        TextSpan(
          text: t.target.cap
              ? 'Today’s cap ${t.target.hi.round()} '
              : 'Today’s target ${t.target.lo.round()}–${t.target.hi.round()} ',
          style: TextStyle(color: c.text1),
        ),
        const TextSpan(
          text: 'is set from recovery: the greener the morning, the higher the range.',
        ),
      ]),
    );
  }

  Widget _zones(TodayData t) {
    final c = context.c, s = context.s;
    return _frame(
      '3 / 6 · Heart-rate zones',
      'Five effort bands, set from your max HR',
      'Your max is set to ${t.hrMax} bpm${t.profile.maxHrEstimated ? ' (estimated from age; change it in Profile if you know yours)' : ''}.',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var z = 1; z <= 5; z++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('Z$z', style: TempoType.label.c(c.text1)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 8.0 + z * 12,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.zone[z - 1],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sc.zoneNames[z - 1],
                      style: TempoType.bodyS.c(c.text1),
                    ),
                  ),
                  Text(
                    '${sc.zoneRange(z, t.hrMax).lo}–${sc.zoneRange(z, t.hrMax).hi} bpm',
                    style: TempoType.caption.c(c.text2).tnum,
                  ),
                ],
              ),
            ),
        ],
      ),
      Text(
        'Most of your week should live in Z2. Z4–Z5 are the spice.',
        style: TempoType.bodyS.c(c.text2),
      ),
    );
  }

  Widget _load(TodayData t) {
    final c = context.c;
    final l = t.load;
    final hi = math.max(1.0, math.max(l.acute, l.chronic));
    Widget col(String v, double h, String label, {bool fill = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(v, style: TempoType.scoreS.c(c.text1)),
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 144 * h,
          decoration: BoxDecoration(
            color: fill
                ? loadColor(
                    context,
                    l.status == sc.LoadStatus.learning
                        ? sc.LoadStatus.building
                        : l.status,
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
            border: fill ? null : Border.all(color: c.text3, width: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TempoType.caption.c(c.text2)),
      ],
    );
    return _frame(
      '4 / 6 · Cardio load',
      'This week, against what you’re used to',
      'Load adds up every minute of effort, weighted by intensity. Tempo compares your last 7 days with your last 28.',
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          col('${l.chronic.round()}', l.chronic / hi, '28-day /day'),
          const SizedBox(width: 40),
          col('${l.acute.round()}', l.acute / hi, '7-day /day', fill: true),
        ],
      ),
      _foot(
        l.status == sc.LoadStatus.learning
            ? [const TextSpan(text: 'Status appears after 7 days of data.')]
            : [
                TextSpan(
                  text: '${loadGlyph(l.status)} ${loadWord(l.status)}',
                  style: TextStyle(
                    color: loadColor(context, l.status),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text:
                      ' — ${l.percentVsNormal.abs()}% ${l.percentVsNormal >= 0 ? 'above' : 'below'} normal. Up to ~30% builds fitness; beyond that, recovery tends to slip.',
                ),
              ],
      ),
    );
  }

  Widget _sleep(TodayData t) {
    final c = context.c, s = context.s;
    final strainPart = t.strain * const sc.SleepParams().strainFactor;
    final debtPart = t.debt * const sc.SleepParams().debtFactor;
    Widget row(String a, String b, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              a,
              style: TempoType.bodyS.copyWith(
                color: bold ? c.text1 : c.text2,
                fontWeight: bold ? FontWeight.w500 : null,
              ),
            ),
          ),
          Text(
            b,
            style: TempoType.bodyS
                .copyWith(
                  color: c.text1,
                  fontWeight: bold ? FontWeight.w500 : null,
                )
                .tnum,
          ),
        ],
      ),
    );
    return _frame(
      '5 / 6 · Sleep need & debt',
      'Tonight’s target, explained',
      'Your baseline need, plus a little for today’s strain, plus a share of any debt from recent short nights. Naps pay debt down. The baseline starts at 7 h 30 m and, after 14 nights, learns from the nights you recover best after.',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentBar(
            height: 28,
            radius: 6,
            parts: [
              (t.baseNeed, s.sleepChannel),
              (strainPart, s.strain[1]),
              (debtPart, c.text2),
            ],
          ),
          const SizedBox(height: 10),
          row(
            t.baseNeedLearned ? 'Your baseline need' : 'Starting baseline',
            hmShort(t.baseNeed),
          ),
          row('Today’s strain ${n1(t.strain)}', '+${hmShort(strainPart)}'),
          row('Debt repayment', '+${hmShort(debtPart)}'),
          const Hair(),
          row('Tonight', hmShort(t.needTonight), bold: true),
        ],
      ),
      _foot([
        TextSpan(
          text:
              'Wake ${clockShort(DateTime(2000, 1, 1, t.wakeMinute ~/ 60, t.wakeMinute % 60))} → bed by ${clock12(t.bedtimeMinute)}. ',
          style: TextStyle(color: c.text1),
        ),
        const TextSpan(
          text: 'Baseline need is estimated from your first 14 nights.',
        ),
      ]),
    );
  }

  Widget _stress(TodayData t, List<st.StressSample> night) {
    final c = context.c;
    final b = t.stressBase;
    final last = t.score?.hrvProxy;
    return _frame(
      '6 / 6 · Stress index',
      'Tempo’s stand-in for HRV',
      'The band scores stress 0–100 from tiny changes between heartbeats. It isn’t raw HRV, so Tempo only compares it with your own history — never with other people.',
      night.length < 2
          ? const TempoEmpty(
              'Overnight stress appears after a night with the band on.',
              kind: EmptyKind.trend,
            )
          : SvgChart(
              width: 300,
              height: 120,
              semantics: 'Overnight stress against your normal',
              draw: (ink, box) {
                double y(num v) => 100 - v.clamp(0, 100) * .9;
                if (b != null) {
                  ink.rect(
                    Rect.fromLTRB(0, y(b.mean + b.sd), 300, y(b.mean - b.sd)),
                    ink.c.surface3,
                    opacity: .7,
                  );
                  ink.text(
                    'your normal',
                    Offset(4, y(b.mean + b.sd) - 6),
                    size: 11,
                  );
                }
                final t0 = night.first.ts, t1 = night.last.ts;
                ink.polyline(
                  [
                    for (final s in night)
                      if (s.value > 0)
                        Offset(
                          (s.ts - t0) / math.max(1, t1 - t0) * 300,
                          y(s.value),
                        ),
                  ],
                  ink.c.text1,
                  w: 2,
                );
                ink.text(
                  clockOf(st.fromTs(t0)),
                  const Offset(0, 116),
                  size: 11,
                );
                ink.text(
                  clockOf(st.fromTs(t1)),
                  const Offset(300, 116),
                  size: 11,
                  align: TextAlign.right,
                );
              },
            ),
      _foot(
        last == null
            ? [
                const TextSpan(
                  text: 'Lower overnight is better: your body was settled.',
                ),
              ]
            : [
                TextSpan(
                  text: 'Last night ${last.round()}',
                  style: TextStyle(color: c.text1),
                ),
                TextSpan(
                  text: b == null
                      ? '. Your normal appears after a few nights.'
                      : ' vs your normal ${b.mean.round()}. Lower overnight is better: your body was settled.',
                ),
              ],
      ),
      badge: const TempoBadge('≈ proxy'),
    );
  }
}
