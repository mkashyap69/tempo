/// Tempo Coach notifications, decided in pure Dart: which to schedule for
/// the next 48 hours, with what words and buttons, under quiet hours, a
/// daily budget, spacing and backoff. The app hands the result to the
/// platform and replaces the whole set on every evaluation.
///
/// Copy is written as a question the buttons answer, so a notification
/// stays true even if no sync ran after it was scheduled.
library;

import 'coach_day.dart';

const nudgeAlgo = 'nudge-1';

enum NudgeKind { brief, session, missed, lever, winddown, rpe, health, weekly }

/// How a kind interrupts. Passive ones go quietly to the shade.
enum NudgeLevel { passive, active }

/// Proactive kinds share the daily budget (the user didn't ask for them).
const proactiveKinds = {NudgeKind.session, NudgeKind.missed, NudgeKind.lever};

/// Kinds on by default; weekly is opt-in.
const defaultKinds = {
  NudgeKind.brief,
  NudgeKind.session,
  NudgeKind.missed,
  NudgeKind.lever,
  NudgeKind.winddown,
  NudgeKind.rpe,
  NudgeKind.health,
};

final class NudgeAction {
  const NudgeAction(this.id, this.title, {this.foreground = false});
  final String id, title;

  /// Opens the app (Start, Open); others run in the background.
  final bool foreground;
}

final class NudgeSpec {
  const NudgeSpec({
    required this.kind,
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    this.actions = const [],
    this.payload = const {},
    this.requested = false,
  });
  final NudgeKind kind;
  final int id;
  final DateTime fireAt;
  final String title, body;
  final List<NudgeAction> actions;
  final Map<String, Object?> payload;

  /// The user asked for it (Later, Plan 18:00): outside the budget.
  final bool requested;

  NudgeLevel get level => kind == NudgeKind.brief || kind == NudgeKind.weekly
      ? NudgeLevel.passive
      : NudgeLevel.active;
}

/// Deterministic id: one per kind per day offset (0 today, 1 tomorrow).
int nudgeId(NudgeKind k, int dayOffset) => 100 + k.index * 10 + dayOffset;

/// A planned day as the nudge planner needs it.
final class NudgeDay {
  const NudgeDay({
    required this.title,
    required this.minutes,
    required this.rest,
    this.plannedMinute,
    this.status = DayStatus.pending,
    this.hard = false,
  });
  final String title;
  final int minutes;
  final bool rest, hard;

  /// Minute of day it's planned for, or null (any time).
  final int? plannedMinute;
  final DayStatus status;
}

final class NudgeContext {
  const NudgeContext({
    required this.now,
    required this.wake,
    required this.bedtime,
    required this.today,
    this.tomorrow,
    this.morning,
    this.winddownBefore,
    this.pmSlot = 18 * 60,
    this.rescue,
    this.briefLine,
    this.leverLine,
    this.stepsBehind = false,
    this.syncAgeMinutes,
    this.live = false,
    this.paused = false,
    this.kinds = defaultKinds,
    this.cap = 1,
    this.ignoreStreak = const {},
    this.sentLast7 = 0,
    this.rpeWorkout,
    this.illness = false,
    this.healthSentToday = false,
  });

  final DateTime now;

  /// Minutes of day.
  final int wake, bedtime;
  final NudgeDay today;
  final NudgeDay? tomorrow;

  /// Morning brief time (minute of day), null = off.
  final int? morning;

  /// Minutes before bedtime for wind-down, null = off.
  final int? winddownBefore;
  final int pmSlot;

  /// Today's same-day rescue, when the slot already passed.
  final Rescue? rescue;

  /// "Recovery 72% · in by 22:45" for today's brief.
  final String? briefLine;

  /// The lever action to nudge (e.g. "4.1k steps so far").
  final String? leverLine;
  final bool stepsBehind;
  final int? syncAgeMinutes;
  final bool live, paused;
  final Set<NudgeKind> kinds;

  /// Proactive nudges allowed per day (0–2).
  final int cap;

  /// Consecutive ignored notifications per kind (newest run).
  final Map<NudgeKind, int> ignoreStreak;

  /// Non-requested nudges posted in the last 7 days.
  final int sentLast7;

  /// A workout to rate: (id, title).
  final (int, String)? rpeWorkout;
  final bool illness, healthSentToday;
}

/// Caps and spacing.
const maxPerDay = 4, maxPerWeek = 14, spacingMinutes = 90;
const ignoreSlow = 3, ignorePause = 5;

String _hm(int m) {
  final x = m % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

/// Every notification to schedule for the next 48 hours, soonest first.
List<NudgeSpec> planNudges(NudgeContext c) {
  final day0 = DateTime(c.now.year, c.now.month, c.now.day);
  DateTime at(int offset, int minute) =>
      DateTime(day0.year, day0.month, day0.day + offset, 0, minute);
  final soon = c.now.add(const Duration(minutes: 1));
  bool future(DateTime t) => t.isAfter(c.now);

  // Quiet: from bedtime to wake (minute of day, wrapping midnight).
  bool quiet(DateTime t) {
    final m = t.hour * 60 + t.minute;
    final b = c.bedtime % 1440, w = c.wake % 1440;
    return b > w ? (m >= b || m < w) : (m >= b && m < w);
  }

  bool on(NudgeKind k) {
    if (!c.kinds.contains(k)) return false;
    if (c.paused && k != NudgeKind.winddown) return false;
    final s = c.ignoreStreak[k] ?? 0;
    if (s >= ignorePause) return false;
    return true;
  }

  // Three ignores in a row: every other day only.
  bool slowed(NudgeKind k, int offset) =>
      (c.ignoreStreak[k] ?? 0) >= ignoreSlow &&
      at(offset, 0).difference(DateTime(2000)).inDays.isOdd;

  final out = <NudgeSpec>[];

  // Morning brief (passive).
  if (c.morning != null && on(NudgeKind.brief)) {
    for (final o in [0, 1]) {
      final t = at(o, c.morning!);
      if (!future(t)) continue;
      final d = o == 0 ? c.today : c.tomorrow;
      out.add(
        NudgeSpec(
          kind: NudgeKind.brief,
          id: nudgeId(NudgeKind.brief, o),
          fireAt: t,
          title: d == null
              ? 'Your plan for today'
              : d.rest
              ? 'Today: rest day'
              : 'Today: ${d.title} ${d.minutes}′',
          body: o == 0 && c.briefLine != null
              ? c.briefLine!
              : 'Open after waking to see how ready you are',
          actions: d == null || d.rest
              ? const [NudgeAction('open', 'Open', foreground: true)]
              : const [
                  NudgeAction('open', 'Open', foreground: true),
                  NudgeAction('easier', 'Easier'),
                  NudgeAction('rest', 'Rest today'),
                ],
        ),
      );
    }
  }

  // Session reminder 15 minutes before its slot.
  if (on(NudgeKind.session)) {
    for (final o in [0, 1]) {
      final d = o == 0 ? c.today : c.tomorrow;
      if (d == null || d.rest || d.plannedMinute == null) continue;
      if (o == 0 &&
          d.status != DayStatus.pending &&
          d.status != DayStatus.moved) {
        continue;
      }
      if (d.status != DayStatus.moved && slowed(NudgeKind.session, o)) {
        continue;
      }
      final t = at(o, d.plannedMinute! - 15);
      if (!future(t)) continue;
      out.add(
        NudgeSpec(
          kind: NudgeKind.session,
          id: nudgeId(NudgeKind.session, o),
          fireAt: t,
          title: '${d.title} at ${_hm(d.plannedMinute!)}?',
          body: '${d.minutes}′ · tap Start when you’re ready',
          actions: const [
            NudgeAction('start', 'Start', foreground: true),
            NudgeAction('later', 'Later 1h'),
            NudgeAction('skip', 'Skip'),
          ],
          requested: o == 0 && d.status == DayStatus.moved,
        ),
      );
    }
  }

  // Missed slot: now if it already passed with a rescue; otherwise a
  // pre-scheduled question two hours after a morning slot ends.
  if (on(NudgeKind.missed) && !c.today.rest) {
    final r = c.rescue;
    if (c.today.status == DayStatus.missedSlot &&
        r != null &&
        r.offered &&
        (c.syncAgeMinutes ?? 0) < 180) {
      out.add(
        NudgeSpec(
          kind: NudgeKind.missed,
          id: nudgeId(NudgeKind.missed, 0),
          fireAt: soon,
          title: '${c.today.title} not seen yet',
          body:
              'Want ${r.session!.title.toLowerCase()} ${r.session!.minutes}′ at ${_hm(r.start!)}?',
          actions: [
            const NudgeAction('done', 'Done already'),
            NudgeAction('plan_pm', 'Plan ${_hm(r.start!)}'),
            const NudgeAction('skip', 'Skip'),
          ],
          payload: {
            'start': r.start,
            'session': r.session!.key,
            'minutes': r.session!.minutes,
          },
        ),
      );
    } else if (c.today.status == DayStatus.pending &&
        c.today.plannedMinute != null &&
        c.today.plannedMinute! < 12 * 60) {
      final t = at(0, c.today.plannedMinute! + c.today.minutes + missedGrace);
      if (future(t) && !slowed(NudgeKind.missed, 0)) {
        out.add(
          NudgeSpec(
            kind: NudgeKind.missed,
            id: nudgeId(NudgeKind.missed, 0),
            fireAt: t,
            title: 'Did ${c.today.title.toLowerCase()} happen?',
            body: 'If not, there’s still time this evening',
            actions: [
              const NudgeAction('done', 'Done already'),
              NudgeAction('plan_pm', 'Plan ${_hm(c.pmSlot)}'),
              const NudgeAction('skip', 'Skip'),
            ],
            payload: {'start': c.pmSlot},
          ),
        );
      }
    }
  }

  // Lever nudge mid-afternoon, only with fresh data and nothing pending.
  if (on(NudgeKind.lever) &&
      c.stepsBehind &&
      c.leverLine != null &&
      (c.syncAgeMinutes ?? 999) < 180 &&
      c.today.status != DayStatus.pending &&
      c.today.status != DayStatus.moved &&
      !slowed(NudgeKind.lever, 0)) {
    final t = at(0, 15 * 60);
    if (future(t)) {
      out.add(
        NudgeSpec(
          kind: NudgeKind.lever,
          id: nudgeId(NudgeKind.lever, 0),
          fireAt: t,
          title: c.leverLine!,
          body: 'A 10′ walk after work could help',
          actions: const [
            NudgeAction('got_it', 'Got it'),
            NudgeAction('not_today', 'Not today'),
          ],
        ),
      );
    }
  }

  // Wind-down.
  if (c.winddownBefore != null && on(NudgeKind.winddown)) {
    for (final o in [0, 1]) {
      final t = at(o, bedScale(c.bedtime) - c.winddownBefore!);
      if (!future(t)) continue;
      out.add(
        NudgeSpec(
          kind: NudgeKind.winddown,
          id: nudgeId(NudgeKind.winddown, o),
          fireAt: t,
          title: 'In bed by ${_hm(c.bedtime)}?',
          body: 'Wind down now to cover tonight’s sleep need',
          actions: const [
            NudgeAction('got_it', 'Got it'),
            NudgeAction('not_today', 'Not tonight'),
          ],
          requested: true,
        ),
      );
    }
  }

  // Rate a detected workout.
  if (c.rpeWorkout != null && on(NudgeKind.rpe) && !quiet(soon)) {
    out.add(
      NudgeSpec(
        kind: NudgeKind.rpe,
        id: nudgeId(NudgeKind.rpe, 0),
        fireAt: soon,
        title: '${c.rpeWorkout!.$2} detected',
        body: 'How hard did it feel?',
        actions: const [
          NudgeAction('rpe_3', 'Easy'),
          NudgeAction('rpe_5', 'Moderate'),
          NudgeAction('rpe_8', 'Hard'),
        ],
        payload: {'workout': c.rpeWorkout!.$1},
      ),
    );
  }

  // Health: once per day while the illness flag holds.
  if (c.illness && !c.healthSentToday && on(NudgeKind.health)) {
    final t = quiet(soon) ? at(0, c.wake + 30) : soon;
    if (!t.isBefore(soon)) {
      out.add(
        NudgeSpec(
          kind: NudgeKind.health,
          id: nudgeId(NudgeKind.health, 0),
          fireAt: t,
          title: 'Night heart rate ran high',
          body: 'Rest today? You can pause the plan',
          actions: const [
            NudgeAction('pause3', 'Pause 3 days'),
            NudgeAction('fine', 'I’m fine'),
          ],
          requested: true,
        ),
      );
    }
  }

  // Weekly look-back, Sunday 18:00 (opt-in).
  if (on(NudgeKind.weekly)) {
    for (final o in [0, 1]) {
      final t = at(o, 18 * 60);
      if (t.weekday != DateTime.sunday || !future(t)) continue;
      out.add(
        NudgeSpec(
          kind: NudgeKind.weekly,
          id: nudgeId(NudgeKind.weekly, o),
          fireAt: t,
          title: 'Your week with Tempo',
          body: 'Next week’s plan is ready',
          actions: const [NudgeAction('open', 'Open', foreground: true)],
        ),
      );
    }
  }

  return _budget(c, out, quiet);
}

const _priority = [
  NudgeKind.health,
  NudgeKind.session,
  NudgeKind.missed,
  NudgeKind.rpe,
  NudgeKind.winddown,
  NudgeKind.lever,
  NudgeKind.brief,
  NudgeKind.weekly,
];

/// Applies quiet hours, the live-session hold, the proactive cap, the
/// daily and weekly totals and 90-minute spacing between interruptions.
/// Higher-priority kinds win.
List<NudgeSpec> _budget(
  NudgeContext c,
  List<NudgeSpec> all,
  bool Function(DateTime) quiet,
) {
  final sorted = [...all]
    ..sort(
      (a, b) => _priority.indexOf(a.kind).compareTo(_priority.indexOf(b.kind)),
    );
  final kept = <NudgeSpec>[];
  var weekLeft = maxPerWeek - c.sentLast7;
  for (final n in sorted) {
    final quietOk =
        n.kind == NudgeKind.brief ||
        n.kind == NudgeKind.winddown ||
        !quiet(n.fireAt);
    if (!quietOk) continue;
    if (c.live && n.fireAt.difference(c.now).inMinutes < 120) continue;
    final day = DateTime(n.fireAt.year, n.fireAt.month, n.fireAt.day);
    final same = kept.where(
      (k) =>
          k.fireAt.year == day.year &&
          k.fireAt.month == day.month &&
          k.fireAt.day == day.day,
    );
    if (same.length >= maxPerDay) continue;
    if (proactiveKinds.contains(n.kind) && !n.requested) {
      final used = same
          .where((k) => proactiveKinds.contains(k.kind) && !k.requested)
          .length;
      if (used >= c.cap) continue;
      if (weekLeft <= 0) continue;
    }
    if (n.level == NudgeLevel.active) {
      final clash = same.any(
        (k) =>
            k.level == NudgeLevel.active &&
            k.fireAt.difference(n.fireAt).inMinutes.abs() < spacingMinutes,
      );
      if (clash) continue;
    }
    if (!n.requested && n.kind != NudgeKind.brief) weekLeft--;
    kept.add(n);
  }
  kept.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return kept;
}

/// Consecutive ignored notifications per kind from a log of posted ones
/// and responses: (kind, fireAt, responded) newest first.
Map<NudgeKind, int> ignoreStreaks(
  List<(NudgeKind, DateTime, bool)> postedNewestFirst,
) {
  final out = <NudgeKind, int>{};
  final closed = <NudgeKind>{};
  for (final (k, _, responded) in postedNewestFirst) {
    if (closed.contains(k)) continue;
    if (responded) {
      closed.add(k);
      out.putIfAbsent(k, () => 0);
    } else {
      out[k] = (out[k] ?? 0) + 1;
    }
  }
  return out;
}
