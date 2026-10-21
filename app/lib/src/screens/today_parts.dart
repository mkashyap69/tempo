import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/feel.dart';
import '../core/format.dart';
import '../core/journal.dart';
import '../core/pause.dart';
import '../core/profile.dart' show Keys;
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach.dart' show CoachTab, openCoachAt;
import 'coach_parts.dart' show WeekStatusRow, coachExtrasProvider;
import 'everyday_cards.dart';
import 'journal.dart';
import 'learn.dart';
import 'nav.dart';
import 'recovery.dart';
import 'shared.dart';
import 'sleep.dart';

/// Morning check-in: how you feel (before the scores can sway it), then
/// yesterday's journal questions in the same card. Collapses to one line
/// once both are in.
class MorningCheckIn extends ConsumerStatefulWidget {
  const MorningCheckIn({
    super.key,
    required this.day,
    required this.askFeel,
    this.showDone = true,
  });
  final DateTime day;

  /// Keep the one-line "checked in" once both are in (mornings only).
  final bool showDone;

  /// Still before [feelAskUntilHour] and not rated.
  final bool askFeel;

  @override
  ConsumerState<MorningCheckIn> createState() => _MorningCheckInState();
}

class _MorningCheckInState extends ConsumerState<MorningCheckIn> {
  final _draft = <String, bool>{};
  final _amounts = <String, double?>{};

  DateTime get _yesterday => widget.day.subtract(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final j = ref.watch(journalProvider).value;
    final felt = ref.watch(feelProvider(st.dateKey(widget.day))).value;
    final c = context.c;
    final journalOpen = j != null && !j.checkedIn && j.config.asked.isNotEmpty;
    if (!widget.askFeel && !journalOpen) {
      if (!widget.showDone || felt == null && (j == null || !j.checkedIn)) {
        return const SizedBox.shrink();
      }
      return _Done(feel: felt, journal: j?.checkedIn ?? false);
    }
    Widget option(int v) => Expanded(
      child: Pressable(
        label: 'Feel $v of 5: ${sc.feelWords[v - 1]}',
        selected: felt == v,
        onTap: () {
          TempoHaptics.selection();
          ref.read(dbProvider).setFeel(widget.day, v);
        },
        child: Container(
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: felt == v ? c.text1 : null,
            borderRadius: BorderRadius.circular(TempoRadii.md),
            border: Border.all(color: felt == v ? c.text1 : c.lineStrong),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$v',
                  style: TempoType.titleM
                      .c(felt == v ? c.textInverse : c.text1)
                      .tnum,
                ),
                Text(
                  sc.feelWords[v - 1],
                  style: TempoType.caption.c(
                    felt == v ? c.textInverse : c.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final answers = {...?j?.answered, ..._draft};
    final amounts = <String, double?>{...?j?.amounts, ..._amounts};
    final asked = j?.config.asked ?? const <sc.JournalEntryDef>[];
    final dirty = _draft.isNotEmpty || _amounts.isNotEmpty;
    return TempoCard(
      label: 'Morning check-in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Morning check-in')),
              Text('About 20 s', style: TempoType.caption.c(c.text3)),
            ],
          ),
          if (widget.askFeel || felt != null) ...[
            const SizedBox(height: 10),
            Text('How do you feel?', style: TempoType.titleM.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              'Before you look at your scores. Tempo checks whether Recovery matches how you feel.',
              style: TempoType.bodyS.c(c.text2),
            ),
            const SizedBox(height: 14),
            Row(children: [for (var v = 1; v <= 5; v++) option(v)]),
          ],
          if (journalOpen) ...[
            if (widget.askFeel || felt != null) ...[
              const SizedBox(height: 16),
              const Hair(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Yesterday, quickly',
                    style: TempoType.label.c(c.text1),
                  ),
                ),
                TempoButton(
                  'More',
                  kind: ButtonKind.text,
                  small: true,
                  onTap: () =>
                      push(context, const JournalScreen(standalone: true)),
                ),
              ],
            ),
            for (final d in asked)
              JournalEntryRow(
                d,
                answer: answers[d.key],
                amount: amounts[d.key],
                fromHealth: false,
                onAnswer: (v) => setState(() => _draft[d.key] = v),
                onAmount: (v) => setState(() => _amounts[d.key] = v),
              ),
            const SizedBox(height: 12),
            TempoButton(
              'Save check-in',
              expand: true,
              onTap: !dirty
                  ? null
                  : () async {
                      await saveCheckin(
                        ref.read(dbProvider),
                        _yesterday,
                        j.config,
                        answers: {
                          for (final d in asked)
                            if (d.kind == sc.EntryKind.yesNo &&
                                answers[d.key] != null)
                              d.key: answers[d.key]!,
                        },
                        amounts: {
                          for (final d in asked)
                            if (d.kind != sc.EntryKind.yesNo &&
                                amounts.containsKey(d.key))
                              d.key: amounts[d.key],
                        },
                      );
                      setState(() {
                        _draft.clear();
                        _amounts.clear();
                      });
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.feel, required this.journal});
  final int? feel;
  final bool journal;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final parts = [
      if (feel != null) 'feeling ${sc.feelWords[feel! - 1].toLowerCase()}',
      if (journal) 'journal saved',
    ];
    return TempoCard(
      label: 'Checked in',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => push(context, const JournalScreen(standalone: true)),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: s.recHigh.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: TempoIcon(TempoIcons.check, size: 15, color: s.recHigh),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Checked in · ${parts.join(' · ')}',
              style: TempoType.bodyS.c(c.text2),
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}

/// The call: one sentence, the reason on tap, and a quieter second line
/// when the number and the call differ.
class CallLine extends StatelessWidget {
  const CallLine({
    super.key,
    required this.t,
    required this.noData,
    this.health = false,
    this.onWhy,
  });
  final TodayData t;
  final bool noData, health;
  final VoidCallback? onWhy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final call = callFor(t, noData: noData, health: health);
    return Pressable(
      label: 'Why today’s call',
      onTap: onWhy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: call.lead,
                  style: TextStyle(color: callColor(context, call.tone)),
                ),
                TextSpan(text: call.rest),
              ],
            ),
            style: TempoType.titleM.c(c.text1),
          ),
          if (call.note != null) ...[
            const SizedBox(height: 6),
            Text(call.note!, style: TempoType.bodyS.c(c.text2)),
          ],
        ],
      ),
    );
  }
}

/// Opens the "not today" sheet: pause the plan for illness or travel.
Future<void> showPauseSheet(BuildContext context) => showTempoSheet<void>(
  context,
  builder: (ctx) => PauseSheet(onDone: () => Navigator.pop(ctx)),
);

/// "Not today?" in a sheet: why, then pause. Closing the sheet is the
/// "no".
class PauseSheet extends ConsumerStatefulWidget {
  const PauseSheet({super.key, this.onDone});

  /// Called once the pause starts.
  final VoidCallback? onDone;
  @override
  ConsumerState<PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends ConsumerState<PauseSheet> {
  var _reason = PauseReason.ill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Not today?', style: TempoType.titleL.c(c.text1)),
        const SizedBox(height: 6),
        Text(
          'Pause the plan. Scores still show; nothing is carried forward or counted as missed, and baselines hold still.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 16),
        TempoSegmented<PauseReason>(
          values: PauseReason.values,
          labels: [for (final r in PauseReason.values) pauseLabel(r)],
          selected: _reason,
          onChanged: (r) => setState(() => _reason = r),
        ),
        const SizedBox(height: 16),
        TempoButton(
          'Pause the plan',
          expand: true,
          onTap: () async {
            await startPause(ref.read(dbProvider), _reason);
            ref.invalidate(todayProvider);
            widget.onDone?.call();
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A quiet link to [showPauseSheet], under the call on a rest day.
class PauseLink extends StatelessWidget {
  const PauseLink({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TempoButton(
      'Not feeling well? Pause the plan',
      kind: ButtonKind.text,
      small: true,
      onTap: () => showPauseSheet(context),
    ),
  );
}

/// Day progress: strain against today's target, then movement.
class DayProgress extends StatelessWidget {
  const DayProgress({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final adds = planAdds(t);
    final (word, line) = strainStatus(t, planAdds: adds > 0 ? adds : null);
    final plain = plainWords(t.profile);
    final tg = t.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TempoCard(
          label: 'Your day so far',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Overline('Your day so far'),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      plain ? 'Effort' : 'Strain',
                      style: TempoType.body.c(c.text1),
                    ),
                  ),
                  Text(n1(t.strain), style: TempoType.label.c(c.text1).tnum),
                  Text(
                    tg.cap
                        ? ' · cap ${tg.hi.round()}'
                        : ' · target ${tg.lo.round()}–${tg.hi.round()}',
                    style: TempoType.bodyS.c(c.text2).tnum,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TargetStrip(
                value: t.strain,
                max: 21,
                lo: tg.cap ? null : tg.lo,
                hi: tg.hi,
                color: s.strain[2],
              ),
              const SizedBox(height: 8),
              Text('$word · $line', style: TempoType.caption.c(c.text2)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const MovementCard(),
      ],
    );
  }
}

/// What Tempo is still learning in the first weeks, and what each unlocks.
class LearningCard extends StatelessWidget {
  const LearningCard({super.key, required this.t, this.checkins = 0});
  final TodayData t;
  final int checkins;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final rows = [
      (
        'Sleep score',
        t.everSlept ? 1 : 0,
        1,
        'night',
        'Ready from your first night',
      ),
      (
        'Personal recovery',
        t.nights,
        14,
        'nights',
        'Scores against your own normal',
      ),
      (
        'Body signals',
        t.nights,
        sc.signalMinNights,
        'nights',
        'Warns when night signals move the wrong way together',
      ),
      (
        'Cardio load',
        t.load.chronicDays,
        sc.loadMinDays,
        'worn days',
        'Says if you’re building, holding or overdoing it',
      ),
      (
        'Journal insights',
        checkins,
        journalInsightsAt,
        'check-ins',
        'Shows what your habits do to your sleep and recovery',
      ),
    ];
    final ready = rows.where((r) => r.$2 >= r.$3).length;
    return TempoCard(
      label: 'What Tempo is learning',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('What Tempo is learning')),
              Text(
                '$ready of ${rows.length} ready',
                style: TempoType.caption.c(c.text3).tnum,
              ),
            ],
          ),
          for (final (name, have, need, unit, unlocks) in rows) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text(name, style: TempoType.body.c(c.text1))),
                Text(
                  have >= need ? 'Ready' : '$have of $need $unit',
                  style: TempoType.bodyS
                      .c(have >= need ? s.recHigh : c.text2)
                      .tnum,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (have / need).clamp(0, 1).toDouble(),
                backgroundColor: c.trackOff,
                color: have >= need ? s.recHigh : c.text2,
              ),
            ),
            const SizedBox(height: 4),
            Text(unlocks, style: TempoType.caption.c(c.text3)),
          ],
        ],
      ),
    );
  }
}

/// One lesson a day in the first two weeks (Learn's six cards).
class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = learnItems(context, t);
    final i = ((t.nights - 1).clamp(0, 13) ~/ 2) % items.length;
    final it = items[i];
    return TempoCard(
      label: 'Lesson: ${it.title}',
      onTap: () => push(context, LearnCardsScreen(initial: i)),
      child: Row(
        children: [
          TempoIcon(it.icon, size: 22, color: it.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Overline('Lesson ${i + 1} of ${items.length} · 1 min'),
                const SizedBox(height: 4),
                Text(it.title, style: TempoType.titleM.c(c.text1)),
                const SizedBox(height: 2),
                Text(it.sub, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 18, color: c.text3, stroke: 2),
        ],
      ),
    );
  }
}

/// Night 14: recovery is now personal. Shown once.
class GraduationCard extends ConsumerWidget {
  const GraduationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    final db = ref.read(dbProvider);
    return TempoCard(
      color: s.tintRecHigh,
      label: 'Your recovery is now personal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline('14 nights', color: s.recHigh),
          const SizedBox(height: 10),
          Text(
            'Your recovery is now personal',
            style: TempoType.titleL.c(c.text1),
          ),
          const SizedBox(height: 6),
          Text(
            'Every score is now measured against your own 14-night normal, and the plan adapts to you.',
            style: TempoType.body.c(c.text2),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TempoButton(
                  'See today’s recovery',
                  expand: true,
                  onTap: () async {
                    await db.putSetting(Keys.graduated, '1');
                    if (context.mounted) {
                      await push(context, const RecoveryScreen());
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              TempoButton(
                'Got it',
                kind: ButtonKind.ghost,
                onTap: () => db.putSetting(Keys.graduated, '1'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Back after days without data: no guilt, a gentle restart.
class WelcomeBackCard extends StatelessWidget {
  const WelcomeBackCard({super.key, required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      label: 'Welcome back',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Welcome back'),
          const SizedBox(height: 8),
          Text('You were away $days days', style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            'Your baselines are still yours. Take this week gently: the plan picks up from where your body is now.',
            style: TempoType.bodyS.c(c.text2),
          ),
        ],
      ),
    );
  }
}

/// Days since the last scored day before today, when 5 or more.
int? daysAway(TodayData t) {
  final last = t.history.where((d) => d.strain > 0 || d.sleptHours != null);
  if (last.isEmpty) return null;
  final gap = t.day.difference(DateTime.parse(last.first.date)).inDays - 1;
  return gap >= 5 ? gap : null;
}

/// This week's days at a glance; opens Plan.
class WeekRow extends ConsumerWidget {
  const WeekRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final x = ref.watch(coachExtrasProvider).value;
    if (x == null) return const SizedBox.shrink();
    final c = context.c;
    return TempoCard(
      label: 'This week',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: () => openCoachAt(context, CoachTab.week),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: TempoType.caption.c(c.text3),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                WeekStatusRow(x.week),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}

/// Tomorrow's session in one line; opens Plan.
class TomorrowRow extends StatelessWidget {
  const TomorrowRow({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final key = st.dateKey(t.day.add(const Duration(days: 1)));
    final row = t.week.where((r) => r.date == key).firstOrNull;
    if (row == null) return const SizedBox.shrink();
    final s = sc.Session.fromJson(
      jsonDecode(row.session) as Map<String, dynamic>,
    );
    return TempoCard(
      label: 'Tomorrow',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => openCoachAt(context, CoachTab.week),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.isRest
                      ? 'Tomorrow · rest'
                      : 'Tomorrow · ${s.title} ${s.minutes} min',
                  style: TempoType.label.c(c.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  'Adapts to tonight’s sleep in the morning',
                  style: TempoType.caption.c(c.text2),
                ),
              ],
            ),
          ),
          Text('Week ›', style: TempoType.bodyS.c(c.text2)),
        ],
      ),
    );
  }
}

/// The evening's summary line: what the day added up to.
class TodayInOneLine extends StatelessWidget {
  const TodayInOneLine({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tg = t.target;
    final inRange = !tg.general && t.strain >= tg.lo && t.strain <= tg.hi;
    final done =
        t.status == sc.DayStatus.done || t.status == sc.DayStatus.doneEasier;
    final parts = [
      if (done && t.plan != null) '${t.plan!.title} done',
      'strain ${n1(t.strain)}${tg.general
          ? ''
          : inRange
          ? ', in range'
          : t.strain > tg.hi
          ? ', above range'
          : ', under range'}',
      if (t.workouts.isNotEmpty)
        '${t.workouts.length} ${t.workouts.length == 1 ? 'workout' : 'workouts'}',
    ];
    final line = parts.join(' · ');
    return TempoCard(
      label: 'Today in one line',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Today in one line'),
          const SizedBox(height: 8),
          Text(
            '${line[0].toUpperCase()}${line.substring(1)}.',
            style: TempoType.body.c(c.text1).tnum,
          ),
        ],
      ),
    );
  }
}

/// Bedtime in one line, for the hours before the evening.
class TonightLine extends StatelessWidget {
  const TonightLine({super.key, required this.t});
  final TodayData t;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return TempoCard(
      label: 'Tonight',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => push(context, const SleepScreen()),
      child: Row(
        children: [
          TempoIcon(TempoIcons.sleep, size: 18, color: s.sleepChannel),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tonight · need ${hmShort(t.needTonight)} · bed by ${clock12(t.bedtimeMinute)}',
              style: TempoType.bodyS.c(c.text1).tnum,
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}
