import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/week_review.dart';

ReviewDay day(String key, sc.DayStatus? s) =>
    ReviewDay(DateTime(2026, 11, 23), sc.sessionTemplate(key), s, null);

void main() {
  test('every planned session done wins first', () {
    final w = weekWin(
      days: [
        day('easy_run', sc.DayStatus.done),
        day('threshold_run', sc.DayStatus.done),
        day('easy_ride', sc.DayStatus.doneEasier),
        day('rest', sc.DayStatus.rest),
      ],
      moderateMinutes: 90,
    );
    expect(w, 'Every planned session done.');
  });

  test('key sessions, then minutes, then sleep, then recovery', () {
    final days = [
      day('easy_run', sc.DayStatus.missedDay),
      day('threshold_run', sc.DayStatus.done),
    ];
    expect(
      weekWin(days: days, moderateMinutes: 20),
      'The week’s key session, done.',
    );
    final none = [day('easy_run', sc.DayStatus.missedDay)];
    expect(weekWin(days: none, moderateMinutes: 160), contains('WHO minimum'));
    expect(
      weekWin(days: none, moderateMinutes: 20, bestSleep: (8.1, 'Tuesday')),
      'Best night: 8 h 06 m on Tuesday.',
    );
    expect(
      weekWin(days: none, moderateMinutes: 20, bestRecovery: (81, 'Friday')),
      'Recovery reached 81 on Friday.',
    );
    expect(weekWin(days: none, moderateMinutes: 20), isNull);
  });

  test('one thing: sleep, then strength, then minutes', () {
    expect(
      weekNextThing(
        avgSleep: 6.9,
        need: 7.9,
        strengthDays: 2,
        moderateMinutes: 200,
        bedtime: '22:50',
      ),
      contains('lights out by 22:50'),
    );
    expect(
      weekNextThing(strengthDays: 1, moderateMinutes: 200, bedtime: ''),
      startsWith('One more strength day'),
    );
    expect(
      weekNextThing(strengthDays: 2, moderateMinutes: 120, bedtime: ''),
      '30 more active minutes reaches the WHO minimum.',
    );
    expect(
      weekNextThing(strengthDays: 2, moderateMinutes: 200, bedtime: ''),
      startsWith('Keep it going'),
    );
  });
}
