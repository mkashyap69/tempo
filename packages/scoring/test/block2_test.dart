import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final mon = DateTime(2026, 9, 7); // a Monday
  DateTime week(int i) => mon.add(Duration(days: 7 * i));
  const good = WeekOutcome(planned: 5, done: 5, recovery: 70, feel: 4);
  const meh = WeekOutcome(planned: 5, done: 3, recovery: 55);
  const bad = WeekOutcome(planned: 5, done: 1);
  // Half marathon on Sun 22 Nov: 11 weeks, week 3 lighter, 7–8 peak.
  final half = TrainingBlock(
    goal: BlockGoal.half,
    start: mon,
    event: DateTime(2026, 11, 22),
  );

  group('lastCall', () {
    test('after a lighter week there is no call to report', () {
      final w = blockWeek(half, week(4), [good, good, meh, good])!;
      expect(w.phase, Phase.build);
      expect(w.prevPhase, Phase.deload);
      expect(w.lastCall, isNull);
      expect(w.newPhase, isTrue);
      expect(w.level, 2);
    });
    test('is last week, not the last week that moved', () {
      final w = blockWeek(half, week(3), [good, good, meh])!;
      expect(w.lastCall, WeekCall.hold);
      expect(w.newPhase, isTrue); // base → lighter
      expect(blockWeek(half, week(2), [good, good])!.newPhase, isFalse);
    });
  });

  group('history and projection', () {
    test('history carries each call and the level after it', () {
      final h = blockHistory(half, [good, bad, meh, good]);
      expect(
        [for (final r in h) r.call],
        [WeekCall.stepUp, WeekCall.stepBack, WeekCall.hold, null],
      );
      expect([for (final r in h) r.level], [1, 0, 0, 0]);
      expect(h.last.phase, Phase.deload);
    });

    test('projection keeps the past and steps up from now on', () {
      final p = projectBlock(half, 4, [good, good, good, good]);
      expect(p.length, 11);
      expect(p[4].level, 3); // as it really is
      expect(p[6].level, 5); // two projected step-ups
      expect(p[8].level, 6); // peak holds
      expect(p[10].phase, Phase.race);
      expect(p[10].volume, closeTo(1.3 * raceWeekVolume, 1e-9));
    });

    test('open blocks project a few weeks ahead', () {
      final open = TrainingBlock(goal: BlockGoal.open, start: mon);
      expect(projectBlock(open, 2, [good, good], ahead: 6).length, 9);
      expect(projectBlock(open, 0, const []).length, 9);
    });
  });

  group('forecastWeek', () {
    test('on track: one more session steps up', () {
      final f = forecastWeek(
        const WeekOutcome(planned: 5, done: 3, recovery: 61, feel: 3.5),
        left: 2,
      );
      expect(f.now, WeekCall.hold);
      expect(f.toStepUp, 1);
      expect(f.toHold, 0);
      expect(f.bodySaysBack, isFalse);
    });
    test('patchy: one more avoids a step back', () {
      final f = forecastWeek(
        const WeekOutcome(planned: 5, done: 1.5, recovery: 55, feel: 3.2),
        left: 2,
      );
      expect(f.now, WeekCall.stepBack);
      expect(f.toHold, 1);
      expect(f.toStepUp, 2);
    });
    test('low recovery steps back whatever is done', () {
      final f = forecastWeek(
        const WeekOutcome(planned: 5, done: 3, recovery: 37, feel: 2.3),
        left: 2,
      );
      expect(f.bodySaysBack, isTrue);
      expect(f.best, WeekCall.stepBack);
      expect(f.toHold, isNull);
      expect(f.toStepUp, isNull);
    });
  });

  group('tune-ups', () {
    final tune = TuneUp(goal: BlockGoal.run10k, date: DateTime(2026, 10, 25));

    test('round-trip and fall in their week', () {
      final b = half.withTuneUps([tune]);
      final r = TrainingBlock.fromJson(b.toJson());
      expect(r.tuneUps.single.goal, BlockGoal.run10k);
      expect(r.tuneUps.single.date, DateTime(2026, 10, 25));
      expect(blockWeek(r, week(6), const [])!.tuneUpDay, 7);
      expect(blockWeek(r, week(5), const [])!.tuneUp, isNull);
      // A block saved before tune-ups existed still loads.
      expect(TrainingBlock.fromJson(half.toJson()).tuneUps, isEmpty);
    });

    test('must sit inside the block, two weeks before the race', () {
      expect(tuneUpProblem(half, DateTime(2026, 10, 25)), isNull);
      expect(
        tuneUpProblem(half, DateTime(2026, 9, 1)),
        TuneUpProblem.beforeStart,
      );
      expect(tuneUpProblem(half, DateTime(2026, 11, 8)), isNull);
      expect(tuneUpProblem(half, DateTime(2026, 11, 9)), TuneUpProblem.tooLate);
      final b = half.withTuneUps([tune]);
      expect(tuneUpProblem(b, DateTime(2026, 10, 24)), TuneUpProblem.sameWeek);
      final full = half.withTuneUps([
        for (final d in [4, 11, 18])
          TuneUp(goal: BlockGoal.run5k, date: DateTime(2026, 10, d)),
      ]);
      expect(tuneUpProblem(full, DateTime(2026, 11, 1)), TuneUpProblem.tooMany);
    });

    test('the race replaces the week\'s hard session', () {
      const prefs = CoachPrefs(
        goal: Goal.fitness,
        likes: {Sport.running},
        days: {1, 2, 3, 4, 5, 6, 7},
        maxMinutes: 60,
      );
      final b = half.withTuneUps([tune]);
      final w = weekPlan(
        prefs,
        block: blockWeek(b, week(6), [good, good, good, good, good, good]),
      );
      expect(w[6].key, 'race');
      expect(w[6].title, 'Tune-up · 10K');
      expect(w[6].note, 'Tune-up race');
      // Nothing heavy the two days before; at most one other hard session.
      for (final i in [4, 5]) {
        expect(w[i].isHard || w[i].key.startsWith('long_'), isFalse);
      }
      expect(w.where((s) => s.isHard && s.key != 'race').length, lessThan(2));
    });

    test('a tune-up the day before a midweek day rests the day after', () {
      const prefs = CoachPrefs(
        goal: Goal.fitness,
        likes: {Sport.running},
        days: {1, 2, 3, 4, 5, 6, 7},
        maxMinutes: 60,
      );
      final b = half.withTuneUps([
        TuneUp(goal: BlockGoal.run5k, date: DateTime(2026, 10, 22)), // Thu
      ]);
      final w = weekPlan(prefs, block: blockWeek(b, week(6), const []));
      expect(w[3].key, 'race');
      expect(w[4].isRest, isTrue);
    });

    test('race week ignores a tune-up', () {
      final b = TrainingBlock(
        goal: BlockGoal.half,
        start: mon,
        event: DateTime(2026, 11, 22),
        tuneUps: [TuneUp(goal: BlockGoal.run5k, date: DateTime(2026, 11, 18))],
      );
      expect(blockWeek(b, week(10), const [])!.tuneUp, isNull);
    });
  });

  group('next goal', () {
    test('starts after a recovery week', () {
      expect(nextBlockStart(half), DateTime(2026, 11, 30));
      expect(
        nextBlockStart(TrainingBlock(goal: BlockGoal.open, start: mon)),
        isNull,
      );
    });
    test('lead time', () {
      expect(eventWeeks(DateTime(2026, 10, 8), DateTime(2026, 12, 13)), 10);
      expect(recommendedWeeks(BlockGoal.marathon), 16);
    });
  });
}
