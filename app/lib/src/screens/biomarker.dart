import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/longevity_service.dart';
import '../core/score_service.dart' show parseDateKey;
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'longevity.dart';
import 'nav.dart';

/// Tempo Age v2: the groups card, and one page per biomarker.

String groupName(sc.AgeGroup g) => switch (g) {
  sc.AgeGroup.sleep => 'Sleep',
  sc.AgeGroup.activity => 'Activity',
  sc.AgeGroup.fitness => 'Fitness',
  sc.AgeGroup.lifestyle => 'Lifestyle',
  sc.AgeGroup.body => 'Body',
  sc.AgeGroup.blood => 'Blood',
};

/// The span a biomarker's bar covers, in its own units.
(double, double) leverScale(sc.Lever l, {required int age}) => switch (l) {
  sc.Lever.fitness => (20, 65),
  sc.Lever.restingHr => (40, 95),
  sc.Lever.steps => (0, 16000),
  sc.Lever.activeMinutes => (0, 450),
  sc.Lever.strength => (0, 4),
  sc.Lever.sleepDuration => (5, 10),
  sc.Lever.sleepRegularity => (0, 120),
  sc.Lever.breathing => (50, 100),
  sc.Lever.stress => (0, 100),
  sc.Lever.smoking => (0, 2),
  sc.Lever.alcohol => (0, 40),
  sc.Lever.bloodPressure => (90, 180),
  sc.Lever.waist => (60, 130),
  sc.Lever.blood => (age - 15.0, age + 15.0),
};

double _yearsAt(sc.Lever l, double v, LongevityData d) => sc
    .yearsFromHazard(sc.hazard(l, v, age: d.profile.age, male: d.profile.male))
    .clamp(-sc.leverCap(l), sc.leverCap(l))
    .toDouble();

/// Years with a sign and unit, "−1.2 yrs".
String yearsText(double y) {
  final a = y.abs();
  final s = a < .05 ? '0' : a.toStringAsFixed(1);
  return y <= -.05
      ? '−$s yrs'
      : y >= .05
      ? '+$s yrs'
      : '0 yrs';
}

Color yearsTone(BuildContext context, double y) => y <= -.5
    ? context.s.recHigh
    : y >= .5
    ? context.s.recLow
    : context.c.text2;

/// Each group with its years; tapping a group shows its biomarkers.
class AgeGroupsCard extends StatefulWidget {
  const AgeGroupsCard(this.d, {super.key});
  final LongevityData d;

  @override
  State<AgeGroupsCard> createState() => _AgeGroupsCardState();
}

class _AgeGroupsCardState extends State<AgeGroupsCard> {
  final _open = <sc.AgeGroup>{};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final groups = groupsOf(widget.d.contributors);
    return CardList(
      children: [
        for (final g in groups) ...[
          Pressable(
            label: '${groupName(g.group)}, ${yearsText(g.years)}',
            onTap: () => setState(
              () => _open.contains(g.group)
                  ? _open.remove(g.group)
                  : _open.add(g.group),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupName(g.group),
                          style: TempoType.body.c(c.text1),
                        ),
                        Text(
                          _groupWords(g.years),
                          style: TempoType.caption.c(
                            yearsTone(context, g.years),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    yearsText(g.years),
                    style: TempoType.label.c(yearsTone(context, g.years)).tnum,
                  ),
                  const SizedBox(width: 6),
                  Transform.rotate(
                    angle: _open.contains(g.group) ? -pi / 2 : pi / 2,
                    child: TempoIcon(
                      TempoIcons.chevron,
                      size: 16,
                      color: c.text3,
                      stroke: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open.contains(g.group))
            for (final l in g.levers) _BiomarkerRow(l, widget.d),
        ],
      ],
    );
  }

  static String _groupWords(double y) => y.abs() < .05
      ? 'On par with your age'
      : '${y.abs().toStringAsFixed(1)} years ${y < 0 ? 'younger' : 'older'}';
}

/// Groups from stored contributors (the scoring order).
List<sc.GroupYears> groupsOf(List<sc.Contributor> cs) => sc.TempoAge(
  realAge: 0,
  age: 0,
  contributors: cs,
  calibrating: false,
).groups;

class _BiomarkerRow extends StatelessWidget {
  const _BiomarkerRow(this.x, this.d);
  final sc.Contributor x;
  final LongevityData d;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      label:
          '${leverName(x.lever)}, ${leverValue(x.lever, x.value)}, ${yearsText(x.years)}',
      onTap: () => push(context, BiomarkerScreen(x.lever)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${leverName(x.lever)}${x.weak ? ' ≈' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TempoType.label.c(c.text1),
                  ),
                ),
                Text(
                  leverValue(x.lever, x.value),
                  style: TempoType.caption.c(c.text2).tnum,
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    yearsText(x.years),
                    textAlign: TextAlign.end,
                    style: TempoType.label.c(yearsTone(context, x.years)).tnum,
                  ),
                ),
              ],
            ),
            if (x.lever != sc.Lever.smoking) ...[
              const SizedBox(height: 8),
              RangeBar(x.lever, x.value, d),
            ],
          ],
        ),
      ),
    );
  }
}

/// The biomarker's span with its "younger" stretch tinted and your value
/// marked.
class RangeBar extends StatelessWidget {
  const RangeBar(this.lever, this.value, this.d, {super.key, this.height = 30});
  final sc.Lever lever;
  final double value;
  final LongevityData d;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = leverScale(lever, age: d.profile.age);
    final good = context.s.recHigh, bad = context.s.recLow;
    return SvgChart(
      height: height,
      semantics:
          '${leverName(lever)} on a scale from ${leverValue(lever, lo)} to ${leverValue(lever, hi)}',
      draw: (ink, box) {
        const n = 60, y = 8.0;
        double x(double v) => 10 + (v - lo) / (hi - lo) * 500;
        for (var i = 0; i < n; i++) {
          final v = lo + (hi - lo) * (i + .5) / n;
          final yrs = _yearsAt(lever, v, d);
          ink.rect(
            Rect.fromLTWH(10 + 500 * i / n, y - 3, 500 / n - 1, 6),
            yrs <= -.05
                ? good
                : yrs >= .05
                ? bad
                : ink.c.surface3,
            opacity: yrs.abs() < .05 ? 1 : .35 + .5 * min(1, yrs.abs() / 3),
          );
        }
        final px = x(value.clamp(lo, hi));
        ink.dot(Offset(px, y), 7, ink.c.text1);
        ink.dot(Offset(px, y), 3, ink.c.surface1);
        ink.text(leverValue(lever, lo), Offset(10, height + 2), size: 12);
        ink.text(
          leverValue(lever, hi),
          Offset(510, height + 2),
          align: TextAlign.right,
          size: 12,
        );
      },
    );
  }
}

/// One biomarker: value, years, its bar, reference and history.
class BiomarkerScreen extends ConsumerStatefulWidget {
  const BiomarkerScreen(this.lever, {super.key});
  final sc.Lever lever;

  @override
  ConsumerState<BiomarkerScreen> createState() => _BiomarkerState();
}

class _BiomarkerState extends ConsumerState<BiomarkerScreen> {
  int _months = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = ref.watch(longevityProvider).value;
    final l = widget.lever;
    final x = d?.contributors.where((c) => c.lever == l).firstOrNull;
    return TempoPage(
      gap: 18,
      children: [
        DetailHeader(title: leverName(l)),
        if (d == null || x == null)
          const TempoEmpty('No data for this measure yet.')
        else ...[
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Overline(groupName(x.group)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        leverValue(l, x.value),
                        style: TempoType.titleL.c(c.text1).tnum,
                      ),
                    ),
                    Text(
                      yearsText(x.years),
                      style: TempoType.titleM
                          .c(yearsTone(context, x.years))
                          .tnum,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l == sc.Lever.blood
                      ? 'PhenoAge from your latest blood test.'
                      : 'Average over the 30 days before ${_md(parseDateKey(d.latest!.date))}.',
                  style: TempoType.bodyS.c(c.text2),
                ),
                if (l != sc.Lever.smoking) ...[
                  const SizedBox(height: 14),
                  RangeBar(l, x.value, d, height: 34),
                ],
                const SizedBox(height: 14),
                Text(_reference(l, d), style: TempoType.bodyS.c(c.text2)),
                if (x.weight < .999) ...[
                  const SizedBox(height: 6),
                  Text(_weightNote(x), style: TempoType.caption.c(c.text3)),
                ],
              ],
            ),
          ),
          _History(l, d, _months, (m) => setState(() => _months = m)),
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('What moves it'),
                const SizedBox(height: 6),
                Text(leverHow(l), style: TempoType.body.c(c.text2)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _weightNote(sc.Contributor x) => switch (x.lever) {
    sc.Lever.restingHr => 'Counted lightly: your VO₂ max is estimated from it, so most of its effect is already there.',
    sc.Lever.blood => 'An older test counts for less: full weight for 6 months, none after 2 years.',
    _ =>
      'Shared with related measures in ${groupName(x.group).toLowerCase()}, so it counts for ${(x.weight * 100).round()} % on its own.',
  };

  String _reference(sc.Lever l, LongevityData d) {
    final a = d.profile.age, m = d.profile.male;
    final who = '${m ? 'men' : 'women'} around $a';
    final t = sc.leverTarget(l, age: a, male: m);
    return switch (l) {
      sc.Lever.fitness =>
        'Typical for $who: VO₂max ${sc.vo2Norm(a, m).round()}. Target ${t.round()} (top quarter).',
      sc.Lever.restingHr =>
        'Typical for $who: ${sc.rhrNorm(a, m).round()} bpm. Target ${t.round()} bpm.',
      sc.Lever.blood => 'PhenoAge equal to your age is typical. Under it means your blood reads younger.',
      sc.Lever.smoking => 'Never smoking is the reference.',
      _ => 'Target: ${leverValue(l, t)}.',
    };
  }
}

String _md(DateTime t) => '${t.day} ${_mo[t.month - 1]}';
const _mo = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _History extends StatelessWidget {
  const _History(this.lever, this.d, this.months, this.onMonths);
  final sc.Lever lever;
  final LongevityData d;
  final int months;
  final ValueChanged<int> onMonths;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - months, now.day);
    final pts = <(DateTime, double)>[
      for (final r in d.history)
        if (!parseDateKey(r.date).isBefore(from))
          for (final x in decodeContributors(r.contributors))
            if (x.lever == lever) (parseDateKey(r.date), x.value),
    ];
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('30-day average over time', style: TempoType.label.c(c.text1)),
          const SizedBox(height: 10),
          TempoSegmented<int>(
            values: const [3, 6, 12],
            labels: const ['3M', '6M', '1Y'],
            selected: months,
            onChanged: onMonths,
            height: 32,
          ),
          const SizedBox(height: 12),
          if (pts.length < 2)
            Text(
              'Two or more snapshots are needed for a line.',
              style: TempoType.bodyS.c(c.text2),
            )
          else
            SvgChart(
              height: 160,
              semantics: '${leverName(lever)} over the last $months months',
              draw: (ink, box) {
                final ys = pts.map((p) => p.$2);
                final mean = ys.reduce((a, b) => a + b) / pts.length;
                var lo = ys.reduce(min), hi = ys.reduce(max);
                if (hi - lo < 1e-6) {
                  lo -= 1;
                  hi += 1;
                }
                final t0 = pts.first.$1;
                final span = max(1, pts.last.$1.difference(t0).inDays);
                double x(DateTime t) =>
                    10 + t.difference(t0).inDays / span * 480;
                double y(double v) => 130 - (v - lo) / (hi - lo) * 115;
                ink.line(
                  Offset(0, y(mean)),
                  Offset(500, y(mean)),
                  ink.c.lineStrong,
                  dash: [4, 4],
                );
                ink.text(
                  'avg ${leverValue(lever, mean)}',
                  Offset(500, y(mean) - 6),
                  align: TextAlign.right,
                  size: 12,
                );
                final line = [for (final p in pts) Offset(x(p.$1), y(p.$2))];
                ink.polyline(line, ink.c.text1, w: 2.5);
                ink.dot(line.last, 4, ink.c.text1);
                ink.text(_md(t0), const Offset(10, 156), size: 12);
                ink.text(
                  _md(pts.last.$1),
                  const Offset(490, 156),
                  align: TextAlign.right,
                  size: 12,
                );
              },
            ),
        ],
      ),
    );
  }
}
