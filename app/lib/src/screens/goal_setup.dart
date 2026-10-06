import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/block_service.dart';
import '../core/coach_service.dart' show dayOf, mondayOf;
import '../core/format.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'goal.dart';
import 'longevity.dart' show LongevityScreen;
import 'nav.dart';

enum SetupMode { newGoal, changeDate, tuneUp, next }

/// What setup saved: the goal it replaced (for undo), or that it cleared.
final class GoalSetupResult {
  const GoalSetupResult({this.before, this.cleared = false});
  final String? before;
  final bool cleared;
}

String goalBlurb(sc.BlockGoal g) => switch (g) {
  sc.BlockGoal.run5k => 'Sharpen speed. Intervals in the peak weeks.',
  sc.BlockGoal.run10k => 'Speed plus a longer aerobic base.',
  sc.BlockGoal.half => 'Long runs build to about 1 h 50 m.',
  sc.BlockGoal.marathon => 'Long runs build to about 2 h 40 m.',
  sc.BlockGoal.open =>
    'No date. Keeps building, with a lighter week every 4th.',
};

String goalTypical(sc.BlockGoal g) => switch (g) {
  sc.BlockGoal.run5k => '6–10 weeks',
  sc.BlockGoal.run10k => '8–12 weeks',
  sc.BlockGoal.half => '10–16 weeks',
  sc.BlockGoal.marathon => '16–24 weeks',
  sc.BlockGoal.open => 'Open-ended',
};

const _events = [
  sc.BlockGoal.run5k,
  sc.BlockGoal.run10k,
  sc.BlockGoal.half,
  sc.BlockGoal.marathon,
];

/// Setting a goal in three steps (goal, race day, preview), or one part of
/// it: moving the race, adding a tune-up race, queueing the next goal.
class GoalSetupScreen extends ConsumerStatefulWidget {
  const GoalSetupScreen({super.key, required this.mode, this.block});
  final SetupMode mode;

  /// The current goal (needed for every mode but [SetupMode.newGoal]).
  final sc.TrainingBlock? block;

  @override
  ConsumerState<GoalSetupScreen> createState() => _GoalSetupState();
}

class _GoalSetupState extends ConsumerState<GoalSetupScreen> {
  late int _step = widget.mode == SetupMode.changeDate ? 1 : 0;

  /// null = no goal (only offered when setting a new goal).
  sc.BlockGoal? _goal;
  bool _none = false;
  DateTime? _date;
  DateTime? _month;
  bool _busy = false;

  sc.TrainingBlock? get _b => widget.block;
  DateTime get _today => dayOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    switch (widget.mode) {
      case SetupMode.newGoal:
        _goal = _b?.goal ?? sc.BlockGoal.half;
      case SetupMode.changeDate:
        _goal = _b!.goal;
        _date = _b!.event;
      case SetupMode.tuneUp:
        _goal = sc.BlockGoal.run10k;
      case SetupMode.next:
        _goal = sc.BlockGoal.half;
    }
  }

  /// Monday the block being set up starts.
  DateTime get _start => switch (widget.mode) {
    SetupMode.newGoal => mondayOf(_today),
    SetupMode.changeDate => _b!.start,
    SetupMode.tuneUp => _b!.start,
    SetupMode.next => sc.nextBlockStart(_b!)!,
  };

  List<sc.BlockGoal> get _options => switch (widget.mode) {
    SetupMode.newGoal => [..._events, sc.BlockGoal.open],
    SetupMode.next => _events,
    SetupMode.tuneUp => [
      for (final g in _events)
        if (_b!.goal == sc.BlockGoal.open || g.index < _b!.goal.index) g,
    ],
    SetupMode.changeDate => [_b!.goal],
  };

  /// Whether [d] can be the race (or tune-up) day.
  bool _ok(DateTime d) {
    if (d.isBefore(_today)) return false;
    if (widget.mode == SetupMode.tuneUp) {
      return sc.tuneUpProblem(_b!, d) == null;
    }
    final n = sc.eventWeeks(_start, d);
    if (n < sc.blockMinWeeks || n > sc.blockMaxWeeks) return false;
    if (widget.mode == SetupMode.changeDate) {
      return _b!.weekOf(d) > _b!.weekOf(_today);
    }
    return true;
  }

  bool _short(DateTime d) =>
      widget.mode != SetupMode.tuneUp &&
      sc.eventWeeks(_start, d) < sc.recommendedWeeks(_goal!);

  (DateTime, DateTime) get _range {
    final from = widget.mode == SetupMode.tuneUp ? _today : _start;
    final to = widget.mode == SetupMode.tuneUp && _b!.isEvent
        ? _b!.event!
        : _start.add(const Duration(days: 7 * sc.blockMaxWeeks));
    return (from, to);
  }

  DateTime _initialMonth() {
    final d =
        _date ??
        (widget.mode == SetupMode.tuneUp
            ? _today.add(const Duration(days: 21))
            : _start.add(Duration(days: 7 * sc.recommendedWeeks(_goal!) - 1)));
    return DateTime(d.year, d.month);
  }

  String get _title => switch (widget.mode) {
    SetupMode.newGoal => 'Training goal',
    SetupMode.changeDate => 'Race date',
    SetupMode.tuneUp => 'Tune-up race',
    SetupMode.next => 'Next goal',
  };

  int get _steps => switch (widget.mode) {
    SetupMode.newGoal => 3,
    SetupMode.changeDate => 2,
    SetupMode.tuneUp => 2,
    SetupMode.next => 3,
  };

  int get _shown => widget.mode == SetupMode.changeDate ? _step - 1 : _step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoPage(
      gap: 16,
      footer: _footer(),
      children: [
        DetailHeader(
          title: _title,
          leadingIcon: TempoIcons.close,
          onBack: () => Navigator.pop(context),
        ),
        Row(
          children: [
            for (var i = 0; i < _steps; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= _shown ? c.text1 : c.trackOff,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        ...switch (_step) {
          0 => _goalStep(),
          1 => _dateStep(),
          _ => _previewStep(),
        },
      ],
    );
  }

  Widget _heading(String over, String title, [String? sub]) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Overline(over),
        const SizedBox(height: 6),
        Text(title, style: TempoType.titleL.c(c.text1)),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub, style: TempoType.bodyS.c(c.text2)),
        ],
      ],
    );
  }

  String get _stepLabel => 'Step ${_shown + 1} of $_steps';

  List<Widget> _goalStep() => [
    _heading(
      _stepLabel,
      switch (widget.mode) {
        SetupMode.tuneUp => 'Which race?',
        SetupMode.next => 'What comes next?',
        _ => 'What are you training for?',
      },
      switch (widget.mode) {
        SetupMode.tuneUp =>
          'A shorter race before the ${sc.goalName(_b!.goal).toLowerCase()}. '
              'It replaces that week\'s hard session.',
        SetupMode.next =>
          'It starts after the ${sc.goalName(_b!.goal).toLowerCase()} and a '
              'recovery week. Nothing changes until then.',
        _ =>
          'One goal leads the plan. You can add tune-up races and the '
              'next goal later.',
      },
    ),
    for (final g in _options)
      _Option(
        title: sc.goalName(g),
        meta: widget.mode == SetupMode.tuneUp ? null : goalTypical(g),
        body: widget.mode == SetupMode.tuneUp ? null : goalBlurb(g),
        selected: !_none && _goal == g,
        onTap: () => setState(() {
          _goal = g;
          _none = false;
          _date = null;
        }),
      ),
    if (widget.mode == SetupMode.newGoal)
      _Option(
        title: 'No goal',
        body: 'The same week every week, built from your days and recovery.',
        selected: _none,
        onTap: () => setState(() {
          _none = true;
          _date = null;
        }),
      ),
  ];

  List<Widget> _dateStep() {
    final c = context.c;
    final g = _goal!;
    final (from, to) = _range;
    _month ??= _initialMonth();
    final d = _date;
    Widget note;
    if (widget.mode == SetupMode.tuneUp) {
      note = _Note(
        tone: Tone.good,
        text: d == null
            ? 'Pick a day inside the block, at least 2 weeks before the '
                  '${sc.goalName(_b!.goal).toLowerCase()} and not in a week '
                  'that already has a tune-up.'
            : '${dayShort(d)} · week ${_b!.weekOf(d) + 1}. The two days before '
                  'are easy and the day after is rest.',
      );
    } else if (d == null) {
      note = _Note(
        tone: Tone.good,
        text:
            'Pick the day of the race. ${sc.goalName(g)}s usually need '
            '${goalTypical(g)}; dates in amber are shorter than that.',
      );
    } else {
      final n = sc.eventWeeks(_start, d);
      note = n < sc.recommendedWeeks(g)
          ? _Note(
              tone: Tone.mid,
              text:
                  '$n weeks is short for a ${sc.goalName(g).toLowerCase()}. '
                  'The plan skips most of the base and the long run tops out '
                  'lower. Fine if you already run regularly.',
            )
          : _Note(
              tone: Tone.good,
              text:
                  '${dayShort(d)} · $n weeks. Enough time for a full base, '
                  'build, peak and taper.',
            );
    }
    return [
      _heading(
        _stepLabel,
        widget.mode == SetupMode.tuneUp
            ? 'When is the ${sc.goalName(g)}?'
            : 'When is the race?',
        switch (widget.mode) {
          SetupMode.newGoal =>
            '${sc.goalName(g)} · the plan starts this week (${dm(_start)})',
          SetupMode.changeDate =>
            'The block keeps its start (${dm(_start)}) and tune-ups that '
                'still fit.',
          SetupMode.next =>
            '${sc.goalName(g)} · starts ${dm(_start)}, after a recovery week',
          SetupMode.tuneUp => null,
        },
      ),
      MonthCalendar(
        month: _month!,
        first: from,
        last: to,
        selected: d,
        enabled: _ok,
        warn: _short,
        onMonth: (m) => setState(() => _month = m),
        onPick: (x) => setState(() => _date = x),
      ),
      note,
      if (widget.mode == SetupMode.changeDate && d != null)
        Text(
          'Moving the race re-times every phase. Weeks already done keep '
          'their history.',
          style: TempoType.caption.c(c.text3),
        ),
    ];
  }

  sc.TrainingBlock get _preview => sc.TrainingBlock(
    goal: _goal!,
    start: _start,
    event: _goal == sc.BlockGoal.open ? null : _date,
    tuneUps: widget.mode == SetupMode.changeDate ? _b!.tuneUps : const [],
  );

  List<Widget> _previewStep() {
    final c = context.c;
    final b = _preview;
    final weeks = sc.projectBlock(b, -1, const [], ahead: 11);
    final counts = <sc.Phase, int>{};
    for (final w in weeks) {
      counts[w.phase] = (counts[w.phase] ?? 0) + 1;
    }
    final biggest = weeks.reduce((a, x) => x.volume > a.volume ? x : a);
    return [
      _heading(
        _stepLabel,
        b.isEvent ? 'Your ${b.weeks}-week plan' : 'Your first 12 weeks',
        b.isEvent
            ? '${sc.goalName(b.goal)} · ${dayShort(b.event!)}'
            : 'Get fitter · keeps going after week 12',
      ),
      TempoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlockTimeline(weeks: weeks, current: -1, height: 72),
            const SizedBox(height: 12),
            for (final p in sc.Phase.values)
              if (counts[p] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: phaseColor(context, p),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sc.phaseName(p),
                          style: TempoType.bodyS.c(c.text1),
                        ),
                      ),
                      Text(
                        counts[p] == 1 ? '1 week' : '${counts[p]} weeks',
                        style: TempoType.bodyS.c(c.text2).tnum,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      TempoCard(
        child: Text(
          'If every week goes well, your biggest week is week '
          '${biggest.index + 1}, with sessions ${volumeLine(biggest.volume)} '
          'and long runs up to ${sc.longCapMinutes(b.goal)} min. Weeks you '
          'miss or find hard hold the plan where it is.'
          '${widget.mode == SetupMode.newGoal ? '\n\nThis week\'s plan is rebuilt from today. Sessions already done stay done.' : ''}',
          style: TempoType.bodyS.c(c.text2),
        ),
      ),
    ];
  }

  Widget _footer() {
    final last = _step == 2 || (widget.mode == SetupMode.tuneUp && _step == 1);
    final canNext = switch (_step) {
      0 => _none || _goal != null,
      1 => _date != null,
      _ => true,
    };
    final label = switch (_step) {
      0 when _none => 'Use the same week every week',
      0 when _goal == sc.BlockGoal.open => 'Preview plan',
      0 =>
        widget.mode == SetupMode.tuneUp ? 'Choose race day' : 'Choose race day',
      1 when last => 'Add tune-up',
      1 => 'Preview plan',
      _ => switch (widget.mode) {
        SetupMode.newGoal => 'Start plan',
        SetupMode.changeDate => 'Move the race',
        SetupMode.next => 'Queue it',
        SetupMode.tuneUp => 'Add tune-up',
      },
    };
    final firstStep = widget.mode == SetupMode.changeDate ? 1 : 0;
    return Row(
      children: [
        if (_step > firstStep) ...[
          Expanded(
            child: TempoButton(
              'Back',
              kind: ButtonKind.secondary,
              expand: true,
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _step = _step == 2 && _goal == sc.BlockGoal.open
                          ? 0
                          : _step - 1;
                    }),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: TempoButton(
            label,
            expand: true,
            onTap: !canNext || _busy ? null : () => _advance(last),
          ),
        ),
      ],
    );
  }

  Future<void> _advance(bool last) async {
    if (_step == 0) {
      if (_none) return _finish();
      setState(() {
        _step = _goal == sc.BlockGoal.open ? 2 : 1;
        _month = null;
      });
      return;
    }
    if (!last) {
      setState(() => _step = 2);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final db = ref.read(dbProvider);
    GoalSetupResult result;
    switch (widget.mode) {
      case SetupMode.newGoal:
        final before = await saveBlock(
          db,
          _none ? null : _goal,
          event: _none || _goal == sc.BlockGoal.open ? null : _date,
        );
        result = GoalSetupResult(before: before, cleared: _none);
      case SetupMode.changeDate:
        await changeEvent(db, _date!);
        result = const GoalSetupResult();
      case SetupMode.tuneUp:
        await addTuneUp(db, sc.TuneUp(goal: _goal!, date: _date!));
        result = const GoalSetupResult();
      case SetupMode.next:
        await saveNext(db, NextGoal(_goal!, _date!));
        result = const GoalSetupResult();
    }
    if (mounted) Navigator.pop(context, result);
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.selected,
    required this.onTap,
    this.meta,
    this.body,
  });
  final String title;
  final String? meta, body;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      label: title,
      selected: selected,
      onTap: onTap == null
          ? null
          : () {
              TempoHaptics.selection();
              onTap!();
            },
      child: AnimatedContainer(
        duration: TempoMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(TempoRadii.md),
          border: Border.all(width: 1.5, color: selected ? c.text1 : c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TempoType.label.c(onTap == null ? c.text3 : c.text1),
                  ),
                ),
                if (meta != null)
                  Text(meta!, style: TempoType.caption.c(c.text3)),
              ],
            ),
            if (body != null) ...[
              const SizedBox(height: 2),
              Text(body!, style: TempoType.bodyS.c(c.text2)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.tone, required this.text});
  final Tone tone;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: toneTint(context, tone),
      borderRadius: BorderRadius.circular(TempoRadii.md),
    ),
    child: Text(text, style: TempoType.bodyS.c(context.c.text1).tnum),
  );
}

/// A month of days, Monday first. Days outside [first]..[last] or not
/// [enabled] can't be picked; [warn] days are shown in amber.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.first,
    required this.last,
    required this.enabled,
    required this.onMonth,
    required this.onPick,
    this.warn,
    this.selected,
  });
  final DateTime month, first, last;
  final DateTime? selected;
  final bool Function(DateTime) enabled;
  final bool Function(DateTime)? warn;
  final ValueChanged<DateTime> onMonth, onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final y = month.year, m = month.month;
    final lead = DateTime(y, m).weekday - 1;
    final n = DateTime(y, m + 1, 0).day;
    final canBack = DateTime(y, m).isAfter(DateTime(first.year, first.month));
    final canFwd = DateTime(
      y,
      m + 1,
    ).isBefore(DateTime(last.year, last.month + 1));
    Widget nav(String label, bool on, int dir) => Pressable(
      label: label,
      onTap: on ? () => onMonth(DateTime(y, m + dir)) : null,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
        child: Opacity(
          opacity: on ? 1 : .35,
          child: Transform.rotate(
            angle: dir < 0 ? 3.14159 : 0,
            child: TempoIcon(
              TempoIcons.chevron,
              size: 16,
              color: c.text1,
              stroke: 2,
            ),
          ),
        ),
      ),
    );
    return TempoCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              nav('Previous month', canBack, -1),
              Expanded(
                child: Text(
                  DateFormat('MMMM y').format(month),
                  textAlign: TextAlign.center,
                  style: TempoType.label.c(c.text1),
                ),
              ),
              nav('Next month', canFwd, 1),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in 'MTWTFSS'.split(''))
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
          for (var row = 0; row * 7 < lead + n; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = row * 7 + col - lead + 1;
                        if (day < 1 || day > n) {
                          return const SizedBox(height: 40);
                        }
                        final date = DateTime(y, m, day);
                        final on = enabled(date);
                        final pick =
                            selected != null &&
                            DateUtils.isSameDay(selected, date);
                        final amber = on && (warn?.call(date) ?? false);
                        return Pressable(
                          label: dayShort(date),
                          selected: pick,
                          onTap: on
                              ? () {
                                  TempoHaptics.selection();
                                  onPick(date);
                                }
                              : null,
                          child: Container(
                            height: 40,
                            margin: const EdgeInsets.all(1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: pick ? c.text1 : null,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$day',
                              style: TempoType.bodyS
                                  .copyWith(
                                    fontWeight: pick ? FontWeight.w600 : null,
                                  )
                                  .c(
                                    pick
                                        ? c.textInverse
                                        : !on
                                        ? c.text3.withValues(alpha: .45)
                                        : amber
                                        ? s.recMid
                                        : c.text1,
                                  )
                                  .tnum,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One goal leads; everything else is added as a kind that can't fight it.
Future<void> showAddToPlan(
  BuildContext context,
  WidgetRef ref,
  GoalView v,
) async {
  final b = v.block;
  final canNext = b.isEvent;
  final pick = await showTempoSheet<String>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline('${sc.goalName(b.goal)} is your main goal'),
          const SizedBox(height: 6),
          Text('Add to your plan', style: TempoType.titleL.c(c.text1)),
          const SizedBox(height: 16),
          _Option(
            title: 'A tune-up race',
            meta: 'Inside this block',
            body:
                'A shorter race before the main one. It replaces that week\'s '
                'hard session.',
            selected: false,
            onTap: b.tuneUps.length >= sc.tuneUpMax
                ? null
                : () => Navigator.pop(ctx, 'tune'),
          ),
          const SizedBox(height: 8),
          _Option(
            title: v.next == null ? 'The next goal' : 'Change the next goal',
            meta: 'After this one',
            body: canNext
                ? 'Queued to start after this race and a recovery week.'
                : 'Needs a race goal to follow. With Get fitter, switch goal '
                      'instead.',
            selected: false,
            onTap: canNext ? () => Navigator.pop(ctx, 'next') : null,
          ),
          const SizedBox(height: 8),
          _Option(
            title: 'A habit alongside',
            meta: 'Every week',
            body:
                'Strength, steps or sleep from Tempo Age. It fits on easy and '
                'rest days and never takes a hard day.',
            selected: false,
            onTap: () => Navigator.pop(ctx, 'habit'),
          ),
          const SizedBox(height: 8),
          const _Option(
            title: 'A second main goal now',
            meta: 'Not offered',
            body:
                'Two plans pulling at once means neither gets a proper build or '
                'taper. Switch goal instead.',
            selected: false,
            onTap: null,
          ),
        ],
      );
    },
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case 'tune':
      await present<GoalSetupResult>(
        context,
        GoalSetupScreen(mode: SetupMode.tuneUp, block: b),
      );
    case 'next':
      await present<GoalSetupResult>(
        context,
        GoalSetupScreen(mode: SetupMode.next, block: b),
      );
    case 'habit':
      await push(context, const LongevityScreen());
  }
}
