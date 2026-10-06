import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'longevity_service.dart' show LongevityFocus, loadFocus;
import 'profile.dart';

/// Ratings or recoveries needed in a week before they count toward its
/// outcome; with fewer, that signal is left out.
const outcomeMinDays = 3;

/// The training goal, or null when the plan is the same week every week.
/// Once the goal's race and a recovery week are over, the queued next goal
/// takes over here.
Future<sc.TrainingBlock?> loadBlock(st.TempoDb db, {DateTime? now}) async {
  final b = _parseBlock(await db.setting(Keys.coachBlock));
  final start = b == null ? null : sc.nextBlockStart(b);
  if (start == null || dayOf(now ?? DateTime.now()).isBefore(start)) return b;
  final next = await loadNext(db);
  if (next == null) return b;
  final promoted = sc.TrainingBlock(
    goal: next.goal,
    start: start,
    event: next.event,
  );
  await db.putSetting(Keys.coachBlock, jsonEncode(promoted.toJson()));
  await db.putSetting(Keys.coachNext, '');
  return promoted;
}

sc.TrainingBlock? _parseBlock(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return sc.TrainingBlock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return null;
  }
}

/// Starts [goal] this week (an event on [event]), or clears it with null,
/// then rebuilds this week's plan from today. Returns what was stored
/// before, for [restoreBlock].
Future<String?> saveBlock(
  st.TempoDb db,
  sc.BlockGoal? goal, {
  DateTime? event,
  DateTime? now,
}) async {
  final today = dayOf(now ?? DateTime.now());
  final before = await db.setting(Keys.coachBlock);
  await db.putSetting(
    Keys.coachBlock,
    goal == null
        ? ''
        : jsonEncode(
            sc.TrainingBlock(
              goal: goal,
              start: mondayOf(today),
              event: event,
            ).toJson(),
          ),
  );
  // A queued goal follows a race; without one it has nothing to follow.
  if (goal == null || goal == sc.BlockGoal.open) {
    await db.putSetting(Keys.coachNext, '');
  }
  await CoachService(db).ensureWeek(today, rebuild: true);
  return before;
}

/// Puts back a goal [saveBlock] replaced (its undo).
Future<void> restoreBlock(st.TempoDb db, String? raw) async {
  await db.putSetting(Keys.coachBlock, raw ?? '');
  await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
}

/// Moves the race to [event], keeping the block's start and tune-ups (any
/// that no longer fit are dropped). Rebuilds this week.
Future<void> changeEvent(st.TempoDb db, DateTime event) async {
  final b = await loadBlock(db);
  if (b == null) return;
  var moved = sc.TrainingBlock(goal: b.goal, start: b.start, event: event);
  for (final t in b.tuneUps) {
    if (sc.tuneUpProblem(moved, t.date) == null) {
      moved = moved.withTuneUps([...moved.tuneUps, t]);
    }
  }
  await _store(db, moved);
}

/// Adds a tune-up race. It must fit ([sc.tuneUpProblem] is null).
Future<void> addTuneUp(st.TempoDb db, sc.TuneUp t) async {
  final b = await loadBlock(db);
  if (b == null || sc.tuneUpProblem(b, t.date) != null) return;
  await _store(db, b.withTuneUps([...b.tuneUps, t]), touched: t.date);
}

Future<void> removeTuneUp(st.TempoDb db, sc.TuneUp t) async {
  final b = await loadBlock(db);
  if (b == null) return;
  await _store(
    db,
    b.withTuneUps([
      for (final x in b.tuneUps)
        if (st.dateKey(x.date) != st.dateKey(t.date)) x,
    ]),
    touched: t.date,
  );
}

/// Saves [b]; rebuilds this week when [touched] is in it (or always when
/// null).
Future<void> _store(
  st.TempoDb db,
  sc.TrainingBlock b, {
  DateTime? touched,
}) async {
  await db.putSetting(Keys.coachBlock, jsonEncode(b.toJson()));
  final now = DateTime.now();
  if (touched == null || mondayOf(touched) == mondayOf(now)) {
    await CoachService(db).ensureWeek(now, rebuild: true);
  }
}

/// The goal queued after this one.
final class NextGoal {
  const NextGoal(this.goal, this.event);
  final sc.BlockGoal goal;
  final DateTime event;
}

Future<NextGoal?> loadNext(st.TempoDb db) async {
  final raw = await db.setting(Keys.coachNext);
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return NextGoal(
      sc.BlockGoal.values.byName(j['goal'] as String),
      DateTime.parse(j['event'] as String),
    );
  } on Object {
    return null;
  }
}

/// Queues [n] after the current goal (null clears it).
Future<void> saveNext(st.TempoDb db, NextGoal? n) => db.putSetting(
  Keys.coachNext,
  n == null
      ? ''
      : jsonEncode({'goal': n.goal.name, 'event': st.dateKey(n.event)}),
);

/// One day of a week, as the goal's scorecard sees it.
final class DayCredit {
  const DayCredit(this.date, this.session, this.credit, this.status);
  final DateTime date;
  final sc.Session session;

  /// 1 done, .5 done easier, 0 not done.
  final double credit;

  /// The plan row's intent (planned, skipped, moved, done).
  final String status;
}

/// Every planned day of the week starting [monday] and what it earned: a
/// session marked done counts 1, a matched workout 1 (done easier, half).
Future<List<DayCredit>> weekCredits(st.TempoDb db, DateTime monday) async {
  final sun = monday.add(const Duration(days: 6));
  final out = <DayCredit>[];
  for (final r in await db.planBetween(monday, sun)) {
    final s = sc.Session.fromJson(
      jsonDecode(r.session) as Map<String, dynamic>,
    );
    final d = DateTime.parse(r.date);
    var credit = 0.0;
    if (s.isRest) {
      credit = 0;
    } else if (r.status == sc.Intent.done.name) {
      credit = 1;
    } else {
      final ws = await db.workoutsBetween(d, d.add(const Duration(days: 1)));
      credit = switch (sc.matchSession(s, [
        for (final w in ws) doneWorkout(w),
      ]).kind) {
        sc.MatchKind.done => 1,
        sc.MatchKind.doneEasier => .5,
        _ => 0,
      };
    }
    out.add(DayCredit(d, s, credit, r.status));
  }
  return out;
}

/// How the week starting [monday] went: sessions done against the plan
/// (a session done easier counts half), mean recovery and mean feel. For
/// this week, recovery and feel cover the days so far.
Future<sc.WeekOutcome> weekOutcome(st.TempoDb db, DateTime monday) async {
  final sun = monday.add(const Duration(days: 6));
  final days = await weekCredits(db, monday);
  final scores = await db.scoresBetween(monday, sun);
  final recs = [
    for (final s in scores)
      if (!s.calibrating && s.recovery != null) s.recovery!,
  ];
  final feel = [
    for (final f in await db.feelSince(monday))
      if (DateTime.parse(f.date).isBefore(sun.add(const Duration(days: 1))))
        f.feel.toDouble(),
  ];
  return sc.WeekOutcome(
    planned: days.where((d) => !d.session.isRest).length,
    done: days.fold(0.0, (a, d) => a + d.credit),
    recovery: _mean(recs),
    feel: _mean(feel),
  );
}

double? _mean(List<double> xs) =>
    xs.length < outcomeMinDays ? null : xs.reduce((a, b) => a + b) / xs.length;

/// Days with a recovery score and a feel rating that week (for "4 days so
/// far").
Future<(int, int)> signalDays(st.TempoDb db, DateTime monday) async {
  final sun = monday.add(const Duration(days: 6));
  final recs = (await db.scoresBetween(
    monday,
    sun,
  )).where((s) => !s.calibrating && s.recovery != null).length;
  final feel = (await db.feelSince(monday))
      .where(
        (f) =>
            DateTime.parse(f.date).isBefore(sun.add(const Duration(days: 1))),
      )
      .length;
  return (recs, feel);
}

/// Outcomes of every finished week of [b] before [monday], oldest first.
Future<List<sc.WeekOutcome>> pastOutcomes(
  st.TempoDb db,
  sc.TrainingBlock b,
  DateTime monday,
) async => [
  for (
    var m = mondayOf(b.start);
    m.isBefore(monday);
    m = DateTime(m.year, m.month, m.day + 7)
  )
    await weekOutcome(db, m),
];

/// The block week for [monday], replaying every finished week since the
/// block began. Null with no goal, or outside the block.
Future<sc.BlockWeek?> blockWeekFor(st.TempoDb db, DateTime monday) async {
  // Today decides whether the next goal has taken over, never the week
  // being built (planning ahead must not start it early).
  final b = await loadBlock(db);
  if (b == null) return null;
  return sc.blockWeek(b, monday, await pastOutcomes(db, b, monday));
}

/// Everything the Goal screen shows for this week.
final class GoalView {
  const GoalView({
    required this.block,
    required this.week,
    required this.weeks,
    required this.history,
    required this.days,
    required this.today,
    required this.soFar,
    required this.forecast,
    required this.left,
    required this.recDays,
    required this.feelDays,
    required this.phaseSeen,
    required this.usualHard,
    this.next,
    this.focus,
    this.missed,
    this.realign,
    this.ease,
  });
  final sc.TrainingBlock block;

  /// This week of the block (null before it starts or after the race).
  final sc.BlockWeek? week;

  /// The block, projected from this week on.
  final List<sc.BlockWeek> weeks;
  final List<sc.WeekRecord> history;
  final List<DayCredit> days;

  /// Today, 0 = Monday.
  final int today;
  final sc.WeekOutcome soFar;
  final sc.WeekForecast forecast;

  /// Sessions still to come this week (today's counts until it's done).
  final int left;
  final int recDays, feelDays;

  /// The new-phase note was already dismissed.
  final bool phaseSeen;

  /// Hard sessions a week outside a block (from the profile).
  final int usualHard;
  final NextGoal? next;
  final LongevityFocus? focus;

  /// A key session missed earlier this week (day index), not yet
  /// rearranged, carried or let go.
  final int? missed;

  /// How the rest of the week would look with [missed] fitted back in.
  final sc.Realign? realign;

  /// The rest of the week made easy (offered when recovery or feel
  /// already mean a step back).
  final sc.Realign? ease;

  int? get daysToRace => block.isEvent
      ? dayOf(block.event!).difference(dayOf(DateTime.now())).inDays
      : null;
}

String _phaseKey(sc.TrainingBlock b, int i) => '${st.dateKey(b.start)}|$i';

Future<void> dismissPhase(st.TempoDb db, sc.TrainingBlock b, int i) =>
    db.putSetting(Keys.coachPhaseSeen, _phaseKey(b, i));

Future<GoalView?> loadGoalView(st.TempoDb db, {DateTime? at}) async {
  final now = at ?? DateTime.now();
  final b = await loadBlock(db, now: now);
  if (b == null) return null;
  final mon = mondayOf(now);
  final past = await pastOutcomes(db, b, mon);
  final current = b.weekOf(mon);
  final week = sc.blockWeek(b, mon, past);
  final idx = now.weekday - 1;
  final days = week == null ? <DayCredit>[] : await weekCredits(db, mon);
  final soFar = await weekOutcome(db, mon);
  final left = [
    for (final d in days)
      if (d.date.difference(dayOf(now)).inDays >= 0 &&
          !d.session.isRest &&
          d.credit == 0 &&
          d.status != sc.Intent.skipped.name)
        d,
  ].length;
  final (recDays, feelDays) = await signalDays(db, mon);
  final profile = await loadAppProfile(db) ?? const Profile();

  int? missed;
  sc.Realign? realign;
  if (days.length == 7) {
    for (var i = 0; i < idx; i++) {
      final d = days[i];
      if (!sc.isKeySession(d.session) ||
          d.credit > 0 ||
          d.status == sc.Intent.skipped.name) {
        continue;
      }
      final placed = [for (var j = i + 1; j < 7; j++) days[j].session.key]
          .contains(d.session.key);
      if (placed) continue;
      missed = i;
    }
    if (missed != null) {
      final from = days[idx].credit > 0 ? idx + 1 : idx;
      realign = sc.realignWeek(
        [for (final d in days) d.session],
        missed,
        from,
        available: profile.days,
      );
    }
  }
  final forecast = sc.forecastWeek(soFar, left: left);
  sc.Realign? ease;
  if (days.length == 7 && forecast.bodySaysBack) {
    final from = days[idx].credit > 0 ? idx + 1 : idx;
    final e = sc.easeRest([for (final d in days) d.session], from);
    if (e.changed.isNotEmpty) ease = e;
  }
  final weeks = current < 0
      ? <sc.BlockWeek>[]
      : sc.projectBlock(b, current, past);
  final seen = await db.setting(Keys.coachPhaseSeen);
  final focus = await loadFocus(db);
  return GoalView(
    block: b,
    week: week,
    weeks: weeks,
    history: sc.blockHistory(b, past),
    days: days,
    today: idx,
    soFar: soFar,
    forecast: forecast,
    left: left,
    recDays: recDays,
    feelDays: feelDays,
    phaseSeen: week == null || seen == _phaseKey(b, week.index),
    usualHard: profile.prefs.hardPerWeek,
    next: await loadNext(db),
    focus: focus != null && focus.activeOn(dayOf(now)) ? focus : null,
    missed: missed,
    realign: realign,
    ease: ease,
  );
}

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Writes [r] over this week's plan from [v], marking each changed day with
/// [why]. The missed day (if any) is let go so it isn't carried as well.
Future<void> applyRealign(
  st.TempoDb db,
  GoalView v,
  sc.Realign r, {
  required String why,
}) async {
  final stamp = st.toTs(DateTime.now());
  final rows = await db.planBetween(v.days.first.date, v.days.last.date);
  for (final i in r.changed) {
    final row = rows[i];
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: row.date,
        session: jsonEncode(r.week[i].toJson()),
        original: Value(row.original ?? row.session),
        reason: Value(why),
        adaptedAt: Value(stamp),
        general: row.general,
        algoVersion: const Value(sc.blockAlgo),
      ),
    );
  }
  final m = v.missed;
  if (m != null && r == v.realign) {
    await db.setPlanIntent(
      v.days[m].date,
      sc.Intent.skipped.name,
      source: 'realign',
    );
    await _clearCarried(db, v.days[m].session);
  }
}

/// Fits the missed session back in (see [sc.realignWeek]).
Future<void> rearrangeWeek(st.TempoDb db, GoalView v) async {
  final r = v.realign, m = v.missed;
  if (r == null || m == null) return;
  await applyRealign(
    db,
    v,
    r,
    why:
        '· Rearranged: ${_dayNames[m]}’s ${v.days[m].session.title} fits in here.',
  );
}

/// Lets the missed session go: nothing is added to catch up.
Future<void> letGo(st.TempoDb db, GoalView v) async {
  final m = v.missed;
  if (m == null) return;
  await db.setPlanIntent(
    v.days[m].date,
    sc.Intent.skipped.name,
    source: 'realign',
  );
  await _clearCarried(db, v.days[m].session);
}

/// Makes the rest of the week easy (recovery or feel already low).
Future<void> easeWeek(st.TempoDb db, GoalView v) async {
  final e = v.ease;
  if (e == null) return;
  await applyRealign(
    db,
    v,
    e,
    why: '■ Easy rest of the week: recovery and feel have been low.',
  );
  final carried = await db.setting(Keys.carried);
  if (carried != null && carried.isNotEmpty) {
    await db.putSetting(Keys.carried, '');
  }
}

Future<void> _clearCarried(st.TempoDb db, sc.Session s) async {
  final raw = await db.setting(Keys.carried);
  if (raw == null || raw.isEmpty) return;
  try {
    final c = sc.Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (c.key == s.key) await db.putSetting(Keys.carried, '');
  } on Object {
    await db.putSetting(Keys.carried, '');
  }
}
