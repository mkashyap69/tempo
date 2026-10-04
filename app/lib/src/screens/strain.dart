import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../core/profile.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'activity_detail.dart';
import 'learn.dart';
import 'nav.dart';
import 'shared.dart';

class StrainDay {
  StrainDay(
    this.day,
    this.minutes,
    this.wake,
    this.rest,
    this.hrMax,
    this.workouts,
  );
  final DateTime day;
  final List<st.MinuteSample> minutes;
  final DateTime wake;
  final double rest;
  final int hrMax;
  final List<st.Workout> workouts;

  Iterable<st.MinuteSample> get awake =>
      minutes.where((m) => !st.fromTs(m.ts).isBefore(wake));
  List<int> get zones =>
      sc.timeInZones(awake.map((m) => m.hr), hrMax, includeBelow: false);
  int? get peak => minutes
      .map((m) => m.hr)
      .whereType<int>()
      .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

  /// (minute of day, cumulative strain) from waking.
  List<(int, double)> get buildUp {
    var trimp = 0.0;
    final out = <(int, double)>[(wake.hour * 60 + wake.minute, 0)];
    for (final m in awake) {
      if (m.hr != null) {
        trimp += sc.minuteTrimp(m.hr!, hrRest: rest, hrMax: hrMax.toDouble());
      }
      final t = st.fromTs(m.ts);
      out.add((t.hour * 60 + t.minute, sc.strainFromTrimp(trimp)));
    }
    return out;
  }
}

final strainDayProvider = FutureProvider.family<StrainDay, DateTime>((
  ref,
  day,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final s = await db.scoreFor(day);
  final mins = await db.minutesBetween(day, day.add(const Duration(days: 1)));
  final profile = await loadAppProfile(db) ?? const Profile();
  return StrainDay(
    day,
    mins,
    s?.sleepEnd == null ? day : st.fromTs(s!.sleepEnd!),
    s?.rhr ?? 60,
    s?.hrMax ?? profile.effectiveMaxHr,
    await db.workoutsBetween(day, day.add(const Duration(days: 1))),
  );
});

class StrainScreen extends ConsumerWidget {
  const StrainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    final d = t == null ? null : ref.watch(strainDayProvider(t.day)).value;
    if (t == null || d == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final tg = t.target;
    final adds = planAdds(t);
    final (status, _) = strainStatus(t, planAdds: adds);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final zones = d.zones;
    final zmax = math.max(1, zones.reduce(math.max));
    final unconfirmed = d.workouts
        .where((w) => w.source == 'auto' && !w.confirmed)
        .toList();

    return TempoPage(
      gap: 22,
      children: [
        DetailHeader(
          title: 'Strain',
          subtitle: 'Live · updated ${clockOf(t.lastSync ?? now)}',
          trailing: InfoButton(
            label: 'How strain works',
            onTap: () => push(context, const LearnCardsScreen(initial: 1)),
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
                        text: n1(t.strain),
                        style: TempoType.hero.c(c.text1),
                      ),
                      TextSpan(text: '/21', style: TempoType.titleM.c(c.text3)),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TempoBadge(status),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 32,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: TickRow(
                          count: 21,
                          filled: t.strain.floor(),
                          color: s.strain[1],
                          colorFor: (i) => s.strainFor(i.toDouble()),
                        ),
                      ),
                      Positioned(
                        left: tg.lo / 21 * w,
                        width: (tg.hi - tg.lo) / 21 * w,
                        top: -6,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.text1, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: tg.cap
                        ? 'Today’s cap is '
                        : 'Today’s ${tg.general ? 'general ' : ''}target is ',
                  ),
                  TextSpan(
                    text: tg.cap
                        ? '${tg.hi.round()}'
                        : '${tg.lo.round()}–${tg.hi.round()}',
                    style: TextStyle(color: c.text1),
                  ),
                  TextSpan(
                    text: t.recovery == null
                        ? ', while Tempo learns your baseline.'
                        : ', set from your ${t.recovery!.round()}% recovery.${t.plan != null && !t.plan!.isRest && t.strain < tg.lo ? ' Your planned ${t.plan!.title.toLowerCase()} should add about ${adds.round()}${t.strain + adds >= tg.lo ? ' and land you inside it' : ''}.' : ''}',
                  ),
                ],
              ),
              style: TempoType.body.c(c.text2),
            ),
          ],
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Heart rate today',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  Text(
                    'resting ${d.rest.round()} · peak ${d.peak ?? '—'}',
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DayHrChart(day: d, nowMinute: nowMin),
            ],
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Time in zones', style: TempoType.label.c(c.text1)),
              const SizedBox(height: 12),
              SegmentBar(
                parts: [for (var i = 0; i < 5; i++) (zones[i], s.zone[i])],
              ),
              const SizedBox(height: 12),
              ZoneRows(minutes: zones, hrMax: d.hrMax, max: zmax),
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
                      'How today built up',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  Text(
                    'dashed = planned session',
                    style: TempoType.caption.c(c.text3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SvgChart(
                height: 160,
                semantics: 'Cumulative strain through the day',
                draw: (ink, box) {
                  double bx(int m) => m / 1440 * 520;
                  double by(double v) => 150 - v / 21 * 140;
                  if (!tg.cap) {
                    ink.rect(
                      Rect.fromLTRB(0, by(tg.hi), 520, by(tg.lo)),
                      ink.s.strain[1],
                      opacity: .12,
                    );
                    ink.text(
                      'target ${tg.lo.round()}–${tg.hi.round()}',
                      Offset(4, by(tg.hi) - 6),
                    );
                  } else {
                    ink.line(
                      Offset(0, by(tg.hi)),
                      Offset(520, by(tg.hi)),
                      ink.s.recLow,
                      dash: [5, 5],
                    );
                    ink.text('cap ${tg.hi.round()}', Offset(4, by(tg.hi) - 6));
                  }
                  final b = d.buildUp;
                  ink.polyline(
                    [for (final (m, v) in b) Offset(bx(m), by(v))],
                    ink.s.strain[1],
                    w: 2.5,
                  );
                  final last = b.isEmpty ? (nowMin, t.strain) : b.last;
                  if (t.plan != null && !t.plan!.isRest && last.$2 < tg.lo) {
                    final end = math.min(1440, last.$1 + t.plan!.minutes);
                    ink.polyline(
                      [
                        Offset(bx(last.$1), by(last.$2)),
                        Offset(bx(end), by(last.$2 + adds)),
                        Offset(520, by(last.$2 + adds + .2)),
                      ],
                      ink.s.strain[1],
                      w: 2,
                      dash: [5, 5],
                    );
                  }
                  ink.dot(Offset(bx(last.$1), by(last.$2)), 6, ink.c.text1);
                  ink.line(
                    const Offset(0, 150),
                    const Offset(520, 150),
                    ink.c.line,
                  );
                },
              ),
            ],
          ),
        ),
        Section(
          title: 'Activities today',
          child: d.workouts.isEmpty
              ? const TempoEmpty(
                  'No activities yet today. Start one with the play button, or Tempo will spot walks and rides on the next sync.',
                  kind: EmptyKind.ticks,
                )
              : CardList(
                  children: [
                    for (final w in d.workouts) ActivityRow(w: w),
                    if (unconfirmed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${unconfirmed.first.title} at ${clockShort(st.fromTs(unconfirmed.first.start))} was auto-detected. Right?',
                                style: TempoType.bodyS.c(c.text2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TempoButton(
                              'Yes',
                              small: true,
                              kind: ButtonKind.secondary,
                              onTap: () => ref
                                  .read(dbProvider)
                                  .updateWorkout(
                                    unconfirmed.first.id,
                                    const st.WorkoutsCompanion(
                                      confirmed: Value(true),
                                    ),
                                  ),
                            ),
                            const SizedBox(width: 6),
                            TempoButton(
                              'Change',
                              small: true,
                              kind: ButtonKind.ghost,
                              onTap: () => changeActivity(
                                context,
                                ref,
                                unconfirmed.first,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Lets the user correct an activity's type. Confirms it too.
Future<void> changeActivity(
  BuildContext context,
  WidgetRef ref,
  st.Workout w,
) async {
  final pick = await pickOption<sc.Sport?>(
    context,
    title: 'What was it?',
    options: [...sportOrder, null],
    label: sportLabel,
    selected: w.sport == null ? null : sc.Sport.values.asNameMap()[w.sport],
  );
  if (!context.mounted) return;
  await ref
      .read(dbProvider)
      .updateWorkout(
        w.id,
        st.WorkoutsCompanion(
          sport: Value(pick?.name),
          title: Value(sportLabel(pick)),
          confirmed: const Value(true),
        ),
      );
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.w});
  final st.Workout w;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final zones = (jsonDecode(w.zones) as List).cast<num>();
    var top = 1;
    for (var i = 0; i < zones.length; i++) {
      if (zones[i] > 0 && zones[i] >= zones[top - 1]) top = i + 1;
    }
    final a = st.fromTs(w.start), b = st.fromTs(w.end);
    return Pressable(
      label: w.title,
      onTap: () => push(context, ActivityDetailScreen(id: w.id)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                color: s.zoneColor(top),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(w.title, style: TempoType.label.c(c.text1)),
                      if (w.source == 'auto') ...[
                        const SizedBox(width: 8),
                        const TempoBadge('Auto-detected', small: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${clockShort(a)}–${clockShort(b)}${ampm(b) == 'pm' ? ' pm' : ''}${w.avgHr == null ? '' : ' · avg ${w.avgHr} bpm'}',
                    style: TempoType.caption.c(c.text2).tnum,
                  ),
                ],
              ),
            ),
            Text(
              '+${n1(w.strain)}',
              style: TempoType.label.c(s.strain[1]).tnum,
            ),
          ],
        ),
      ),
    );
  }
}

/// Zone rows: label, bar, bpm range, minutes.
class ZoneRows extends StatelessWidget {
  const ZoneRows({
    super.key,
    required this.minutes,
    required this.hrMax,
    required this.max,
  });
  final List<int> minutes;
  final int hrMax, max;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return Column(
      children: [
        for (var i = 0; i < 5; i++)
          SizedBox(
            height: 32,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('Z${i + 1}', style: TempoType.label.c(c.text1)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Bar(fraction: minutes[i] / max, color: s.zone[i]),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: Text(
                    '${sc.zoneRange(i + 1, hrMax).lo}–${sc.zoneRange(i + 1, hrMax).hi} bpm',
                    style: TempoType.caption.c(c.text3).tnum,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${minutes[i]} min',
                    textAlign: TextAlign.right,
                    style: TempoType.label.c(c.text1).tnum,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Heart rate across the day with zone lines and activity bars.
class DayHrChart extends StatelessWidget {
  const DayHrChart({super.key, required this.day, required this.nowMinute});
  final StrainDay day;
  final int nowMinute;
  @override
  Widget build(BuildContext context) => SvgChart(
    height: 240,
    semantics: 'Heart rate across the day with zone lines',
    draw: (ink, box) {
      double x(int m) => m / 1440 * 490;
      double y(num b) => 200 - (b - 40) / 140 * 200;
      for (var z = 1; z <= 5; z++) {
        final b = sc.zoneRange(z, day.hrMax).lo;
        ink.line(Offset(0, y(b)), Offset(490, y(b)), ink.c.line, dash: [2, 4]);
        ink.text('Z$z', Offset(520, y(b) + 5), align: TextAlign.right);
      }
      final isToday = DateUtils.isSameDay(day.day, DateTime.now());
      if (isToday) {
        ink.rect(
          Rect.fromLTWH(x(nowMinute), 0, 490 - x(nowMinute), 200),
          ink.c.surface2,
          opacity: .6,
        );
      }
      final pts = <Offset?>[];
      int? prev;
      for (final m in day.minutes) {
        final t = st.fromTs(m.ts);
        final mm = t.hour * 60 + t.minute;
        if (prev != null && mm - prev > 20) pts.add(null);
        if (m.hr != null) {
          pts.add(Offset(x(mm), y(m.hr!.clamp(40, 180))));
          prev = mm;
        }
      }
      ink.gappedLine(pts, ink.c.text1, w: 1.75);
      for (final w in day.workouts) {
        final a = st.fromTs(w.start), b = st.fromTs(w.end);
        final zs = (jsonDecode(w.zones) as List).cast<num>();
        var top = 1;
        for (var i = 0; i < zs.length; i++) {
          if (zs[i] > 0 && zs[i] >= zs[top - 1]) top = i + 1;
        }
        ink.rect(
          Rect.fromLTWH(
            x(a.hour * 60 + a.minute),
            204,
            math.max(3, x(b.hour * 60 + b.minute) - x(a.hour * 60 + a.minute)),
            8,
          ),
          ink.s.zoneColor(top),
          radius: 2,
        );
      }
      for (final (m, l) in [
        (0, '12 am'),
        (360, '6'),
        (720, '12 pm'),
        (1080, '6'),
      ]) {
        ink.text(l, Offset(x(m) * 520 / 490, 234));
      }
    },
  );
}
