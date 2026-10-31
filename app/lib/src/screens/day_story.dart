import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart' show stepsToday;
import '../core/day_tags.dart';
import '../core/minutes.dart' show loadMinutes;
import '../core/format.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'activity_detail.dart';
import 'coach.dart' show CoachScreen;
import 'day_timeline.dart';
import 'nav.dart';
import 'sleep.dart';
import 'workout_detail.dart';

final _stepsProvider = dbQuery((db, _) => stepsToday(db, DateTime.now()));

/// One moment of the day.
final class DayEvent {
  const DayEvent(
    this.at,
    this.title,
    this.sub, {
    this.now = false,
    this.sleep = false,
    this.tag = false,
    this.open,
  });
  final DateTime at;
  final String title, sub;
  final bool now, sleep, tag;
  final Widget Function()? open;
}

DateTime _at(DateTime day, int minute) =>
    DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));

/// The day's events, oldest first: last night, waking, workouts, quick
/// tags, now, the session still planned, wind-down, bedtime and [tomorrow].
List<DayEvent> dayEvents(
  TodayData t, {
  required DateTime now,
  int? steps,
  List<(sc.QuickTag, int)> tags = const [],
  String? tomorrow,
}) {
  final out = <DayEvent>[];
  final s = t.score;
  if (s?.sleepStart != null && s?.sleepEnd != null) {
    final a = st.fromTs(s!.sleepStart!), b = st.fromTs(s.sleepEnd!);
    out.add(
      DayEvent(
        a,
        'Slept ${hmShort(t.slept ?? b.difference(a).inMinutes / 60)}'
            '${t.sleepScore == null ? '' : ' · score ${t.sleepScore!.round()}'}',
        'Asleep ${clockOf(a)}',
        sleep: true,
        open: () => const SleepScreen(),
      ),
    );
    out.add(
      DayEvent(
        b,
        'Woke up',
        t.recovery == null
            ? 'Recovery is still learning'
            : 'Recovery ${t.recovery!.round()}%'
                  '${s.rhr == null ? '' : ' · resting HR ${s.rhr!.round()}'}',
      ),
    );
  }
  for (final w in t.workouts) {
    final a = st.fromTs(w.start), b = st.fromTs(w.end);
    out.add(
      DayEvent(
        a,
        w.title,
        '${b.difference(a).inMinutes} min · strain ${n1(w.strain)}',
        open: () => ActivityDetailScreen(id: w.id),
      ),
    );
  }
  for (final (tag, m) in tags) {
    out.add(
      DayEvent(
        _at(t.day, m),
        sc.quickTagName(tag),
        'Tagged · in your journal',
        tag: true,
      ),
    );
  }
  final nowLine = [
    if (steps != null) '${grouped(steps)} steps',
    'strain ${n1(t.strain)}',
  ].join(' · ');
  out.add(
    DayEvent(
      now,
      nowLine[0].toUpperCase() + nowLine.substring(1),
      'Now',
      now: true,
      open: () => const DayTimelineScreen(),
    ),
  );
  final p = t.plan;
  final open =
      p != null &&
      !p.isRest &&
      !t.restDay &&
      t.status != sc.DayStatus.done &&
      t.status != sc.DayStatus.doneEasier &&
      t.status != sc.DayStatus.skipped &&
      t.status != sc.DayStatus.missedDay;
  if (open && t.plannedMinute != null) {
    final at = _at(t.day, t.plannedMinute!);
    if (at.isAfter(now)) {
      out.add(
        DayEvent(
          at,
          '${p.title} · ${p.minutes} min',
          'Planned',
          open: () => const WorkoutDetailScreen(),
        ),
      );
    }
  }
  var bed = _at(t.day, t.bedtimeMinute);
  if (t.bedtimeMinute < 12 * 60) bed = bed.add(const Duration(days: 1));
  final wind = bed.subtract(const Duration(minutes: 30));
  if (wind.isAfter(now)) {
    out.add(
      DayEvent(wind, 'Wind down', 'Screens off, lights low', sleep: true),
    );
  }
  if (bed.isAfter(now)) {
    out.add(
      DayEvent(
        bed,
        'Bed by ${clockOf(bed)}',
        'Tonight’s need ${hmShort(t.needTonight)}'
            '${t.smartAlarm == null ? '' : ' · alarm ${fmtHm(t.smartAlarm!)}'}',
        sleep: true,
        open: () => const SleepScreen(),
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  if (tomorrow != null) {
    out.add(
      DayEvent(
        _at(t.day.add(const Duration(days: 1)), t.wakeMinute),
        'Tomorrow',
        tomorrow,
        open: () => const CoachScreen(standalone: true),
      ),
    );
  }
  return out;
}

/// "Up by 7:30 · Long run, 75 min" from tomorrow's plan row, when it's in
/// this week's plan.
String tomorrowLine(TodayData t) {
  final key = st.dateKey(t.day.add(const Duration(days: 1)));
  final row = t.week.where((r) => r.date == key).firstOrNull;
  final up = 'Up by ${fmtHm(t.wakeMinute)}';
  if (row == null) return up;
  final s = sc.Session.fromJson(
    jsonDecode(row.session) as Map<String, dynamic>,
  );
  return s.isRest
      ? '$up · rest day, a walk is fine'
      : '$up · ${s.title}, ${s.minutes} min';
}

final _tagsProvider = FutureProvider.family<List<(sc.QuickTag, int)>, DateTime>(
  (ref, day) async {
    ref.watch(dbTickProvider);
    return loadDayTags(ref.watch(dbProvider), day);
  },
);

/// Heart rate through [day] in 15-minute means (minute of day, bpm).
final _hrProvider = FutureProvider.family<List<(int, double)>, DateTime>((
  ref,
  day,
) async {
  ref.watch(dbTickProvider);
  final end = day.add(const Duration(days: 1));
  final now = DateTime.now();
  final mins = (await loadMinutes(
    ref.watch(dbProvider),
    day,
    end.isAfter(now) ? now : end,
  )).minutes;
  final buckets = <int, List<int>>{};
  for (final m in mins) {
    if (m.hr == null || m.offWrist) continue;
    final k = (m.ts.hour * 60 + m.ts.minute) ~/ 15;
    (buckets[k] ??= []).add(m.hr!);
  }
  return [
    for (final k in buckets.keys.toList()..sort())
      (k * 15 + 7, buckets[k]!.reduce((a, b) => a + b) / buckets[k]!.length),
  ];
});

/// Today in the evening: the day as a timeline from last night to tonight's
/// bedtime, a "now" marker between what happened and what's ahead. Each
/// event opens its screen.
class DayStoryCard extends ConsumerWidget {
  const DayStoryCard({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final steps = ref.watch(_stepsProvider).value;
    final tags = ref.watch(_tagsProvider(t.day)).value ?? const [];
    final hr = ref.watch(_hrProvider(t.day)).value ?? const [];
    final now = appNow();
    final events = dayEvents(
      t,
      now: now,
      steps: steps,
      tags: tags,
      tomorrow: tomorrowLine(t),
    );
    final tg = t.target;
    final summary = [
      if (t.status == sc.DayStatus.done && t.plan != null)
        '${t.plan!.title} done',
      'strain ${n1(t.strain)}${tg.general
          ? ''
          : t.strain >= tg.lo && t.strain <= tg.hi
          ? ', in range'
          : t.strain > tg.hi
          ? ', above range'
          : ', under range'}',
    ].join(' · ');
    return TempoCard(
      label: 'Your day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('Your day'),
          const SizedBox(height: 4),
          Text(
            '${summary[0].toUpperCase()}${summary.substring(1)}.',
            style: TempoType.bodyS.c(c.text2).tnum,
          ),
          if (hr.length >= 4) ...[
            const SizedBox(height: 14),
            _HrBand(
              hr: hr,
              now: now.hour * 60 + now.minute,
              marks: [
                for (final e in events)
                  if (!e.now &&
                      !e.sleep &&
                      DateUtils.isSameDay(e.at, t.day) &&
                      !e.at.isAfter(now))
                    (e.at.hour * 60 + e.at.minute, e.tag),
              ],
            ),
          ],
          const SizedBox(height: 14),
          for (final (i, e) in events.indexed) ...[
            _EventRow(
              e: e,
              ahead: e.at.isAfter(now) && !e.now,
              last: i == events.length - 1,
              color: e.now
                  ? c.text1
                  : e.sleep
                  ? s.sleepDeep
                  : e.tag
                  ? s.recMid
                  : s.strain[1],
            ),
            if (e.now) _QuickTags(t: t),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.e,
    required this.ahead,
    required this.last,
    required this.color,
  });
  final DayEvent e;
  final bool ahead, last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dot = Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ahead ? c.surface1 : color,
        border: Border.all(color: color, width: 2),
        boxShadow: e.now
            ? [BoxShadow(color: c.lineStrong, spreadRadius: 3)]
            : null,
      ),
    );
    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                e.now ? 'Now' : clockOf(e.at),
                textAlign: TextAlign.right,
                style: (e.now ? TempoType.label : TempoType.caption)
                    .c(e.now ? c.text1 : c.text3)
                    .tnum,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 16,
            child: Column(
              children: [
                dot,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: c.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: TempoType.label
                              .c(ahead ? c.text2 : c.text1)
                              .tnum,
                        ),
                        Text(
                          e.now ? 'So far today' : e.sub,
                          style: TempoType.bodyS.c(c.text2).tnum,
                        ),
                      ],
                    ),
                  ),
                  if (e.open != null)
                    Text('›', style: TempoType.titleM.c(c.text3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return e.open == null
        ? row
        : Pressable(
            label: e.title,
            onTap: () => push(context, e.open!()),
            child: row,
          );
  }
}

/// One-tap tags under "Now": each writes its Journal entries with the time,
/// with an undo.
class _QuickTags extends ConsumerWidget {
  const _QuickTags({required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(left: 84, bottom: 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tag in sc.QuickTag.values)
            TempoButton(
              '+ ${sc.quickTagName(tag)}',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () async {
                final host = Navigator.of(context).context;
                final at = appNow();
                final undo = await addQuickTag(
                  ref.read(dbProvider),
                  tag,
                  at,
                  bedtime: t.bedtimeMinute,
                );
                if (host.mounted) {
                  showTempoToast(
                    host,
                    '${sc.quickTagName(tag)} at ${clockOf(at)} · in your journal',
                    action: 'Undo',
                    onAction: undo,
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

/// The day's heart rate as a soft band, with a mark for each workout or
/// tag and a line at now.
class _HrBand extends StatelessWidget {
  const _HrBand({required this.hr, required this.now, required this.marks});
  final List<(int, double)> hr;
  final int now;
  final List<(int, bool)> marks;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final lo = hr.map((x) => x.$2).reduce((a, b) => a < b ? a : b);
    final hi = hr.map((x) => x.$2).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Heart rate', style: TempoType.caption.c(c.text2)),
            ),
            Text(
              '${lo.round()}–${hi.round()} bpm',
              style: TempoType.caption.c(c.text3).tnum,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label:
              'Heart rate through the day, from ${lo.round()} to ${hi.round()} bpm',
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _HrPainter(
                hr,
                now,
                marks,
                line: s.recLow,
                fill: s.tintRecLow,
                nowColor: c.text1,
                workout: s.strain[1],
                tag: s.recMid,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in ['00', '06', '12', '18', '24'])
              Text(h, style: TempoType.caption.c(c.text3).tnum),
          ],
        ),
      ],
    );
  }
}

class _HrPainter extends CustomPainter {
  _HrPainter(
    this.hr,
    this.now,
    this.marks, {
    required this.line,
    required this.fill,
    required this.nowColor,
    required this.workout,
    required this.tag,
  });
  final List<(int, double)> hr;
  final int now;
  final List<(int, bool)> marks;
  final Color line, fill, nowColor, workout, tag;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = hr.map((x) => x.$2).reduce((a, b) => a < b ? a : b) - 5;
    final hi = hr.map((x) => x.$2).reduce((a, b) => a > b ? a : b) + 5;
    double x(int m) => m / 1440 * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final path = Path()..moveTo(x(hr.first.$1), y(hr.first.$2));
    for (final p in hr.skip(1)) {
      path.lineTo(x(p.$1), y(p.$2));
    }
    final area = Path.from(path)
      ..lineTo(x(hr.last.$1), size.height)
      ..lineTo(x(hr.first.$1), size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (final (m, isTag) in marks) {
      final near = hr.reduce(
        (a, b) => (a.$1 - m).abs() <= (b.$1 - m).abs() ? a : b,
      );
      canvas.drawCircle(
        Offset(x(m), y(near.$2)),
        3.5,
        Paint()..color = isTag ? tag : workout,
      );
    }
    final nx = x(now);
    final dash = Paint()
      ..color = nowColor
      ..strokeWidth = 1.2;
    for (var yy = 0.0; yy < size.height; yy += 6) {
      canvas.drawLine(Offset(nx, yy), Offset(nx, yy + 3), dash);
    }
  }

  @override
  bool shouldRepaint(_HrPainter o) =>
      o.hr != hr || o.now != now || o.marks != marks;
}
