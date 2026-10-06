import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/score_service.dart' show dismissBandWorkout, saveRpe;
import '../core/format.dart';
import '../core/profile.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'strain.dart' show changeActivity;

@immutable
class EffectQuery {
  const EffectQuery(this.sport, this.strain);
  final String? sport;
  final double strain;
  @override
  bool operator ==(Object other) =>
      other is EffectQuery &&
      other.sport == sport &&
      (other.strain - strain).abs() < .05;
  @override
  int get hashCode => Object.hash(sport, (strain * 10).round());
}

/// Average next-morning recovery after similar sessions, against the
/// 30-day mean before each one. Estimate; needs ≥ 3 sessions.
final effectProvider =
    FutureProvider.family<({double delta, int n}), EffectQuery>((ref, q) async {
      ref.watch(dbTickProvider);
      final db = ref.watch(dbProvider);
      final now = DateTime.now();
      final ws = await db.workoutsBetween(
        now.subtract(const Duration(days: 120)),
        now,
      );
      final deltas = <double>[];
      for (final w in ws) {
        if (q.sport != null && w.sport != q.sport) continue;
        if (w.strain < q.strain * .5 || w.strain > q.strain * 1.5 + .5) {
          continue;
        }
        final d = dayOf(st.fromTs(w.start));
        final next = await db.scoreFor(d.add(const Duration(days: 1)));
        if (next?.recovery == null || next!.calibrating) continue;
        final before = await db.scoresBefore(d, limit: 30);
        final b = sc.Baseline.of(
          before.map((x) => x.calibrating ? null : x.recovery),
        );
        if (b == null) continue;
        deltas.add(next.recovery! - b.mean);
      }
      return (
        delta: deltas.isEmpty
            ? 0.0
            : deltas.reduce((a, b) => a + b) / deltas.length,
        n: deltas.length,
      );
    });

class _ActivityData {
  _ActivityData(
    this.w,
    this.hr,
    this.hrMax,
    this.similar, {
    this.gait,
    this.strideFromBand = false,
  });
  final st.Workout w;

  /// Steps, cadence and estimated distance and pace (walks, runs and other
  /// on-foot sessions); null without steps.
  final sc.Gait? gait;

  /// Whether the stride came from the band's own counter (else height).
  final bool strideFromBand;
  final List<(DateTime, int)> hr;
  final int hrMax;
  final List<st.Workout> similar;
}

final _activityProvider = FutureProvider.family<_ActivityData?, int>((
  ref,
  id,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final w = await db.workout(id);
  if (w == null) return null;
  final a = st.fromTs(w.start), b = st.fromTs(w.end);
  final rows = await db.minutesBetween(a, b);
  var hr = <(DateTime, int)>[
    for (final m in rows)
      if (m.hr != null) (st.fromTs(m.ts), m.hr!),
  ];
  if (w.source == 'live') {
    final live = [
      for (final h in await db.hrLiveSince(a))
        if (h.ts < w.end) (st.fromTs(h.ts), h.bpm),
    ];
    if (live.length > hr.length) hr = live;
  }
  final s = await db.scoreFor(dayOf(a));
  final profile = await loadAppProfile(db) ?? const Profile();
  final dur = w.end - w.start;
  final all = await db.workoutsBetween(
    a.subtract(const Duration(days: 90)),
    DateTime.now().add(const Duration(minutes: 1)),
  );
  // This one plus the four nearest in time of the same type and length.
  final others =
      [
        for (final x in all)
          if (x.id != w.id &&
              x.sport == w.sport &&
              (x.end - x.start) >= dur * .7 &&
              (x.end - x.start) <= dur * 1.3)
            x,
      ]..sort(
        (p, q) =>
            (p.start - w.start).abs().compareTo((q.start - w.start).abs()),
      );
  final similar = [w, ...others.take(4)]
    ..sort((p, q) => q.start.compareTo(p.start));
  // Gait for anything on foot.
  sc.Gait? gait;
  var fromBand = false;
  const offFoot = {'cycling', 'strength', 'yoga'};
  if (!offFoot.contains(w.sport)) {
    final mins = [
      for (final m in rows) sc.Minute(st.fromTs(m.ts), steps: m.steps),
    ];
    final probe = sc.gaitOf(mins, strideM: 1);
    if (probe != null) {
      final running = w.sport == sc.Sport.running.name || probe.running;
      final band = double.tryParse(await db.setting(Keys.bandStride) ?? '');
      final stride = sc.strideMetres(
        running: running,
        bandStride: band,
        heightCm: profile.heightCm.toDouble(),
      );
      fromBand = !running && band != null && stride == band;
      gait = sc.gaitOf(mins, strideM: stride);
    }
  }
  return _ActivityData(
    w,
    hr,
    s?.hrMax ?? profile.effectiveMaxHr,
    similar,
    gait: gait,
    strideFromBand: fromBand,
  );
});

class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(_activityProvider(id));
    final c = context.c, s = context.s;
    if (d.isLoading && !d.hasValue) return Scaffold(backgroundColor: c.bg);
    final data = d.value;
    if (data == null) {
      return TempoPage(
        children: [
          const DetailHeader(title: 'Activity'),
          const TempoEmpty('This activity was removed.'),
        ],
      );
    }
    final w = data.w;
    final a = st.fromTs(w.start), b = st.fromTs(w.end);
    final mins = ((w.end - w.start) / 60).round();
    final zones = (jsonDecode(w.zones) as List)
        .cast<num>()
        .map((e) => e.round())
        .toList();
    final effect = ref
        .watch(effectProvider(EffectQuery(w.sport, w.strain)))
        .value;
    final maxStrain = math.max(
      3.0,
      data.similar.fold<double>(0, (m, x) => math.max(m, x.strain)),
    );
    final hrs = [for (final h in data.hr) h.$2];

    return TempoPage(
      children: [
        DetailHeader(
          title: '',
          center: TempoBadge(switch (w.source) {
            'auto' =>
              w.confirmed ? 'Auto-detected · confirmed' : 'Auto-detected',
            'band' => 'Recorded on the band',
            _ => 'Recorded live',
          }),
          trailing: TempoIconButton(
            TempoIcons.edit,
            label: 'Edit activity',
            stroke: 1.75,
            onTap: () => _edit(context, ref, w),
          ),
        ),
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: sportTint(w.sport, dark: c.dark),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: TempoIcon(
                sportIcon(w.sport),
                size: 26,
                color: sportColor(w.sport, dark: c.dark),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.title, style: TempoType.pageTitle.c(c.text1)),
                  const SizedBox(height: 4),
                  Text(
                    '${dayShort(a)} · ${clockShort(a)}–${clockOf(b)} · $mins min',
                    style: TempoType.bodyS.c(c.text2).tnum,
                  ),
                ],
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Stat('Strain', '+${n1(w.strain)}', color: s.strain[1]),
            ),
            Expanded(child: Stat('Avg HR', '${w.avgHr ?? '—'}')),
            Expanded(child: Stat('Max HR', '${w.maxHr ?? '—'}')),
          ],
        ),
        if (data.gait != null)
          GaitCard(gait: data.gait!, strideFromBand: data.strideFromBand),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Heart rate', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 10),
              if (hrs.length < 2)
                Text(
                  'No heart rate stored for this activity.',
                  style: TempoType.bodyS.c(c.text2),
                )
              else
                SvgChart(
                  height: 200,
                  semantics: 'Heart rate through the activity',
                  draw: (ink, box) {
                    final lo = math.min(80, hrs.reduce(math.min) - 5),
                        hi = math.max(data.hrMax, hrs.reduce(math.max) + 5);
                    double y(num v) => 196 - (v - lo) / (hi - lo) * 192;
                    for (var z = 1; z <= 5; z++) {
                      final r = sc.zoneRange(z, data.hrMax);
                      final top = y(math.min(hi, r.hi + 1)),
                          bot = y(math.max(lo, r.lo));
                      if (bot <= top) continue;
                      ink.rect(
                        Rect.fromLTRB(0, top, 490, bot),
                        ink.s.zoneColor(z),
                        opacity: .14,
                      );
                      ink.text(
                        'Z$z',
                        Offset(520, (top + bot) / 2 + 5),
                        align: TextAlign.right,
                      );
                    }
                    final t0 = data.hr.first.$1,
                        span = math.max(
                          1,
                          data.hr.last.$1.difference(t0).inSeconds,
                        );
                    ink.polyline(
                      [
                        for (final (t, v) in data.hr)
                          Offset(t.difference(t0).inSeconds / span * 490, y(v)),
                      ],
                      ink.c.text1,
                      w: 2.5,
                    );
                  },
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0′', style: TempoType.caption.c(c.text3)),
                  Text('$mins′', style: TempoType.caption.c(c.text3).tnum),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Zones', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 10),
              SegmentBar(
                parts: [for (var i = 0; i < 5; i++) (zones[i], s.zone[i])],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 5; i++)
                    Text(
                      'Z${i + 1} ${zones[i]}′',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (effect != null)
          TempoCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '■',
                    style: TextStyle(fontSize: 10, color: s.recMid),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Impact on tomorrow’s recovery',
                        style: TempoType.label.c(c.text1),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: effect.n < 3
                              ? [
                                  const TextSpan(
                                    text: 'Not enough similar sessions yet to estimate. Tomorrow will mostly come down to tonight’s sleep.',
                                  ),
                                ]
                              : [
                                  TextSpan(
                                    text:
                                        '${sportLabel(sc.Sport.values.asNameMap()[w.sport])} sessions like this have moved your next-morning recovery by about ',
                                  ),
                                  TextSpan(
                                    text:
                                        '${effect.delta >= 0 ? '+' : '−'}${effect.delta.abs().round()} points',
                                    style: TextStyle(color: c.text1),
                                  ),
                                  TextSpan(
                                    text: effect.delta.abs() < 5
                                        ? ' — small. Most of tomorrow will come down to tonight’s sleep.'
                                        : '. Protect tonight’s bedtime.',
                                  ),
                                ],
                        ),
                        style: TempoType.bodyS.c(c.text2),
                      ),
                      const SizedBox(height: 8),
                      TempoBadge(
                        'Est. · from ${effect.n} similar ${effect.n == 1 ? 'session' : 'sessions'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (data.similar.length > 1)
          Section(
            title: 'Compared with similar ${w.title.toLowerCase()}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardList(
                  children: [
                    for (final x in data.similar)
                      Container(
                        color: x.id == w.id ? c.surface2 : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                '${dm(st.fromTs(x.start))}${x.id == w.id ? ' · this' : ''}',
                                style: TempoType.caption.c(c.text2).tnum,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Bar(
                                fraction: x.strain / maxStrain,
                                color: s.strain[1],
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 56,
                              child: Text(
                                x.avgHr == null ? '' : '${x.avgHr} bpm',
                                textAlign: TextAlign.right,
                                style: TempoType.caption.c(c.text2).tnum,
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '+${n1(x.strain)}',
                                textAlign: TextAlign.right,
                                style: TempoType.label.c(c.text1).tnum,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Same type, similar length. ${_compare(w, data.similar)}',
                  style: TempoType.caption.c(c.text3),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(TempoRadii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  w.rpe == null
                      ? 'How hard did it feel? Coach adjusts the next days from it.'
                      : 'You rated it ${w.rpe}/10',
                  style: TempoType.bodyS.c(c.text1),
                ),
              ),
              TempoButton(
                w.rpe == null ? 'Rate RPE' : 'Change',
                small: true,
                kind: ButtonKind.secondary,
                onTap: () => _rate(context, ref, w),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _compare(st.Workout w, List<st.Workout> sim) {
    final others = sim.where((x) => x.id != w.id).toList();
    if (others.isEmpty) return '';
    final avg = others.fold<double>(0, (a, x) => a + x.strain) / others.length;
    final d = w.strain - avg;
    return d.abs() < .3
        ? 'This one: about your usual.'
        : d > 0
        ? 'This one: harder than your usual at the same length.'
        : 'This one: easier than your usual at the same length.';
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, st.Workout w) async {
    final what = await pickOption<String>(
      context,
      title: 'Edit activity',
      options: const ['type', 'delete'],
      label: (o) => o == 'type' ? 'Change type' : 'Delete activity',
    );
    if (!context.mounted || what == null) return;
    if (what == 'type') {
      await changeActivity(context, ref, w);
    } else if (await confirmSheet(
      context,
      title: 'Delete this activity?',
      body:
          'Its heart rate stays in your history; only the activity is removed.',
      action: 'Delete',
      danger: true,
    )) {
      final db = ref.read(dbProvider);
      await db.deleteWorkout(w.id);
      // Band workouts are re-derived on every rescore; remember the removal.
      if (w.source == 'band') await dismissBandWorkout(db, w.start);
      if (context.mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _rate(BuildContext context, WidgetRef ref, st.Workout w) async {
    final v = await pickOption<int>(
      context,
      title: 'How hard did it feel?',
      options: List.generate(10, (i) => i + 1),
      label: (i) =>
          '$i · ${const ['Very easy', 'Easy', 'Easy', 'Moderate', 'Moderate', 'Somewhat hard', 'Hard', 'Very hard', 'Very hard', 'Max'][i - 1]}',
      selected: w.rpe,
    );
    if (v != null) await saveRpe(ref.read(dbProvider), w.id, v);
  }
}

/// Steps, cadence, estimated distance and pace, a cadence chart and
/// kilometre splits for a session on foot.
class GaitCard extends StatelessWidget {
  const GaitCard({super.key, required this.gait, this.strideFromBand = false});
  final sc.Gait gait;
  final bool strideFromBand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final g = gait;
    final pace = g.movingPacePerKm ?? g.pacePerKm;
    final km = g.distanceM / 1000;
    final steps = NumberFormat.decimalPattern().format(g.steps);
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pace & cadence', style: TempoType.label.c(c.text1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Stat('Steps', steps)),
              Expanded(
                child: Stat('Cadence', '${g.cadence.round()}', unit: ' spm'),
              ),
              Expanded(
                child: Stat(
                  'Distance',
                  km.toStringAsFixed(2),
                  unit: ' km',
                  estimate: true,
                ),
              ),
              Expanded(
                child: Stat(
                  'Pace',
                  pace == null ? '—' : mmss(pace),
                  unit: ' /km',
                  estimate: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SvgChart(
            height: 120,
            semantics: 'Steps per minute through the session',
            draw: (ink, box) {
              final top = math.max(140, g.peakCadence + 10).toDouble();
              double y(num v) => 116 - v / top * 112;
              final n = g.perMinute.length;
              final w = 520 / n;
              for (final (i, v) in g.perMinute.indexed) {
                ink.rect(
                  Rect.fromLTRB(
                    i * w + w * .15,
                    y(v),
                    (i + 1) * w - w * .15,
                    116,
                  ),
                  v >= sc.movingCadence ? ink.c.text2 : ink.c.line,
                  radius: 2,
                );
              }
              ink.line(
                Offset(0, y(g.cadence)),
                Offset(520, y(g.cadence)),
                ink.c.text1,
                dash: const [6, 4],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Steps per minute; dashed = average while moving. '
            'Best minute ${g.peakCadence}.',
            style: TempoType.caption.c(c.text3),
          ),
          if (g.splits.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final (i, sp) in g.splits.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('Km ${i + 1}', style: TempoType.bodyS.c(c.text2)),
                    const Spacer(),
                    Text(mmss(sp), style: TempoType.bodyS.c(c.text1).tnum),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            'Distance and pace are estimated from steps × '
            '${g.strideM.toStringAsFixed(2)} m '
            '(${strideFromBand
                ? "the band's own stride today"
                : g.running
                ? 'a running stride from your height'
                : 'a walking stride from your height'}). '
            'The band has no GPS.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}
