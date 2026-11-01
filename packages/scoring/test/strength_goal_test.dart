import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// U6: Get stronger as a goal.
void main() {
  final mon = DateTime(2026, 10, 5); // a Monday
  DateTime week(int i) => mon.add(Duration(days: 7 * i));
  const good = WeekOutcome(planned: 5, done: 5, recovery: 70, feel: 4);
  const prefs = CoachPrefs(
    goal: Goal.fitness,
    likes: {Sport.running, Sport.cycling},
    days: {1, 2, 3, 4, 5, 6, 7},
    maxMinutes: 60,
  );
  final b = TrainingBlock(goal: BlockGoal.strength, start: mon);

  test('an open-ended goal named Get stronger', () {
    expect(b.isEvent, isFalse);
    expect(goalName(BlockGoal.strength), 'Get stronger');
    expect(recommendedWeeks(BlockGoal.strength), 0);
    expect(phaseOf(b, 3), Phase.deload);
    expect(phaseOf(b, 5), Phase.build);
    expect(TrainingBlock.fromJson(b.toJson()).goal, BlockGoal.strength);
  });

  test('three lifting days a day apart, cardio easy, no long session', () {
    final w = weekPlan(prefs, block: blockWeek(b, week(5), [good, good, good]));
    final lift = [
      for (var i = 0; i < 7; i++)
        if (w[i].sport == Sport.strength) i,
    ];
    expect(lift.length, 3);
    for (var k = 1; k < lift.length; k++) {
      expect(lift[k] - lift[k - 1], greaterThanOrEqualTo(2));
    }
    expect(
      {for (final i in lift) w[i].key},
      {'strength_lower', 'strength_upper', 'strength_full'},
    );
    expect(w.where((s) => s.isHard), isEmpty);
    expect(w.where((s) => s.key.startsWith('long_')), isEmpty);
  });

  test('your lifting days come first', () {
    final w = weekPlan(
      const CoachPrefs(
        goal: Goal.fitness,
        likes: {Sport.running},
        days: {1, 2, 3, 4, 5, 6, 7},
        maxMinutes: 60,
        liftDays: {2, 4, 6},
      ),
      block: blockWeek(b, week(1), [good]),
    );
    expect(
      [w[1].sport, w[3].sport, w[5].sport],
      [Sport.strength, Sport.strength, Sport.strength],
    );
  });

  test('main lifts: best e1RM at the start and now', () {
    final sets = [
      SetLog(
        exercise: 'back_squat',
        at: mon.add(const Duration(days: 2)),
        kg: 100,
        reps: 5,
      ),
      SetLog(
        exercise: 'back_squat',
        at: week(6).add(const Duration(days: 1)),
        kg: 110,
        reps: 5,
      ),
      SetLog(
        exercise: 'back_squat',
        at: week(6).add(const Duration(days: 3)),
        kg: 100,
        reps: 12,
      ),
    ];
    final p = liftProgress(
      'back_squat',
      sets,
      since: mon,
      now: week(6).add(const Duration(days: 4)),
    );
    expect(p.start, closeTo(100 * (1 + 5 / 30), 1e-9));
    expect(p.now, closeTo(110 * (1 + 5 / 30), 1e-9));
    final early = liftProgress(
      'back_squat',
      sets,
      since: mon,
      now: mon.add(const Duration(days: 5)),
    );
    expect(early.now, isNull);
    expect(mainLifts, contains('deadlift'));
  });
}
