import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// U3: minutes per day, a week template and training around an injury.
void main() {
  final mon = DateTime(2026, 10, 5); // a Monday
  DateTime week(int i) => mon.add(Duration(days: 7 * i));
  const good = WeekOutcome(planned: 5, done: 5, recovery: 70, feel: 4);
  bool heavy(Session s) => s.isHard || s.key.startsWith('long_');

  CoachPrefs prefs({
    Map<int, int> dayMinutes = const {},
    int? longDay,
    Set<int> liftDays = const {},
    int? hardSessions,
    Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  }) => CoachPrefs(
    goal: Goal.performance,
    likes: const {Sport.running, Sport.strength},
    days: days,
    maxMinutes: 90,
    dayMinutes: dayMinutes,
    longDay: longDay,
    liftDays: liftDays,
    hardSessions: hardSessions,
  );

  test('defaults are unchanged', () {
    final a = weekPlan(prefs());
    final b = weekPlan(
      const CoachPrefs(
        goal: Goal.performance,
        likes: {Sport.running, Sport.strength},
        days: {1, 2, 3, 4, 5, 6, 7},
        maxMinutes: 90,
      ),
    );
    expect([for (final s in a) s.key], [for (final s in b) s.key]);
  });

  test('minutes per day cap each day', () {
    final w = weekPlan(prefs(dayMinutes: {1: 30, 2: 30, 3: 30, 4: 30, 5: 30}));
    for (var i = 0; i < 5; i++) {
      expect(w[i].minutes, lessThanOrEqualTo(30), reason: 'day ${i + 1}');
    }
  });

  test('long session on the pinned day, neighbours not hard', () {
    final w = weekPlan(prefs(longDay: 3));
    expect(w[2].key, startsWith('long_'));
    expect(w[1].isHard, isFalse);
    expect(w[3].isHard, isFalse);
  });

  test('lifting days are strength; legs fresh before hard or long', () {
    final b = TrainingBlock(
      goal: BlockGoal.half,
      start: mon,
      event: DateTime(2027, 1, 3),
    );
    final w = weekPlan(
      prefs(longDay: 7, liftDays: {1, 6}),
      block: blockWeek(b, week(5), [good, good]),
    );
    expect(w[0].sport, Sport.strength);
    expect(w[5].key, 'strength_upper'); // Saturday, before Sunday's long run
    expect(w[6].key, 'long_run');
    expect(
      w.where((s) => s.isHard).every((s) => s.sport == Sport.running),
      isTrue,
    );
    // Never two heavy days together.
    for (var i = 0; i < 6; i++) {
      expect(heavy(w[i]) && heavy(w[i + 1]), isFalse, reason: 'day ${i + 1}');
    }
  });

  test('hard sessions a week as set', () {
    expect(weekPlan(prefs(hardSessions: 0)).where((s) => s.isHard), isEmpty);
    expect(weekPlan(prefs(hardSessions: 3)).where((s) => s.isHard).length, 3);
  });

  test('the forced rest day avoids pinned days', () {
    final w = weekPlan(prefs(liftDays: {3}));
    expect(w[2].sport, Sport.strength);
    expect(w.where((s) => s.isRest).length, 1);
  });

  group('injury', () {
    const likes = {Sport.running, Sport.cycling, Sport.strength};
    final run = sessionTemplate('threshold_run');
    test('no running: rides keep the effort, nothing runs', () {
      final w = limitedWeek(
        weekPlan(prefs()),
        TrainingLimit.noRunning,
        likes: likes,
      );
      expect(w.any((s) => s.sport == Sport.running), isFalse);
      expect(
        limited(run, TrainingLimit.noRunning, likes: likes).key,
        'tempo_ride',
      );
      expect(
        limited(run, TrainingLimit.noRunning, likes: {Sport.running}).key,
        'strength_upper',
      );
      expect(
        limited(
          sessionTemplate('easy_run'),
          TrainingLimit.noRunning,
          likes: {Sport.running},
        ).key,
        'easy_walk',
      );
    });
    test('upper body only: upper strength or rest', () {
      final w = limitedWeek(
        weekPlan(prefs(liftDays: {1})),
        TrainingLimit.upperOnly,
        likes: likes,
      );
      for (final s in w) {
        expect(s.isRest || s.key == 'strength_upper', isTrue, reason: s.key);
      }
      expect(w.any((s) => s.key == 'strength_upper'), isTrue);
    });
    test('race day and no limit stay as they are', () {
      final race = raceSession(BlockGoal.half);
      expect(limited(race, TrainingLimit.noRunning, likes: likes), same(race));
      expect(limited(run, TrainingLimit.none, likes: likes), same(run));
    });
  });
}
