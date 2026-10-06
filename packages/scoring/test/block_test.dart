import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final mon = DateTime(2026, 10, 5); // a Monday
  DateTime week(int i) => mon.add(Duration(days: 7 * i));
  const good = WeekOutcome(planned: 5, done: 5, recovery: 70, feel: 4);
  const meh = WeekOutcome(planned: 5, done: 3, recovery: 55);
  const bad = WeekOutcome(planned: 5, done: 1);

  group('phases', () {
    test('12-week half marathon', () {
      final ps = [
        for (var i = 0; i < 12; i++) eventPhase(i, 12, BlockGoal.half),
      ];
      expect(ps, [
        Phase.base,
        Phase.base,
        Phase.base,
        Phase.deload,
        Phase.build,
        Phase.build,
        Phase.build,
        Phase.deload,
        Phase.peak,
        Phase.peak,
        Phase.taper,
        Phase.race,
      ]);
    });
    test('short 5K block still ends peak, race', () {
      final ps = [
        for (var i = 0; i < 5; i++) eventPhase(i, 5, BlockGoal.run5k),
      ];
      expect(ps.last, Phase.race);
      expect(ps[3], Phase.peak);
      expect(ps.first, Phase.base);
    });
    test('open block: base cycle, then build, every 4th lighter', () {
      expect(
        [for (var i = 0; i < 9; i++) openPhase(i)],
        [
          Phase.base,
          Phase.base,
          Phase.base,
          Phase.deload,
          Phase.build,
          Phase.build,
          Phase.build,
          Phase.deload,
          Phase.build,
        ],
      );
    });
  });

  group('week calls', () {
    test('absorbed, held, stepped back', () {
      expect(weekCall(good), WeekCall.stepUp);
      expect(weekCall(meh), WeekCall.hold);
      expect(weekCall(bad), WeekCall.stepBack);
      // Plan done but feeling rough: back off.
      expect(
        weekCall(const WeekOutcome(planned: 4, done: 4, feel: 2.2)),
        WeekCall.stepBack,
      );
      // Unknown recovery and feel don't block a step up.
      expect(weekCall(const WeekOutcome(planned: 3, done: 2)), WeekCall.stepUp);
    });
  });

  group('blockWeek', () {
    final open = TrainingBlock(goal: BlockGoal.open, start: mon);

    test('levels replay only base and build weeks', () {
      final w = blockWeek(open, week(5), [good, good, good, good, good])!;
      // Weeks 0–2 base (+3), week 3 lighter (no change), week 4 build (+1).
      expect(w.level, 4);
      expect(w.phase, Phase.build);
      expect(w.lastCall, WeekCall.stepUp);
      expect(w.volume, closeTo(1.2, 1e-9));
    });

    test('a bad week steps back, never below 0', () {
      expect(blockWeek(open, week(3), [good, bad, bad])!.level, 0);
      expect(blockWeek(open, week(3), [good, good, bad])!.level, 1);
    });

    test('lighter weeks cut volume', () {
      final w = blockWeek(open, week(3), [good, good, good])!;
      expect(w.phase, Phase.deload);
      expect(w.volume, closeTo(1.15 * deloadVolume, 1e-9));
      expect(w.hard(2), 1);
    });

    test('event: race week has the race day and no hard sessions', () {
      final b = TrainingBlock(
        goal: BlockGoal.run10k,
        start: mon,
        event: DateTime(2026, 11, 29), // Sunday of week 7
      );
      expect(b.weeks, 8);
      final w = blockWeek(b, week(7), const [])!;
      expect(w.phase, Phase.race);
      expect(w.raceDay, 7);
      expect(w.hard(2), 0);
      expect(blockWeek(b, week(8), const []), isNull);
      expect(blockWeek(b, week(-1), const []), isNull);
    });

    test('round-trips through JSON', () {
      final b = TrainingBlock(
        goal: BlockGoal.half,
        start: mon,
        event: DateTime(2027, 1, 10),
      );
      final r = TrainingBlock.fromJson(b.toJson());
      expect((r.goal, r.start, r.event), (b.goal, b.start, b.event));
    });
  });

  group('scaled', () {
    test('intervals change reps, steady sessions their main block', () {
      final t = scaled(sessionTemplate('threshold_run'), 1.4);
      expect(t.structure, '10′ Z2 · 7 × (3′ Z4 / 2′ Z1) · 8′ Z2');
      final e = scaled(sessionTemplate('easy_run'), 1.2);
      expect(e.structure, '5′ Z1 · 30′ Z2 · 5′ Z1');
      final small = scaled(sessionTemplate('easy_run'), .3);
      expect(small.structure, '5′ Z1 · 10′ Z2 · 5′ Z1');
    });
    test('a cap drops whole reps', () {
      final t = scaled(sessionTemplate('vo2_run'), 1.4, cap: 50);
      expect(t.minutes, lessThanOrEqualTo(50));
      expect(t.structure, contains('× (3′ Z5 / 3′ Z1)'));
    });
  });

  group('weekPlan with a block', () {
    const prefs = CoachPrefs(
      goal: Goal.fitness,
      likes: {Sport.cycling, Sport.strength},
      days: {1, 2, 4, 5, 6, 7},
      maxMinutes: 60,
    );

    test('a running event makes the key sessions runs', () {
      final b = TrainingBlock(
        goal: BlockGoal.half,
        start: mon,
        event: DateTime(2027, 1, 3),
      );
      final w = weekPlan(prefs, block: blockWeek(b, week(5), [good, good]));
      expect(
        w.where((s) => s.isHard).every((s) => s.sport == Sport.running),
        isTrue,
      );
      final long = w.firstWhere((s) => s.key == 'long_run');
      // The long run may pass the 60-minute session limit for an event.
      expect(long.minutes, greaterThan(60));
    });

    test('race week: race on race day, rest the day before', () {
      final b = TrainingBlock(
        goal: BlockGoal.run5k,
        start: mon,
        event: DateTime(2026, 11, 8), // Sunday of week 4
      );
      final w = weekPlan(prefs, block: blockWeek(b, week(4), const []));
      expect(w[6].key, 'race');
      expect(w[5].isRest, isTrue);
      expect(w.where((s) => s.isHard && s.key != 'race'), isEmpty);
    });

    test('peak for a 5K uses VO2 intervals', () {
      final b = TrainingBlock(
        goal: BlockGoal.run5k,
        start: mon,
        event: DateTime(2026, 11, 29), // week 7 → weeks 5–6 peak
      );
      final w = weekPlan(prefs, block: blockWeek(b, week(5), const []));
      expect(w.any((s) => s.key == 'vo2_run'), isTrue);
    });

    test('no block plans exactly as before', () {
      expect(
        [for (final s in weekPlan(prefs)) s.structure],
        [for (final s in weekPlan(prefs, block: null)) s.structure],
      );
    });
  });

  test('race day is never adapted', () {
    final w = [
      for (var i = 0; i < 6; i++) sessionTemplate('easy_run'),
      raceSession(BlockGoal.run10k),
    ];
    final a = adaptWeek(w, 6, DayState.rest, reason: 'Recovery 20%');
    expect(a.week[6].key, 'race');
    expect(a.changes, isEmpty);
    expect(isKeySession(raceSession(BlockGoal.run10k)), isFalse);
  });
}
