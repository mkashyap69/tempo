import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_notifier.dart';
import '../core/coach_service.dart' show dayOf;
import '../core/format.dart';
import '../core/profile.dart' show Keys;
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'day_timeline.dart';
import 'nav.dart';
import 'strain.dart' show ActivityRow;
import 'today_charts.dart';

/// How many days back Today's arrows can go (Saturday, Sunday, today).
const todayBackMax = 2;

class _Counter extends Notifier<int> {
  @override
  int build() => 0;
  void set(int v) => state = v;
  void bump() => state++;
}

/// Days back from today that Today shows (0 = today).
final todayBackProvider = NotifierProvider<_Counter, int>(_Counter.new);

/// Bumped by "Replay": the rings draw in again.
final ringsReplayProvider = NotifierProvider<_Counter, int>(_Counter.new);

/// Today's data as it stood on an earlier day (date key).
final todayAtProvider = FutureProvider.family<TodayData, String>((
  ref,
  key,
) async {
  ref.watch(dbTickProvider);
  final d = DateTime.parse(key);
  // Read as of that evening, so the day counts in full.
  return loadToday(ref.watch(dbProvider), at: d.add(const Duration(hours: 23)));
});

/// ‹ › beside the title: step to an earlier day and back.
class DayStepper extends ConsumerWidget {
  const DayStepper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final back = ref.watch(todayBackProvider);
    final n = ref.read(todayBackProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TempoIconButton(
          TempoIcons.back,
          label: 'Earlier day',
          size: 18,
          onTap: back >= todayBackMax
              ? null
              : () {
                  TempoHaptics.selection();
                  n.set(back + 1);
                },
        ),
        TempoIconButton(
          TempoIcons.chevron,
          label: 'Later day',
          size: 18,
          onTap: back == 0
              ? null
              : () {
                  TempoHaptics.selection();
                  n.set(back - 1);
                },
        ),
      ],
    );
  }
}

/// Today's page for an earlier day: the rings as they ended, the day's
/// session and workouts, and the way to its timeline.
List<Widget> pastDayChildren(BuildContext context, WidgetRef ref, int back) {
  final c = context.c;
  final day = dayOf(DateTime.now()).subtract(Duration(days: back));
  final key = st.dateKey(day);
  final t = ref.watch(todayAtProvider(key)).value;
  final title = back == 1 ? 'Yesterday' : dayWeekday(day);
  final header = ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(dayLong(day)),
              const SizedBox(height: 2),
              Text(title, style: TempoType.titleM.c(c.text1)),
            ],
          ),
        ),
        const DayStepper(),
      ],
    ),
  );
  if (t == null) return [header, const SizedBox(height: 240)];
  final p = t.plan;
  final planLine = p == null || p.isRest
      ? 'Rest day'
      : '${p.title} · ${p.minutes} min';
  final status = switch (t.status) {
    sc.DayStatus.done => 'Done ✓',
    sc.DayStatus.doneEasier => 'Done, easier',
    sc.DayStatus.doneHarder => 'Done, harder',
    sc.DayStatus.partial => 'Partly done',
    sc.DayStatus.skipped => 'Skipped',
    sc.DayStatus.rest => 'Rest',
    _ => p == null || p.isRest ? 'Rest' : 'Not done',
  };
  return [
    header,
    // A key per day: the rings draw in again as the day changes.
    TodayRings(key: ValueKey('past-$key'), t: t, noData: false, past: true),
    TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('The plan'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(planLine, style: TempoType.label.c(c.text1)),
              ),
              Text(status, style: TempoType.caption.c(c.text2)),
            ],
          ),
        ],
      ),
    ),
    if (t.workouts.isNotEmpty)
      Section(
        title: 'Workouts',
        child: CardList(
          children: [
            for (final (i, w) in t.workouts.indexed) ...[
              if (i > 0) const Hair(),
              ActivityRow(w: w),
            ],
          ],
        ),
      ),
    CardList(
      children: [
        ListRow(
          'The day, hour by hour',
          sub: 'Heart rate, sleep, steps and workouts',
          onTap: () => push(context, DayTimelineScreen(day: day)),
        ),
      ],
    ),
    TempoButton(
      'Back to today',
      kind: ButtonKind.secondary,
      expand: true,
      onTap: () => ref.read(todayBackProvider.notifier).set(0),
    ),
  ];
}

String dayWeekday(DateTime d) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][d.weekday - 1];

/// Today's win, unless it was put away today.
final momentProvider = FutureProvider<sc.Win?>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final t = await ref.watch(todayProvider.future);
  final now = DateTime.now();
  final win = await CoachNotifier(db).todayWin(t, now);
  if (win == null) return null;
  final seen = await db.setting(Keys.momentSeen);
  return seen == '${st.dateKey(now)}|${win.kind.name}' ? null : win;
});

/// A moment worth a word on Today: a best recovery, a week done, a streak
/// of nights kept, halfway to the goal. Also sent as the win notification;
/// here it stays until put away.
class MomentCard extends ConsumerWidget {
  const MomentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(momentProvider).value;
    if (w == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    return TempoCard(
      label: w.title,
      color: s.tintRecHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TempoIcon(TempoIcons.check, size: 16, color: s.recHigh),
              const SizedBox(width: 8),
              Expanded(child: Overline(_kindWord(w.kind), color: s.recHigh)),
            ],
          ),
          const SizedBox(height: 8),
          Text(w.title, style: TempoType.titleM.c(c.text1).tnum),
          const SizedBox(height: 4),
          Text(w.body, style: TempoType.bodyS.c(c.text2)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TempoButton(
              'Nice',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () {
                TempoHaptics.success();
                ref
                    .read(dbProvider)
                    .putSetting(
                      Keys.momentSeen,
                      '${st.dateKey(DateTime.now())}|${w.kind.name}',
                    );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _kindWord(sc.WinKind k) => switch (k) {
    sc.WinKind.recoveryBest => 'Best in 30 days',
    sc.WinKind.bedtimeStreak => 'Sleep plan kept',
    sc.WinKind.weekDone => 'Week done',
    sc.WinKind.stepStreak => 'Streak',
    sc.WinKind.calibrated => 'Baseline ready',
    sc.WinKind.longest => 'Personal best',
    sc.WinKind.halfway => 'Milestone',
  };
}

/// The answer to the morning rating: feel against recovery, with Replay
/// to draw the rings in again.
class FeelResponse extends ConsumerWidget {
  const FeelResponse({super.key, required this.feel, required this.recovery});
  final int feel;
  final double? recovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            sc.feelResponse(feel, recovery),
            style: TempoType.bodyS.c(c.text1),
          ),
        ),
        const SizedBox(width: 8),
        TempoButton(
          'Replay',
          small: true,
          kind: ButtonKind.text,
          onTap: () => ref.read(ringsReplayProvider.notifier).bump(),
        ),
      ],
    );
  }
}
