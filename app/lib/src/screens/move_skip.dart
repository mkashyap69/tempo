import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/home_widgets.dart' show rescheduleNotifications;
import '../core/pause.dart';
import '../core/profile.dart';
import '../core/skip_reasons.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach.dart' show WeekView, weekProvider;

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The reason given when a day's session was skipped or moved (date key).
final skipReasonProvider = FutureProvider.family<SkipReason?, String>((
  ref,
  key,
) {
  ref.watch(dbTickProvider);
  return loadSkipReason(ref.watch(dbProvider), DateTime.parse(key));
});

/// Move or skip [day]'s session in one sheet: why (optional), the coach's
/// note for that reason, then the ways forward it suggests: move to a day
/// that keeps hard days apart, skip, skip and ease the week (sore), or
/// pause the plan (ill, travelling).
Future<void> showMoveOrSkipSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  final host = Navigator.of(context).context;
  final db = ref.read(dbProvider);
  final w = await ref.read(weekProvider.future);
  final prof = await loadAppProfile(db) ?? const Profile();
  if (!context.mounted) return;
  final from = day.weekday - 1;
  final today = DateTime.now().weekday - 1;
  final week = [for (var i = 0; i < 7; i++) w.session(i)];
  final targets = sc.moveTargets(
    week,
    from,
    today: today,
    available: prof.days,
  );
  await showTempoSheet<void>(
    context,
    builder: (ctx) => _MoveOrSkip(
      w: w,
      week: week,
      from: from,
      today: today,
      day: day,
      targets: targets,
      host: host,
    ),
  );
}

class _MoveOrSkip extends ConsumerStatefulWidget {
  const _MoveOrSkip({
    required this.w,
    required this.week,
    required this.from,
    required this.today,
    required this.day,
    required this.targets,
    required this.host,
  });
  final WeekView w;
  final List<sc.Session> week;
  final int from, today;
  final DateTime day;
  final List<int> targets;
  final BuildContext host;

  @override
  ConsumerState<_MoveOrSkip> createState() => _MoveOrSkipState();
}

class _MoveOrSkipState extends ConsumerState<_MoveOrSkip> {
  SkipReason? _why;

  Future<void> _changed() async {
    HapticFeedback.selectionClick();
    await rescheduleNotifications(ref.read(dbProvider));
  }

  void _toast(String text, {Future<void> Function()? undo}) {
    final host = widget.host;
    if (!host.mounted) return;
    showTempoToast(
      host,
      text,
      action: undo == null ? null : 'Undo',
      onAction: undo == null
          ? null
          : () async {
              await undo();
              await _changed();
            },
    );
  }

  Future<void> _move(int j) async {
    final db = ref.read(dbProvider);
    final w = widget.w, s = widget.week[widget.from];
    await CoachService(db).moveDay(widget.day, w.date(j));
    await saveSkipReason(db, widget.day, _why);
    await _changed();
    if (mounted) Navigator.pop(context);
    _toast(
      '${s.title} moved to ${_dayNames[j]}',
      undo: () async {
        await CoachService(db).moveDay(w.date(j), widget.day);
        await saveSkipReason(db, widget.day, null);
      },
    );
  }

  Future<void> _skip({bool ease = false}) async {
    final db = ref.read(dbProvider);
    final coach = CoachService(db);
    await coach.setIntent(widget.day, sc.Intent.skipped);
    await saveSkipReason(db, widget.day, _why);
    final eased = ease ? await easeRestOfWeek(db, widget.day) : const <int>[];
    await _changed();
    if (mounted) Navigator.pop(context);
    _toast(
      eased.isEmpty
          ? skippedLine(_why)
          : 'Skipped. ${eased.map((i) => _dayNames[i]).join(', ')} '
                '${eased.length == 1 ? 'is' : 'are'} easier now.',
      // Easing rewrites later days; undo the skip only, the easier days
      // stay (each shows what it was).
      undo: () async {
        await coach.setIntent(widget.day, sc.Intent.planned);
        await saveSkipReason(db, widget.day, null);
      },
    );
  }

  Future<void> _pause(PauseReason r) async {
    final db = ref.read(dbProvider);
    await startPause(db, r);
    await saveSkipReason(db, widget.day, _why);
    ref.invalidate(todayProvider);
    await _changed();
    if (mounted) Navigator.pop(context);
    _toast('Plan paused · ${pauseLabel(r).toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.week[widget.from];
    final isToday = widget.from == widget.today;
    final dayWord = isToday ? 'today' : _dayNames[widget.from];
    final why = _why;
    final pause = switch (why) {
      SkipReason.ill => PauseReason.ill,
      SkipReason.travel => PauseReason.travel,
      _ => null,
    };
    final moveFirst = why == SkipReason.busy || why == SkipReason.tired;
    final showMove = why != SkipReason.ill;

    Widget option(
      String title,
      String body,
      VoidCallback onTap, {
      bool suggested = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TempoCard(
        onTap: onTap,
        label: title,
        color: c.surface1,
        border: suggested ? c.text1 : c.line,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: TempoType.label.c(c.text1))),
                if (suggested)
                  TempoBadge('Suggested', color: context.s.recHigh),
              ],
            ),
            const SizedBox(height: 4),
            Text(body, style: TempoType.bodyS.c(c.text2)),
          ],
        ),
      ),
    );

    final moves = <Widget>[
      if (showMove) ...[
        const SizedBox(height: 16),
        const Overline('Move to'),
        if (widget.targets.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No other day this week takes it without two hard days in a '
              'row.',
              style: TempoType.bodyS.c(c.text2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CardList(
              children: [
                for (final j in widget.targets)
                  ListRow(
                    '${_dayNames[j]} ${widget.w.date(j).day}'
                    '${j == widget.today ? ' · today' : ''}',
                    sub: widget.week[j].isRest
                        ? 'A rest day now; rest moves to ${_dayNames[widget.from]}'
                        : 'Swaps with ${widget.week[j].title.toLowerCase()} · '
                              '${widget.week[j].minutes} min',
                    onTap: () => _move(j),
                  ),
              ],
            ),
          ),
      ],
    ];
    final skips = <Widget>[
      const SizedBox(height: 16),
      const Overline('Or'),
      if (pause != null)
        option(
          'Pause the plan · ${pauseLabel(pause).toLowerCase()}',
          'Scores still show. Nothing counts as missed and baselines hold '
              'still until you resume.',
          () => _pause(pause),
          suggested: true,
        ),
      if (why == SkipReason.sore)
        option(
          'Skip and ease the week',
          'Hard sessions left this week become their easier version; long '
              'ones lose a quarter.',
          () => _skip(ease: true),
          suggested: true,
        ),
      option(
        'Skip $dayWord',
        'Let it go. Nothing is added to catch up.',
        _skip,
        suggested: why == SkipReason.notToday,
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Move or skip ${s.title.toLowerCase()}',
          style: TempoType.titleM.c(c.text1),
        ),
        const SizedBox(height: 2),
        Text(
          '${isToday ? 'Today' : _dayNames[widget.from]} · ${s.minutes} min',
          style: TempoType.caption.c(c.text3).tnum,
        ),
        const SizedBox(height: 14),
        Text('What’s up? (optional)', style: TempoType.label.c(c.text1)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in SkipReason.values)
              TempoChip(
                skipReasonLabel(r),
                height: 40,
                selected: why == r,
                onTap: () => setState(() => _why = why == r ? null : r),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: context.reduceMotion ? Duration.zero : TempoMotion.fast,
          child: Container(
            key: ValueKey(why),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface1,
              borderRadius: BorderRadius.circular(TempoRadii.md),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Coach: ',
                    style: TempoType.bodyS.c(c.text1).w500,
                  ),
                  TextSpan(text: skipReasonNote(why)),
                ],
              ),
              style: TempoType.bodyS.c(c.text2),
            ),
          ),
        ),
        if (moveFirst) ...[...moves, ...skips] else ...[...skips, ...moves],
        const SizedBox(height: 12),
        TempoButton(
          'Keep it',
          kind: ButtonKind.ghost,
          expand: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
