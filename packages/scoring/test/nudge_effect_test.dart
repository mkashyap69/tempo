import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// V7: reminders that change nothing are paused.
void main() {
  List<NudgeTrial> trials(NudgeKind k, int n, int followed) => [
    for (var i = 0; i < n; i++) (kind: k, followed: i < followed),
  ];

  test('owner: 28 wind-downs, in bed by the time twice', () {
    final c = followCounts(trials(NudgeKind.winddown, 28, 2));
    expect(c[NudgeKind.winddown], (n: 28, followed: 2));
    expect(notWorking(c), {NudgeKind.winddown});
  });

  test('a reminder that works stays', () {
    final c = followCounts([
      ...trials(NudgeKind.winddown, 12, 6),
      ...trials(NudgeKind.session, 10, 2),
    ]);
    expect(notWorking(c), isEmpty);
  });

  test('too few to judge, or a kind with no visible effect', () {
    expect(notWorking(followCounts(trials(NudgeKind.winddown, 9, 0))), isEmpty);
    expect(notWorking(followCounts(trials(NudgeKind.brief, 30, 0))), isEmpty);
  });
}
