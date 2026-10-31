import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart' show stepsToday;
import '../core/format.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'activity_detail.dart';
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
    this.open,
  });
  final DateTime at;
  final String title, sub;
  final bool now, sleep;
  final Widget Function()? open;
}

DateTime _at(DateTime day, int minute) =>
    DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));

/// The day's events, oldest first: last night, waking, workouts, now, the
/// session still planned, wind-down and bedtime.
List<DayEvent> dayEvents(TodayData t, {required DateTime now, int? steps}) {
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
  return out;
}

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
    final now = appNow();
    final events = dayEvents(t, now: now, steps: steps);
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
          const SizedBox(height: 14),
          for (final (i, e) in events.indexed)
            _EventRow(
              e: e,
              ahead: e.at.isAfter(now) && !e.now,
              last: i == events.length - 1,
              color: e.now
                  ? c.text1
                  : e.sleep
                  ? s.sleepDeep
                  : s.strain[1],
            ),
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
