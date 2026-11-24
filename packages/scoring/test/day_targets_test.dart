import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  DayTargetsInput input({
    Goal goal = Goal.fatLoss,
    String? session = 'Easy run',
    DayStatus? status = DayStatus.pending,
    int? steps = 3000,
    bool? habit,
    double? protein,
    double? proteinTarget,
    int? nightBed,
  }) => DayTargetsInput(
    goal: goal,
    weightKg: 80,
    stepGoal: 8000,
    bedMinute: 22 * 60 + 30,
    wakeMinute: 6 * 60 + 30,
    sessionTitle: session,
    sessionMinutes: 40,
    status: status,
    steps: steps,
    habitAnswer: habit,
    proteinGrams: protein,
    proteinTarget: proteinTarget,
    nightBedMinute: nightBed,
  );

  test('session, steps, habit and sleep, in that order', () {
    final t = dayTargets(input());
    expect(
      [for (final x in t) x.kind],
      [
        TargetKind.session,
        TargetKind.steps,
        TargetKind.habit,
        TargetKind.sleep,
      ],
    );
    expect(t[1].sub, '3,000 so far · 5,000 to go');
    expect(t[2].title, 'Protein with each meal');
    expect(t[2].sub, 'About 128–160 g a day over 3–4 meals');
    expect(t[3].title, 'Bed by 22:30');
    expect(t[3].sub, 'Up at 06:30 (8 h) · checked against your sleep');
    final s = summarise(t);
    expect((s.done, s.total), (0, 4));
    expect(s.next!.kind, TargetKind.session);
  });

  test('a rest day or no plan has no session target', () {
    expect(dayTargets(input(session: null)).length, 3);
    expect(dayTargets(input(status: DayStatus.rest)).length, 3);
  });

  test('steps tick at the goal; no steps stays open', () {
    final t = dayTargets(input(steps: 8200));
    expect(t[1].state, TargetState.done);
    expect(t[1].sub, '8,200 today');
    expect(dayTargets(input(steps: null))[1].state, TargetState.open);
  });

  test('done session counts; skipped leaves the count', () {
    final done = summarise(dayTargets(input(status: DayStatus.doneEasier)));
    expect((done.done, done.total), (1, 4));
    expect(done.next!.kind, TargetKind.steps);
    final skipped = summarise(dayTargets(input(status: DayStatus.skipped)));
    expect((skipped.done, skipped.total), (0, 3));
  });

  test('habit by goal, ticked by hand or by protein from Health', () {
    final w = dayTargets(input(goal: Goal.wellbeing));
    expect(w[2].title, 'Morning daylight');
    expect(w[2].journalKey, 'daylight');
    expect(dayTargets(input(habit: true))[2].state, TargetState.done);
    final health = dayTargets(input(protein: 150, proteinTarget: 145))[2];
    expect(health.state, TargetState.done);
    expect(health.auto, isTrue);
    expect(health.sub, '150 of 145 g from Health');
    expect(
      dayTargets(input(protein: 90, proteinTarget: 145))[2].state,
      TargetState.open,
    );
  });

  test('sleep ticks from a bedtime within 15 min, across midnight', () {
    expect(dayTargets(input(nightBed: 22 * 60 + 40))[3].done, isTrue);
    expect(dayTargets(input(nightBed: 23 * 60))[3].done, isFalse);
    expect(dayTargets(input(nightBed: 30))[3].done, isFalse);
  });

  test('everything done has no next', () {
    final s = summarise(
      dayTargets(
        input(
          status: DayStatus.done,
          steps: 9000,
          habit: true,
          nightBed: 22 * 60,
        ),
      ),
    );
    expect((s.done, s.total, s.next), (4, 4, null));
    expect(s.share, 1);
  });
}
