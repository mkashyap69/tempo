import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/block_service.dart';
import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/home_widgets.dart' show rescheduleNotifications;
import '../core/profile.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart' show IntervalBars;
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach.dart' show WeekView, weekProvider;
import 'coach_parts.dart' show coachExtrasProvider, statusColor, statusLabel;
import 'goal.dart';
import 'nav.dart';
import 'workout_detail.dart';

/// This week's days with what each earned (done, done easier, not yet).
final weekDaysProvider = dbQuery<List<DayCredit>>(
  (db, ref) => weekCredits(db, mondayOf(DateTime.now())),
);

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> _changed(WidgetRef ref) async {
  HapticFeedback.selectionClick();
  await rescheduleNotifications(ref.read(dbProvider));
}

/// Skips [day] with a toast that undoes it.
Future<void> _skip(BuildContext context, WidgetRef ref, DateTime day) async {
  // The row that was tapped may be rebuilt away; toast from the navigator.
  final host = Navigator.of(context).context;
  final coach = CoachService(ref.read(dbProvider));
  await coach.setIntent(day, sc.Intent.skipped);
  await _changed(ref);
  if (host.mounted) {
    showTempoToast(
      host,
      'Skipped. Nothing to make up.',
      action: 'Undo',
      onAction: () async {
        await coach.setIntent(day, sc.Intent.planned);
        await _changed(ref);
      },
    );
  }
}

/// A small tag on a session: Key, Easy, Hard, Today.
class PlanTag extends StatelessWidget {
  const PlanTag(this.text, {super.key, this.fg, this.bg});
  final String text;
  final Color? fg, bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg ?? context.c.surface2,
      borderRadius: BorderRadius.circular(TempoRadii.pill),
    ),
    child: Text(
      text,
      style: TempoType.caption
          .copyWith(fontWeight: FontWeight.w600)
          .c(fg ?? context.c.text1),
    ),
  );
}

/// Key and effort tags for [s].
List<Widget> sessionTags(BuildContext context, sc.Session s) {
  final x = context.s;
  return [
    if (sc.isKeySession(s)) PlanTag('Key', fg: x.recHigh, bg: x.tintRecHigh),
    if (!s.isRest)
      PlanTag(
        sc.effortTag(s),
        fg: switch (s.intensity) {
          sc.Intensity.hard => x.recLow,
          sc.Intensity.moderate => x.recMid,
          _ => context.c.text1,
        },
        bg: switch (s.intensity) {
          sc.Intensity.hard => x.tintRecLow,
          sc.Intensity.moderate => x.tintRecMid,
          _ => context.c.surface2,
        },
      ),
  ];
}

/// Today first: what to do, how hard, why, and Start / Move / Skip.
class PlanTodayCard extends ConsumerWidget {
  const PlanTodayCard(this.t, {super.key});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final p = t.plan;
    final weekday = _dayNames[t.day.weekday - 1];
    final paused = t.pause != null;
    final done =
        t.status == sc.DayStatus.done ||
        t.status == sc.DayStatus.doneEasier ||
        t.status == sc.DayStatus.doneHarder;
    final skipped =
        t.status == sc.DayStatus.skipped || t.status == sc.DayStatus.missedDay;

    if (p == null || p.isRest || t.restDay) {
      final off = p != null && !p.isRest;
      return _Brief(
        overline: 'Today · $weekday',
        title: 'Rest day',
        sub: off
            ? 'Recovery says rest today, so the ${p.title.toLowerCase()} is '
                  'off. Light movement only.'
            : 'Nothing planned. A walk is fine.',
        how: null,
        why: sc.sessionPurpose(sc.sessionTemplate('rest')),
      );
    }
    if (done) {
      return _Brief(
        overline: 'Today · $weekday',
        chip: statusLabel(t),
        chipColor: statusColor(context, t.status),
        title: '${p.title} done',
        sub: 'Recover well. The rest of the week is below.',
        onTap: () => push(context, const WorkoutDetailScreen()),
      );
    }

    final row = t.planRow;
    final changed = row?.original != null && (row?.reason ?? '').isNotEmpty;
    final reason = changed
        ? row!.reason!.replaceFirst(RegExp(r'^\S\s'), '')
        : null;
    final strength = p.sport == sc.Sport.strength;
    final detail = p.detail;
    final names = detail is sc.StrengthDetail
        ? [for (final e in detail.exercises) e.name]
        : const <String>[];
    final coach = CoachService(ref.read(dbProvider));
    final chip = t.status == sc.DayStatus.pending && t.plannedMinute == null
        ? null
        : statusLabel(t);

    return TempoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PlanTag('Today · $weekday', fg: c.textInverse, bg: c.text1),
              ...sessionTags(context, p),
              if (chip != null)
                TempoBadge(chip, color: statusColor(context, t.status)),
            ],
          ),
          const SizedBox(height: 12),
          Text(p.title, style: TempoType.titleL.c(c.text1)),
          Text('${p.minutes} minutes', style: TempoType.titleM.c(c.text2).tnum),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Text(reason, style: TempoType.bodyS.c(c.text2)),
          ],
          const SizedBox(height: 14),
          if (strength)
            Text(
              names.isEmpty
                  ? 'Log sets as you go; Tempo suggests weights from your last '
                        'session.'
                  : '${names.take(4).join(' · ')}${names.length > 4 ? ' · +${names.length - 4} more' : ''}',
              style: TempoType.bodyS.c(c.text1),
            )
          else ...[
            IntervalBars(
              segments: [for (final g in p.segments) (g.minutes, g.zone)],
            ),
            const SizedBox(height: 6),
            Text(p.structure, style: TempoType.caption.c(c.text3).tnum),
          ],
          const SizedBox(height: 14),
          _HowWhy(how: sc.effortCue(p), why: sc.sessionPurpose(p)),
          if (!paused) ...[
            const SizedBox(height: 14),
            if (skipped)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Skipped. Nothing to make up.',
                      style: TempoType.bodyS.c(c.text2),
                    ),
                  ),
                  TempoButton(
                    'Undo',
                    small: true,
                    kind: ButtonKind.secondary,
                    onTap: () async {
                      await coach.setIntent(t.day, sc.Intent.planned);
                      await _changed(ref);
                    },
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TempoButton(
                      'Start',
                      icon: TempoIcons.play,
                      expand: true,
                      onTap: () => openLive(context, ref, plan: p),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TempoButton(
                    'Move',
                    kind: ButtonKind.secondary,
                    onTap: () => showMoveSheet(context, ref, t.day),
                  ),
                  const SizedBox(width: 8),
                  TempoButton(
                    'Skip',
                    kind: ButtonKind.secondary,
                    onTap: () => _skip(context, ref, t.day),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TempoButton(
                'Details and other options',
                small: true,
                kind: ButtonKind.text,
                onTap: () => push(context, const WorkoutDetailScreen()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A short today card (rest or done).
class _Brief extends StatelessWidget {
  const _Brief({
    required this.overline,
    required this.title,
    required this.sub,
    this.how,
    this.why,
    this.chip,
    this.chipColor,
    this.onTap,
  });
  final String overline, title, sub;
  final String? how, why, chip;
  final Color? chipColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      onTap: onTap,
      label: title,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PlanTag(overline, fg: c.textInverse, bg: c.text1),
              const Spacer(),
              if (chip != null) TempoBadge(chip!, color: chipColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: TempoType.titleL.c(c.text1)),
          const SizedBox(height: 4),
          Text(sub, style: TempoType.bodyS.c(c.text2)),
          if (how != null || why != null) ...[
            const SizedBox(height: 12),
            _HowWhy(how: how, why: why),
          ],
        ],
      ),
    );
  }
}

class _HowWhy extends StatelessWidget {
  const _HowWhy({this.how, this.why});
  final String? how, why;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget line(String head, String body) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$head ', style: TempoType.bodyS.c(c.text1).w500),
          TextSpan(text: body),
        ],
      ),
      style: TempoType.bodyS.c(c.text2),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (how != null) line('How:', how!),
          if (how != null && why != null) const SizedBox(height: 8),
          if (why != null) line('Why:', why!),
        ],
      ),
    );
  }
}

/// The week as an agenda: what next week depends on, missed sessions as
/// one line with options, the days still to come (Move / Skip) and the
/// days gone by.
class PlanWeekCard extends ConsumerWidget {
  const PlanWeekCard(this.t, {super.key});
  final TodayData t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final w = ref.watch(weekProvider).value;
    final days = ref.watch(weekDaysProvider).value;
    final gv = ref.watch(goalViewProvider).value;
    if (w == null || days == null || days.length != 7) {
      return const SizedBox(height: 200);
    }
    final today = t.day.weekday - 1;
    final paused = t.pause != null;
    final missed = missedDays(days, today);
    final left = [
      for (var i = today; i < 7; i++)
        if (!days[i].session.isRest &&
            days[i].credit == 0 &&
            days[i].status != sc.Intent.skipped.name)
          i,
    ].length;
    final rule = sc.weekRuleLine(
      phase: gv?.week?.phase,
      forecast: gv?.week == null ? null : gv!.forecast,
      left: gv?.week == null ? left : gv!.left,
    );

    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('This week')),
              Text(
                '${dm(w.monday)} – ${dm(w.date(6))}',
                style: TempoType.caption.c(c.text3).tnum,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(rule, style: TempoType.body.c(c.text1)),
          if (missed.isNotEmpty && !paused) ...[
            const SizedBox(height: 12),
            _MissedLine(n: missed.length),
          ],
          for (var i = today + 1; i < 7; i++) ...[
            const SizedBox(height: 12),
            const Hair(),
            _UpcomingRow(w: w, d: days[i], i: i, today: today, paused: paused),
          ],
          if (today > 0) ...[
            const SizedBox(height: 16),
            const Overline('Earlier'),
            for (var i = 0; i < today; i++) _PastRow(d: days[i], i: i),
          ],
        ],
      ),
    );
  }
}

class _MissedLine extends ConsumerWidget {
  const _MissedLine({required this.n});
  final int n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, s = context.s;
    return Pressable(
      label: 'Missed sessions: options',
      onTap: () => showCatchUpSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: s.tintRecMid,
          borderRadius: BorderRadius.circular(TempoRadii.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: n == 1
                          ? '1 session missed. '
                          : '$n sessions missed. ',
                      style: TempoType.bodyS.c(c.text1).w500,
                    ),
                    const TextSpan(text: 'No need to make them up.'),
                  ],
                ),
                style: TempoType.bodyS.c(c.text1),
              ),
            ),
            const SizedBox(width: 8),
            Text('Options ›', style: TempoType.label.c(c.text1)),
          ],
        ),
      ),
    );
  }
}

class _DateCol extends StatelessWidget {
  const _DateCol(this.date, {this.muted = false});
  final DateTime date;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          Text(
            _dayNames[date.weekday - 1],
            style: TempoType.caption.c(c.text3),
          ),
          Text(
            '${date.day}',
            style: TempoType.label.c(muted ? c.text2 : c.text1).tnum,
          ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends ConsumerWidget {
  const _UpcomingRow({
    required this.w,
    required this.d,
    required this.i,
    required this.today,
    required this.paused,
  });
  final WeekView w;
  final DayCredit d;
  final int i, today;
  final bool paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = d.session;
    final skipped = d.status == sc.Intent.skipped.name;
    final was = w.original(i);
    final race = s.key == 'race';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateCol(d.date),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!s.isRest) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sessionTags(context, s),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  s.isRest ? 'Rest' : '${s.title} · ${s.minutes} min',
                  style: TempoType.label.c(skipped ? c.text3 : c.text1).tnum,
                ),
                const SizedBox(height: 2),
                Text(
                  s.isRest
                      ? (s.note.isEmpty ? 'Recover' : s.note)
                      : skipped
                      ? 'Skipped'
                      : s.sport == sc.Sport.strength
                      ? sc.effortCue(s)
                      : s.structure,
                  style: TempoType.bodyS.c(c.text2).tnum,
                ),
                if (was != null && was.key != s.key) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Was ${was.title.toLowerCase()}',
                    style: TempoType.caption.c(c.text3),
                  ),
                ],
                if (!s.isRest && !race && !paused) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: skipped
                        ? [
                            TempoButton(
                              'Undo skip',
                              small: true,
                              kind: ButtonKind.secondary,
                              onTap: () async {
                                await CoachService(ref.read(dbProvider))
                                    .setIntent(d.date, sc.Intent.planned);
                                await _changed(ref);
                              },
                            ),
                          ]
                        : [
                            TempoButton(
                              'Move',
                              small: true,
                              kind: ButtonKind.secondary,
                              onTap: () => showMoveSheet(context, ref, d.date),
                            ),
                            TempoButton(
                              'Skip',
                              small: true,
                              kind: ButtonKind.secondary,
                              onTap: () => _skip(context, ref, d.date),
                            ),
                          ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.d, required this.i});
  final DayCredit d;
  final int i;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final x = d.session;
    final (label, col) = x.isRest
        ? ('Rest', c.text3)
        : d.credit >= 1
        ? ('Done ✓', s.recHigh)
        : d.credit > 0
        ? ('Done, easier', s.recHigh)
        : d.status == sc.Intent.skipped.name
        ? ('Let go', c.text3)
        : ('Missed', c.text2);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _DateCol(d.date, muted: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              x.isRest ? 'Rest' : '${x.title} · ${x.minutes} min',
              style: TempoType.bodyS.c(c.text2).tnum,
            ),
          ),
          Text(label, style: TempoType.caption.c(col)),
        ],
      ),
    );
  }
}

/// Where a session can go this week: days that swap without two heavy
/// days back to back.
Future<void> showMoveSheet(
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
  final s = week[from];
  await showTempoSheet<void>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Move ${s.title.toLowerCase()}',
            style: TempoType.titleM.c(c.text1),
          ),
          const SizedBox(height: 6),
          Text(
            targets.isEmpty
                ? 'No other day this week takes it without two hard days in a '
                      'row. Skip it instead, or keep it where it is.'
                : 'It swaps with that day’s session. Tempo keeps hard days '
                      'apart.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 12),
          if (targets.isNotEmpty)
            CardList(
              children: [
                for (final j in targets)
                  ListRow(
                    '${_dayNames[j]} ${w.date(j).day}${j == today ? ' · today' : ''}',
                    sub: week[j].isRest
                        ? 'A rest day now; rest moves to ${_dayNames[from]}'
                        : 'Swaps with ${week[j].title.toLowerCase()} · ${week[j].minutes} min',
                    onTap: () async {
                      await CoachService(db).moveDay(day, w.date(j));
                      await _changed(ref);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (host.mounted) {
                        showTempoToast(
                          host,
                          '${s.title} moved to ${_dayNames[j]}',
                          action: 'Undo',
                          onAction: () async {
                            await CoachService(db).moveDay(w.date(j), day);
                            await _changed(ref);
                          },
                        );
                      }
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          TempoButton(
            'Keep it',
            kind: ButtonKind.ghost,
            expand: true,
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      );
    },
  );
}

/// Missed sessions: let them go (the default), fit a key one back in, make
/// the rest of the week easy, or rebuild the week from today.
Future<void> showCatchUpSheet(BuildContext context, WidgetRef ref) async {
  final host = Navigator.of(context).context;
  final db = ref.read(dbProvider);
  final days = await ref.read(weekDaysProvider.future);
  final gv = await ref.read(goalViewProvider.future);
  final x = await ref.read(coachExtrasProvider.future);
  if (!context.mounted) return;
  final today = DateTime.now().weekday - 1;
  final missed = missedDays(days, today);
  final m = gv?.missed;
  String plan(sc.Realign r) => [
    for (final i in r.changed)
      '${_dayNames[i]} ${r.week[i].title.toLowerCase()}',
  ].join(' · ');

  Future<void> run(
    BuildContext ctx,
    Future<void> Function() go,
    String toast,
  ) async {
    await go();
    await _changed(ref);
    if (ctx.mounted) Navigator.pop(ctx);
    if (host.mounted) showTempoToast(host, toast);
  }

  await showTempoSheet<void>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      final options = <Widget>[
        _Option(
          title: 'Let them go',
          tag: 'Suggested',
          body:
              'Carry on with the rest of the week as planned. Nothing is '
              'added to catch up.',
          onTap: () => run(
            ctx,
            () => letGoAll(db, days, today),
            'Let go. Carry on from here.',
          ),
        ),
        if (gv != null && m != null && gv.realign != null)
          _Option(
            title: 'Fit ${gv.days[m].session.title.toLowerCase()} back in',
            body:
                'It takes an easy day’s place, with no two hard days in a '
                'row: ${plan(gv.realign!)}. The others are let go.',
            onTap: () => run(ctx, () async {
              await rearrangeWeek(db, gv);
              await letGoAll(db, days, today);
            }, 'Week rearranged'),
          ),
        if (gv != null && gv.ease != null)
          _Option(
            title: 'Make the rest of the week easy',
            body:
                'Recovery or feel has been low: ${plan(gv.ease!)}. The missed '
                'ones are let go.',
            onTap: () => run(ctx, () async {
              await easeWeek(db, gv);
              await letGoAll(db, days, today);
            }, 'Rest of the week is easy'),
          ),
        if (gv == null && x.realign)
          _Option(
            title: 'Rebuild the rest of the week',
            body:
                'Start the week’s pattern again from today, sized for how '
                'the last days went.',
            onTap: () => run(ctx, () async {
              await db.putSetting(Keys.carried, '');
              await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
              await letGoAll(db, days, today);
            }, 'Week rebuilt from today'),
          ),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            missed.length == 1
                ? '1 session missed this week'
                : '${missed.length} sessions missed this week',
            style: TempoType.titleM.c(c.text1),
          ),
          const SizedBox(height: 6),
          Text(
            'Missing a few is normal. Squeezing them all in raises injury '
            'risk, so pick one way forward.',
            style: TempoType.bodyS.c(c.text2),
          ),
          for (final o in options) ...[const SizedBox(height: 10), o],
          const SizedBox(height: 8),
          TempoButton(
            'Not now',
            kind: ButtonKind.ghost,
            expand: true,
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      );
    },
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.body,
    required this.onTap,
    this.tag,
  });
  final String title, body;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return TempoCard(
      onTap: onTap,
      label: title,
      color: c.surface1,
      border: tag == null ? c.line : c.text1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TempoType.label.c(c.text1))),
              if (tag != null) PlanTag(tag!, fg: s.recHigh, bg: s.tintRecHigh),
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: TempoType.bodyS.c(c.text2)),
        ],
      ),
    );
  }
}

/// The goal in one card: name and countdown, the stages as a bar, where
/// you are in plain words. With no goal, an invitation to set one.
class PlanGoalCard extends ConsumerWidget {
  const PlanGoalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final async = ref.watch(goalViewProvider);
    if (!async.hasValue) return const SizedBox.shrink();
    final v = async.value;
    if (v == null) {
      return TempoCard(
        label: 'Set a training goal',
        onTap: () => startGoal(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Your goal'),
            const SizedBox(height: 8),
            Text('No training goal', style: TempoType.titleM.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              'Training for something? Set a race or a fitness goal and the '
              'plan builds toward it, with a lighter week every 4th.',
              style: TempoType.bodyS.c(c.text2),
            ),
            const SizedBox(height: 8),
            Text('Set a goal →', style: TempoType.label.c(c.text1)),
          ],
        ),
      );
    }
    final b = v.block, w = v.week;
    final days = v.daysToRace;
    final current = w?.index ?? -1;
    final weeks = v.weeks;
    final title = b.isEvent && days != null && days > 0
        ? '${sc.goalName(b.goal)} in ${days == 1 ? '1 day' : '$days days'}'
        : sc.goalName(b.goal);
    String where;
    if (w == null) {
      where = b.isEvent && DateTime.now().isAfter(b.event!)
          ? 'Race done. Set a new goal to keep building.'
          : 'Starts next week.';
    } else {
      final nextPhase = current + 1 < weeks.length
          ? weeks[current + 1].phase
          : null;
      where = [
        b.isEvent
            ? 'Week ${w.index + 1} of ${w.weeks}: ${phasePlain(w.phase).toLowerCase()}.'
            : 'Week ${w.index + 1}: ${phasePlain(w.phase).toLowerCase()}.',
        if (nextPhase != null && nextPhase != w.phase)
          'Next week: ${phasePlain(nextPhase).toLowerCase()}.',
      ].join(' ');
    }
    // Stages, in order, with how many weeks each.
    final stages = <(sc.Phase, int)>[];
    for (final x in weeks) {
      if (stages.isNotEmpty && stages.last.$1 == x.phase) {
        stages.last = (x.phase, stages.last.$2 + 1);
      } else {
        stages.add((x.phase, 1));
      }
    }
    return TempoCard(
      label: 'Open your goal',
      onTap: () => push(context, const GoalScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Your goal')),
              if (b.isEvent)
                Text(dayShort(b.event!), style: TempoType.caption.c(c.text3)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TempoType.titleM.c(c.text1)),
          if (weeks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (k, x) in weeks.indexed) ...[
                  if (k > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: x.index < current
                            ? c.text2
                            : x.index == current
                            ? c.text1
                            : c.trackOff,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final (p, n) in stages)
                  Expanded(
                    flex: n,
                    child: Text(
                      phaseShort(p),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TempoType.caption
                          .copyWith(
                            fontSize: 11,
                            fontWeight: w?.phase == p ? FontWeight.w600 : null,
                          )
                          .c(w?.phase == p ? c.text1 : c.text3),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(where, style: TempoType.bodyS.c(c.text2)),
          const SizedBox(height: 8),
          Text('See the whole plan →', style: TempoType.label.c(c.text1)),
        ],
      ),
    );
  }
}

/// The header pill: the goal and days to go, or "Set a goal".
class GoalPill extends ConsumerWidget {
  const GoalPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final v = ref.watch(goalViewProvider).value;
    final days = v?.daysToRace;
    final text = v == null
        ? 'Set a goal'
        : days != null && days > 0
        ? '${sc.goalName(v.block.goal)} · ${days == 1 ? '1 day' : '$days days'}'
        : sc.goalName(v.block.goal);
    return Pressable(
      label: v == null ? 'Set a training goal' : 'Open your goal',
      onTap: () => v == null
          ? startGoal(context, ref)
          : push(context, const GoalScreen()),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TempoRadii.pill),
          border: Border.all(color: c.lineStrong),
        ),
        child: Text(text, style: TempoType.label.c(c.text1).tnum),
      ),
    );
  }
}
