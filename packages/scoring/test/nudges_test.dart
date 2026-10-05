import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  // Monday 5 Oct 2026.
  DateTime t(int h, [int m = 0]) => DateTime(2026, 10, 5, h, m);
  const run = NudgeDay(
    title: 'Easy run',
    minutes: 35,
    rest: false,
    plannedMinute: 7 * 60,
  );
  NudgeContext ctx({
    DateTime? now,
    NudgeDay today = run,
    NudgeDay? tomorrow = run,
    int? morning = 7 * 60,
    int? winddown = 45,
    Rescue? rescue,
    Set<NudgeKind> kinds = defaultKinds,
    int cap = 1,
    Map<NudgeKind, int> ignore = const {},
    bool paused = false,
    bool live = false,
    int? syncAge = 30,
    bool stepsBehind = false,
    int sentLast7 = 0,
  }) => NudgeContext(
    now: now ?? t(5),
    wake: 6 * 60 + 30,
    bedtime: 22 * 60 + 30,
    today: today,
    tomorrow: tomorrow,
    morning: morning,
    winddownBefore: winddown,
    rescue: rescue,
    kinds: kinds,
    cap: cap,
    ignoreStreak: ignore,
    paused: paused,
    live: live,
    syncAgeMinutes: syncAge,
    stepsBehind: stepsBehind,
    leverLine: '4.1k steps so far',
    sentLast7: sentLast7,
  );
  Iterable<NudgeKind> kinds(List<NudgeSpec> s) => s.map((n) => n.kind);

  test('a normal day: brief, session, missed question, wind-down', () {
    final s = planNudges(ctx());
    final today = s.where((n) => n.fireAt.day == 5).toList();
    expect(kinds(today), [
      NudgeKind.session, // 06:45
      NudgeKind.brief, // 07:00
      NudgeKind.winddown, // 21:45
    ]);
    // The pre-scheduled missed question loses the proactive slot to the
    // session reminder (cap 1).
    expect(kinds(s), isNot(contains(NudgeKind.missed)));
  });

  test('cap 2 lets the missed question through, 90 minutes apart', () {
    final s = planNudges(ctx(cap: 2)).where((n) => n.fireAt.day == 5);
    final missed = s.firstWhere((n) => n.kind == NudgeKind.missed);
    expect(missed.fireAt, t(9, 35)); // 07:00 + 35′ + 2 h
    expect(missed.title, 'Did easy run happen?');
    expect(missed.actions.map((a) => a.id), ['done', 'plan_pm', 'skip']);
  });

  test('deterministic ids and a short 48 h horizon', () {
    final a = planNudges(ctx(cap: 2));
    final b = planNudges(ctx(cap: 2));
    expect(a.map((n) => n.id), b.map((n) => n.id));
    expect(a.length, lessThanOrEqualTo(20));
    expect(a.map((n) => n.id).toSet().length, a.length);
    expect(
      a.every((n) => n.fireAt.isBefore(t(5).add(const Duration(hours: 48)))),
      isTrue,
    );
  });

  test('missed slot with a rescue fires now', () {
    final r = Rescue(
      RescueTier.full,
      session: sessionTemplate('easy_run'),
      start: 18 * 60,
    );
    final s = planNudges(
      ctx(
        now: t(11),
        today: const NudgeDay(
          title: 'Easy run',
          minutes: 35,
          rest: false,
          plannedMinute: 7 * 60,
          status: DayStatus.missedSlot,
        ),
        rescue: r,
      ),
    );
    final m = s.firstWhere((n) => n.kind == NudgeKind.missed);
    expect(m.fireAt.difference(t(11)).inMinutes, lessThanOrEqualTo(1));
    expect(m.body, 'Want easy run 35′ at 18:00?');
    expect(m.payload['start'], 18 * 60);
  });

  test('stale sync: no rescue push, no lever nudge', () {
    final r = Rescue(
      RescueTier.full,
      session: sessionTemplate('easy_run'),
      start: 18 * 60,
    );
    final s = planNudges(
      ctx(
        now: t(11),
        syncAge: 400,
        stepsBehind: true,
        today: const NudgeDay(
          title: 'Easy run',
          minutes: 35,
          rest: false,
          plannedMinute: 7 * 60,
          status: DayStatus.missedSlot,
        ),
        rescue: r,
      ),
    );
    expect(kinds(s), isNot(contains(NudgeKind.missed)));
    expect(kinds(s), isNot(contains(NudgeKind.lever)));
  });

  test('lever nudge at 15:00 when nothing is pending', () {
    final s = planNudges(
      ctx(
        now: t(12),
        stepsBehind: true,
        today: const NudgeDay(
          title: 'Rest',
          minutes: 0,
          rest: true,
          status: DayStatus.rest,
        ),
      ),
    );
    final l = s.firstWhere((n) => n.kind == NudgeKind.lever);
    expect(l.fireAt, t(15));
    expect(l.actions.map((a) => a.id), ['got_it', 'not_today']);
  });

  test('quiet hours: nothing proactive between bed and wake', () {
    final s = planNudges(
      ctx(
        today: const NudgeDay(
          title: 'Easy run',
          minutes: 35,
          rest: false,
          plannedMinute: 6 * 60, // reminder 05:45, before wake
        ),
      ),
    );
    expect(
      s.where((n) => n.kind == NudgeKind.session && n.fireAt.day == 5),
      isEmpty,
    );
  });

  test('pause mode keeps only wind-down', () {
    final s = planNudges(ctx(paused: true));
    expect(kinds(s).toSet(), {NudgeKind.winddown});
  });

  test('backoff: 5 ignores pause a kind, 3 slow it to every other day', () {
    expect(
      kinds(planNudges(ctx(ignore: {NudgeKind.session: 5}))),
      isNot(contains(NudgeKind.session)),
    );
    final slowed = planNudges(ctx(ignore: {NudgeKind.session: 3}))
        .where((n) => n.kind == NudgeKind.session)
        .length;
    expect(slowed, 1); // today or tomorrow, not both
  });

  test('ignore streaks reset on any response', () {
    final s = ignoreStreaks([
      (NudgeKind.session, t(9), false),
      (NudgeKind.session, t(8), false),
      (NudgeKind.session, t(7), true),
      (NudgeKind.session, t(6), false),
      (NudgeKind.lever, t(5), true),
    ]);
    expect(s[NudgeKind.session], 2);
    expect(s[NudgeKind.lever], 0);
  });

  test('daily total and weekly budget', () {
    final s = planNudges(ctx(cap: 2, sentLast7: 14));
    expect(kinds(s).where(proactiveKinds.contains), isEmpty);
    final perDay = <int, int>{};
    for (final n in planNudges(ctx(cap: 2))) {
      perDay[n.fireAt.day] = (perDay[n.fireAt.day] ?? 0) + 1;
    }
    expect(perDay.values.every((v) => v <= maxPerDay), isTrue);
  });

  test('live session holds nudges for two hours', () {
    final s = planNudges(ctx(now: t(6), live: true));
    expect(s.where((n) => n.fireAt.isBefore(t(8))), isEmpty);
  });

  test('weekly is opt-in and lands on Sunday', () {
    expect(kinds(planNudges(ctx())), isNot(contains(NudgeKind.weekly)));
    final sat = DateTime(2026, 10, 10, 9);
    final s = planNudges(
      ctx(now: sat, kinds: {...defaultKinds, NudgeKind.weekly}),
    );
    final w = s.firstWhere((n) => n.kind == NudgeKind.weekly);
    expect(w.fireAt.weekday, DateTime.sunday);
  });
}
