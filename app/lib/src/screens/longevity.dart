import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/longevity_service.dart';
import '../core/profile.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';
import 'trends.dart';

class LongevityData {
  LongevityData({
    required this.latest,
    required this.contributors,
    required this.history,
    required this.pace,
    required this.days,
    required this.focus,
    required this.progress,
    required this.manual,
    required this.profile,
  });
  final st.LongevitySnapshot? latest;
  final List<sc.Contributor> contributors;
  final List<st.LongevitySnapshot> history;
  final double? pace;
  final int days;
  final LongevityFocus? focus;
  final (double, double)? progress;
  final ManualHealth manual;
  final Profile profile;

  /// The newest settled snapshot at least a week before [latest].
  st.LongevitySnapshot? get weekAgo {
    final l = latest;
    if (l == null || l.calibrating) return null;
    final cut = DateTime.parse(l.date).subtract(const Duration(days: 7));
    return history
        .where((r) => !r.calibrating && !DateTime.parse(r.date).isAfter(cut))
        .lastOrNull;
  }

  /// What moved Tempo Age since [weekAgo], biggest first.
  List<(sc.Lever, double)> get changes {
    final w = weekAgo;
    return w == null
        ? const []
        : sc.contributorChanges(
            decodeContributors(w.contributors),
            contributors,
          );
  }

  /// The levers with the most to gain, biggest first.
  List<sc.Contributor> get levers => sc.TempoAge(
    realAge: latest?.realAge ?? 0,
    age: latest?.tempoAge ?? 0,
    contributors: contributors,
    calibrating: latest?.calibrating ?? true,
  ).levers;
}

final longevityProvider = FutureProvider<LongevityData>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final profile = await loadAppProfile(db) ?? const Profile();
  final today = DateTime.now();
  final history = await db.longevitySince(
    DateTime(today.year - 1, today.month, today.day),
  );
  final latest = history.isEmpty ? null : history.last;
  var focus = await loadFocus(db);
  if (focus != null && !focus.activeOn(today)) focus = null;
  return LongevityData(
    latest: latest,
    contributors: latest == null
        ? const []
        : decodeContributors(latest.contributors),
    history: history,
    pace: paceFrom(history),
    days: await daysOfData(db),
    focus: focus,
    progress: focus == null ? null : await focusProgress(db, focus, profile),
    manual: await loadManualHealth(db),
    profile: profile,
  );
});

/// Longevity tab: Tempo Age, what moves it, a focus plan, and Trends.
class LongevityScreen extends ConsumerStatefulWidget {
  const LongevityScreen({super.key, this.standalone = false});

  /// Pushed from Coach (back button, no tab padding).
  final bool standalone;
  @override
  ConsumerState<LongevityScreen> createState() => _LongevityScreenState();
}

class _LongevityScreenState extends ConsumerState<LongevityScreen> {
  @override
  void initState() {
    super.initState();
    // Fresh numbers on open (syncs also update it).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await updateLongevity(ref.read(dbProvider));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = ref.watch(longevityProvider).value;
    final info = Transform.translate(
      offset: const Offset(10, 0),
      child: InfoButton(
        label: 'How Tempo Age works',
        onTap: () => _howItWorks(context),
      ),
    );
    return TempoPage(
      gap: 18,
      bottom: widget.standalone ? 48 : 100,
      children: [
        if (widget.standalone)
          DetailHeader(title: 'Longevity', trailing: info)
        else
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Longevity',
                    style: TempoType.pageTitle.c(c.text1),
                  ),
                ),
                info,
              ],
            ),
          ),
        if (d == null)
          const SizedBox(height: 400)
        else ...[
          _Hero(d),
          if (d.weekAgo != null) _SinceLastWeek(d),
          if (longevityPoints(d.history).length >= 2) _TrendCard(d),
          if (d.focus != null) _FocusCard(d),
          if (d.levers.isNotEmpty)
            Section(
              title: 'Biggest levers',
              child: Column(
                children: [
                  for (final (i, l) in d.levers.take(3).indexed) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _LeverCard(l, d),
                  ],
                ],
              ),
            ),
          if (d.contributors.isNotEmpty)
            Section(
              title: 'What shapes it',
              child: _Contributors(d.contributors),
            ),
          Section(title: 'Health details', child: _ManualCard(d.manual)),
          CardList(
            children: [
              ListRow(
                'Trends',
                sub: 'Recovery, strain and sleep over 7–90 days',
                onTap: () => push(context, const TrendsScreen()),
              ),
            ],
          ),
          Text(
            'Tempo Age is a wellness estimate from published population '
            'studies, not a medical test or a diagnosis. Talk to a doctor '
            'about your health.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ],
    );
  }
}

// ---- presentation helpers ---------------------------------------------------

String leverName(sc.Lever l) => switch (l) {
  sc.Lever.fitness => 'Cardio fitness',
  sc.Lever.restingHr => 'Resting heart rate',
  sc.Lever.steps => 'Daily steps',
  sc.Lever.activeMinutes => 'Zone 2+ minutes',
  sc.Lever.strength => 'Strength training',
  sc.Lever.sleepDuration => 'Sleep duration',
  sc.Lever.sleepRegularity => 'Bedtime regularity',
  sc.Lever.breathing => 'Breathing at night',
  sc.Lever.stress => 'Stress',
  sc.Lever.smoking => 'Smoking',
  sc.Lever.alcohol => 'Alcohol',
  sc.Lever.bloodPressure => 'Blood pressure',
  sc.Lever.waist => 'Waist',
};

String leverValue(sc.Lever l, double v) => switch (l) {
  sc.Lever.fitness => 'VO₂max ${v.round()}',
  sc.Lever.restingHr => '${v.round()} bpm',
  sc.Lever.steps => '${_k(v)} a day',
  sc.Lever.activeMinutes => '${v.round()} min a week',
  sc.Lever.strength => '${_one(v)} a week',
  sc.Lever.sleepDuration => _hm(v),
  sc.Lever.sleepRegularity => '±${v.round()} min',
  sc.Lever.breathing => 'Score ${v.round()}',
  sc.Lever.stress => 'Index ${v.round()}',
  sc.Lever.smoking => switch (sc.Smoking.values[v.round()]) {
    sc.Smoking.never => 'Never',
    sc.Smoking.former => 'Former',
    sc.Smoking.current => 'Current',
  },
  sc.Lever.alcohol => '${v.round()} units a week',
  sc.Lever.bloodPressure => '${v.round()} systolic',
  sc.Lever.waist => '${v.round()} cm',
};

/// What to do, and what Tempo does for you, per lever.
String leverHow(sc.Lever l) => switch (l) {
  sc.Lever.fitness =>
    'Fitness follows Zone 2 work and intervals. Coach adds them to your week.',
  sc.Lever.steps =>
    'Walk more through the day: calls on foot, stairs, a walk after meals.',
  sc.Lever.activeMinutes =>
    'Coach swaps easy days for Zone 2 sessions where you can still talk.',
  sc.Lever.strength =>
    'Coach keeps two strength days a week, never back to back.',
  sc.Lever.sleepDuration =>
    'Protect a bedtime that leaves room for your sleep need. Tempo nudges you.',
  sc.Lever.sleepRegularity =>
    'Go to bed within the same 30 minutes, weekends too.',
  sc.Lever.breathing => 'Side sleeping, less alcohol late and a clear nose help. Persistent dips are worth a doctor’s look.',
  sc.Lever.smoking => 'Quitting is the biggest single gain there is.',
  sc.Lever.alcohol => 'Aim for 7 units a week or fewer, with dry days.',
  sc.Lever.bloodPressure =>
    'Less salt, more movement and good sleep lower it. Check it with a cuff.',
  sc.Lever.waist => 'Waist follows activity, sleep and food quality.',
  sc.Lever.restingHr || sc.Lever.stress => 'Follows fitness and sleep.',
};

String _k(double v) =>
    v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}';
String _one(double v) => v.toStringAsFixed(1).replaceAll('.0', '');
String _hm(double h) {
  final m = (h * 60).round();
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

String _years(double y) {
  final a = y.abs();
  final s = a < .05 ? '0' : a.toStringAsFixed(1);
  return y <= -.05
      ? '−$s yrs'
      : y >= .05
      ? '+$s yrs'
      : '0 yrs';
}

Color _tone(BuildContext context, double y) => y <= -.5
    ? context.s.recHigh
    : y >= .5
    ? context.s.recLow
    : context.c.text2;

// ---- hero -------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero(this.d);
  final LongevityData d;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = d.latest;
    if (l == null) {
      return const TempoEmpty(
        'Tempo Age appears after your first sync. It turns 30 days of heart rate, sleep and activity into an age.',
      );
    }
    final delta = l.tempoAge - l.realAge;
    final younger = delta <= -.05;
    final words = delta.abs() < .05
        ? 'Right on your calendar age'
        : '${delta.abs().toStringAsFixed(1)} years ${younger ? 'younger' : 'older'} than your calendar age';
    return TempoCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Tempo Age')),
              if (l.calibrating)
                TempoBadge('Calibrating · ${min(d.days, 30)} of 30 days')
              else if (d.pace != null)
                TempoBadge(
                  'Pace ${d.pace!.toStringAsFixed(2)}×',
                  color: d.pace! < .98
                      ? context.s.recHigh
                      : d.pace! > 1.02
                      ? context.s.recLow
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label:
                'Tempo Age ${l.tempoAge.toStringAsFixed(1)}. Calendar age ${l.realAge.round()}.',
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l.tempoAge.toStringAsFixed(1),
                    style: TempoType.hero.c(l.calibrating ? c.text2 : c.text1),
                  ),
                  TextSpan(
                    text: '  age ${l.realAge.round()}',
                    style: TempoType.titleM.c(c.text3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.calibrating
                ? 'An early estimate. It settles once Tempo has 30 days and at least four band measures.'
                : '$words.${d.pace == null ? '' : ' ${_paceWords(d.pace!)}'}',
            style: TempoType.body.c(c.text2),
          ),
          const SizedBox(height: 14),
          _AgeScale(real: l.realAge, tempo: l.tempoAge),
        ],
      ),
    );
  }

  static String _paceWords(double p) => p < .98
      ? 'You’re ageing ${((1 - p) * 100).round()}% slower than the calendar lately.'
      : p > 1.02
      ? 'You’re ageing ${((p - 1) * 100).round()}% faster than the calendar lately.'
      : 'You’re ageing at the calendar’s pace.';
}

/// A ±15-year scale with your calendar age in the middle.
class _AgeScale extends StatelessWidget {
  const _AgeScale({required this.real, required this.tempo});
  final double real, tempo;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context, tempo - real);
    return SvgChart(
      height: 64,
      semantics: 'Tempo Age against calendar age',
      draw: (ink, box) {
        double x(double off) => 260 + off.clamp(-15, 15) / 15 * 240;
        const y = 22.0;
        ink.line(
          const Offset(20, y),
          const Offset(500, y),
          ink.c.surface3,
          w: 6,
        );
        for (final t in [-10, -5, 5, 10]) {
          ink.line(
            Offset(x(t.toDouble()), y + 8),
            Offset(x(t.toDouble()), y + 12),
            ink.c.lineStrong,
          );
          ink.text(
            '${(real + t).round()}',
            Offset(x(t.toDouble()), 58),
            align: TextAlign.center,
            size: 13,
          );
        }
        ink.line(Offset(x(0), y - 12), Offset(x(0), y + 14), ink.c.text2, w: 2);
        ink.text(
          'Calendar',
          Offset(x(0), 58),
          align: TextAlign.center,
          size: 13,
          color: ink.c.text2,
        );
        final off = tempo - real;
        ink.line(Offset(x(0), y), Offset(x(off), y), tone, w: 6);
        ink.dot(Offset(x(off), y), 9, tone);
        ink.dot(Offset(x(off), y), 4, ink.c.surface1);
      },
    );
  }
}

// ---- since last week -------------------------------------------------------

class _SinceLastWeek extends StatelessWidget {
  const _SinceLastWeek(this.d);
  final LongevityData d;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = d.weekAgo!, l = d.latest!;
    final delta = l.tempoAge - w.tempoAge;
    final days = DateTime.parse(l.date)
        .difference(DateTime.parse(w.date))
        .inDays;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Overline(
                  days <= 8 ? 'Since last week' : 'Since $days days ago',
                ),
              ),
              Text(
                _years(delta),
                style: TempoType.label.c(_tone(context, delta)).tnum,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (d.changes.isEmpty)
            Text(
              'Nothing moved by more than a tenth of a year.',
              style: TempoType.bodyS.c(c.text2),
            )
          else
            for (final (lever, y) in d.changes.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        leverName(lever),
                        style: TempoType.bodyS.c(c.text1),
                      ),
                    ),
                    Text(
                      _years(y),
                      style: TempoType.label.c(_tone(context, y)).tnum,
                    ),
                  ],
                ),
              ),
          if (delta.abs() >= sc.tempoAgePerWeek * days / 7 - .01) ...[
            const SizedBox(height: 8),
            Text(
              'Tempo Age moves at most a year a week, so the rest of this change arrives over the next weeks.',
              style: TempoType.caption.c(c.text3),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- trend ------------------------------------------------------------------

class _TrendCard extends StatelessWidget {
  const _TrendCard(this.d);
  final LongevityData d;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pts = longevityPoints(d.history);
    final real = d.latest!.realAge;
    final ys = [...pts.map((p) => p.$2), real];
    final lo = ys.reduce(min) - 1, hi = ys.reduce(max) + 1;
    final t0 = pts.first.$1, t1 = pts.last.$1;
    final span = max(1, t1.difference(t0).inDays);
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tempo Age over time', style: TempoType.label.c(c.text1)),
          const SizedBox(height: 10),
          SvgChart(
            height: 180,
            semantics: 'Tempo Age over the last months',
            draw: (ink, box) {
              String md(DateTime t) => '${t.day} ${_months[t.month - 1]}';
              ink.text(md(t0), const Offset(10, 176), size: 13);
              ink.text(
                md(t1),
                const Offset(470, 176),
                align: TextAlign.right,
                size: 13,
              );
              double x(DateTime t) => 10 + t.difference(t0).inDays / span * 460;
              double y(double v) => 140 - (v - lo) / (hi - lo) * 130;
              ink.line(
                Offset(0, y(real)),
                Offset(480, y(real)),
                ink.c.lineStrong,
                dash: [4, 4],
              );
              ink.text(
                '${real.round()}',
                Offset(520, y(real) + 5),
                align: TextAlign.right,
                size: 13,
              );
              final line = [for (final p in pts) Offset(x(p.$1), y(p.$2))];
              ink.polyline(line, ink.c.text1, w: 2.5);
              for (final p in line) {
                ink.dot(p, 4, ink.c.text1);
              }
              ink.text(
                pts.last.$2.toStringAsFixed(1),
                Offset(line.last.dx, line.last.dy - 10),
                align: TextAlign.center,
                size: 13,
                color: ink.c.text1,
              );
            },
          ),
        ],
      ),
    );
  }
}

const _months = [
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

// ---- focus ------------------------------------------------------------------

class _FocusCard extends ConsumerWidget {
  const _FocusCard(this.d);
  final LongevityData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = d.focus!;
    final now = DateTime.now();
    final p = d.progress;
    final frac = p == null || p.$2 <= 0 ? null : (p.$1 / p.$2).clamp(0, 1);
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Your focus')),
              TempoBadge('Week ${f.weekOn(now)} of ${f.weeks}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(leverName(f.lever), style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(leverHow(f.lever), style: TempoType.bodyS.c(c.text2)),
          if (p != null && frac != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text('This week', style: TempoType.label.c(c.text2)),
                ),
                Text(
                  '${leverValue(f.lever, p.$1)} / ${leverValue(f.lever, p.$2)}',
                  style: TempoType.label.c(c.text1).tnum,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(TempoRadii.pill),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: c.surface3),
                    FractionallySizedBox(
                      widthFactor: frac.toDouble(),
                      child: Container(
                        color: frac >= 1 ? context.s.recHigh : c.text1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TempoButton(
              'End focus',
              kind: ButtonKind.text,
              small: true,
              onTap: () async {
                final ok = await confirmSheet(
                  context,
                  title: 'End this focus?',
                  body: 'Coach goes back to your usual plan from this week. You can start a new focus any time.',
                  action: 'End focus',
                );
                if (ok) await setFocus(ref.read(dbProvider), null);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeverCard extends ConsumerWidget {
  const _LeverCard(this.l, this.d);
  final sc.Contributor l;
  final LongevityData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final current = d.focus?.lever == l.lever;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  leverName(l.lever),
                  style: TempoType.titleM.c(c.text1),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'up to −${l.gain.toStringAsFixed(1)} yrs',
                style: TempoType.label.c(context.s.recHigh).tnum,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${leverValue(l.lever, l.value)} now · target ${leverValue(l.lever, l.target)}',
            style: TempoType.bodyS.c(c.text2).tnum,
          ),
          const SizedBox(height: 6),
          Text(leverHow(l.lever), style: TempoType.bodyS.c(c.text3)),
          const SizedBox(height: 12),
          if (current)
            const TempoBadge('Your focus')
          else
            TempoButton(
              'Make this my focus · ${sc.leverWeeks(l.lever)} weeks',
              kind: ButtonKind.secondary,
              small: true,
              onTap: () async {
                if (d.focus != null) {
                  final ok = await confirmSheet(
                    context,
                    title: 'Switch focus?',
                    body:
                        'This ends your ${leverName(d.focus!.lever).toLowerCase()} focus and rebuilds this week’s plan.',
                    action: 'Switch',
                  );
                  if (!ok) return;
                }
                HapticFeedback.mediumImpact();
                await setFocus(ref.read(dbProvider), l.lever);
              },
            ),
        ],
      ),
    );
  }
}

// ---- contributors -----------------------------------------------------------

class _Contributors extends StatelessWidget {
  const _Contributors(this.items);
  final List<sc.Contributor> items;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sorted = [...items]..sort((a, b) => a.years.compareTo(b.years));
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Younger', style: TempoType.caption.c(c.text3)),
              ),
              Text('Older', style: TempoType.caption.c(c.text3)),
            ],
          ),
          const SizedBox(height: 6),
          for (final (i, x) in sorted.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Semantics(
              label:
                  '${leverName(x.lever)}, ${leverValue(x.lever, x.value)}, ${_years(x.years)}',
              excludeSemantics: true,
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
                      const SizedBox(width: 8),
                      Text(
                        leverValue(x.lever, x.value),
                        maxLines: 1,
                        style: TempoType.caption.c(c.text2).tnum,
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          _years(x.years),
                          textAlign: TextAlign.end,
                          style: TempoType.label
                              .c(_tone(context, x.years))
                              .tnum,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Diverge(x.years),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A bar from the centre: left for younger, right for older (±5 years).
class _Diverge extends StatelessWidget {
  const _Diverge(this.years);
  final double years;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = (years.abs() / 5).clamp(0, 1).toDouble();
    final tone = _tone(context, years);
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (_, box) {
          final half = box.maxWidth / 2;
          final w = max(2.0, f * half);
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: years < 0 ? half - w : half,
                width: w,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: half - .5,
                width: 1,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: c.lineStrong),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---- manual inputs ----------------------------------------------------------

class _ManualCard extends ConsumerWidget {
  const _ManualCard(this.m);
  final ManualHealth m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    Future<void> save(ManualHealth n) async {
      await saveManualHealth(db, n);
      await updateLongevity(db);
    }

    return CardList(
      children: [
        ListRow(
          'Smoking',
          value: m.smoking == null
              ? 'Add'
              : leverValue(sc.Lever.smoking, m.smoking!.index.toDouble()),
          onTap: () async {
            // -1 = prefer not to say; dismissing returns null.
            final v = await pickOption<int>(
              context,
              title: 'Do you smoke?',
              options: [for (final s in sc.Smoking.values) s.index, -1],
              selected: m.smoking?.index ?? -1,
              label: (i) => i < 0
                  ? 'Prefer not to say'
                  : leverValue(sc.Lever.smoking, i.toDouble()),
            );
            if (v == null) return;
            await save(
              ManualHealth(
                smoking: v < 0 ? null : sc.Smoking.values[v],
                alcohol: m.alcohol,
                systolic: m.systolic,
                waist: m.waist,
              ),
            );
          },
        ),
        ListRow(
          'Alcohol',
          value: m.alcohol == null
              ? 'Add'
              : leverValue(sc.Lever.alcohol, m.alcohol!),
          onTap: () async {
            final v = await _number(
              context,
              title: 'Alcohol a week',
              suffix: 'units',
              note: 'A unit is a small glass of wine, half a pint or a single spirit.',
              initial: m.alcohol,
              min: 0,
              max: 100,
            );
            if (v == null) return;
            await save(
              ManualHealth(
                smoking: m.smoking,
                alcohol: v.isNaN ? null : v,
                systolic: m.systolic,
                waist: m.waist,
              ),
            );
          },
        ),
        ListRow(
          'Blood pressure',
          value: m.systolic == null
              ? 'Add'
              : leverValue(sc.Lever.bloodPressure, m.systolic!.toDouble()),
          onTap: () async {
            final v = await _number(
              context,
              title: 'Systolic blood pressure',
              suffix: 'mmHg',
              note: 'The top number from a home or pharmacy cuff.',
              initial: m.systolic?.toDouble(),
              min: 80,
              max: 220,
            );
            if (v == null) return;
            await save(
              ManualHealth(
                smoking: m.smoking,
                alcohol: m.alcohol,
                systolic: v.isNaN ? null : v.round(),
                waist: m.waist,
              ),
            );
          },
        ),
        ListRow(
          'Waist',
          value: m.waist == null ? 'Add' : leverValue(sc.Lever.waist, m.waist!),
          onTap: () async {
            final v = await _number(
              context,
              title: 'Waist',
              suffix: 'cm',
              note: 'Measured at the navel, breathing out.',
              initial: m.waist,
              min: 40,
              max: 200,
            );
            if (v == null) return;
            await save(
              ManualHealth(
                smoking: m.smoking,
                alcohol: m.alcohol,
                systolic: m.systolic,
                waist: v.isNaN ? null : v,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A number sheet. Null = cancelled; NaN = cleared.
Future<double?> _number(
  BuildContext context, {
  required String title,
  required String suffix,
  required String note,
  required double? initial,
  required double min,
  required double max,
}) {
  final ctl = TextEditingController(text: initial == null ? '' : _one(initial));
  return showTempoSheet<double>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final v = double.tryParse(ctl.text.replaceAll(',', '.'));
        final ok = v != null && v >= min && v <= max;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TempoType.titleM.c(ctx.c.text1)),
            const SizedBox(height: 12),
            TempoField(
              controller: ctl,
              suffix: suffix,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              error: ctl.text.isNotEmpty && !ok,
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              ctl.text.isNotEmpty && !ok
                  ? '⚠ Enter ${min.round()}–${max.round()}.'
                  : note,
              style: TempoType.caption.c(ctx.c.text2),
            ),
            const SizedBox(height: 16),
            TempoButton(
              'Save',
              expand: true,
              onTap: ok ? () => Navigator.pop(ctx, v) : null,
            ),
            if (initial != null)
              TempoButton(
                'Remove',
                kind: ButtonKind.text,
                expand: true,
                onTap: () => Navigator.pop(ctx, double.nan),
              ),
          ],
        );
      },
    ),
  );
}

// ---- how it works -----------------------------------------------------------

Future<void> _howItWorks(BuildContext context) => showTempoSheet<void>(
  context,
  builder: (ctx) {
    final c = ctx.c;
    Widget p(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(t, style: TempoType.body.c(c.text2)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How Tempo Age works', style: TempoType.titleM.c(c.text1)),
        const SizedBox(height: 12),
        p(
          'Each measure is compared with large studies of how it relates to '
          'lifespan, giving a risk ratio. Risk roughly doubles every 8 years '
          'of adult life, so a ratio becomes years: 8 × log₂(ratio).',
        ),
        p(
          'Measures use your last 30 days: resting HR and estimated VO₂max '
          '(Uth et al.), steps (Paluch 2022), Zone 2+ minutes (Arem 2015), '
          'strength (Momma 2022), sleep length and regularity (Windred '
          '2024), night breathing from SpO₂ dips, and the band’s stress '
          'index (lightly weighted).',
        ),
        p(
          'Optional details add smoking (Jha 2013), alcohol, blood '
          'pressure and waist. Each measure is capped, and the total stays '
          'within 15 years of your calendar age.',
        ),
        p(
          'Pace of aging is how fast Tempo Age moves per calendar year '
          'across your saved snapshots. Below 1× means slowing.',
        ),
        Text(
          'Everything is computed on your phone. It’s an estimate for '
          'motivation, not a medical result.',
          style: TempoType.bodyS.c(c.text3),
        ),
      ],
    );
  },
);
