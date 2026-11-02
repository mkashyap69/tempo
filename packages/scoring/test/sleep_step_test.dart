import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// V1: targets step 15 min a week from your usual times.
void main() {
  int hm(int h, int m) => h * 60 + m;

  test('clockDiff orders evening and after-midnight times', () {
    expect(clockDiff(hm(0, 30), hm(23, 30)), 60);
    expect(clockDiff(hm(23, 4), hm(0, 31)), -87);
  });

  test('stepToward moves at most steps × 15 min, never past the goal', () {
    // Owner: usual bed 00:31, goal 23:04.
    expect(stepToward(hm(0, 31), hm(23, 4), 1), hm(0, 16));
    expect(stepToward(hm(0, 31), hm(23, 4), 3), hm(23, 46));
    expect(stepToward(hm(0, 31), hm(23, 4), 9), hm(23, 4));
    // Wake 9:09 toward 6:15: later steps go earlier in the morning.
    expect(stepToward(hm(9, 9), hm(6, 15), 2), hm(8, 39));
    expect(stepToward(null, hm(6, 15), 1), hm(6, 15));
  });

  test('steppedBedtime asks only one step earlier than usual', () {
    expect(steppedBedtime(goal: hm(23, 40), usual: hm(0, 31)), hm(0, 16));
    // Already in bed by the goal (or within a step): the goal.
    expect(steppedBedtime(goal: hm(23, 40), usual: hm(23, 0)), hm(23, 40));
    expect(steppedBedtime(goal: hm(23, 40), usual: hm(23, 50)), hm(23, 40));
    expect(steppedBedtime(goal: hm(23, 40)), hm(23, 40));
  });

  test('usualClock needs 5 nights', () {
    expect(usualClock([hm(0, 30), hm(1, 0), hm(0, 10), hm(0, 40)]), isNull);
    expect(
      usualClock([hm(0, 30), hm(1, 0), hm(0, 10), hm(0, 40), hm(23, 50)]),
      hm(0, 30),
    );
  });

  test('briefMinute waits until after you usually wake', () {
    expect(briefMinute(hm(6, 30), hm(9, 9)), hm(9, 24));
    expect(briefMinute(hm(6, 30), hm(6, 0)), hm(6, 30));
    expect(briefMinute(hm(6, 30), null), hm(6, 30));
  });
}
