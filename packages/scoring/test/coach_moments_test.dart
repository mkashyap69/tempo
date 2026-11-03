import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('pickWin', () {
    test('nothing special: no win', () {
      expect(pickWin(const WinInput(recovery: 60)), isNull);
    });

    test('a 30-day best recovery beats a bedtime streak', () {
      final w = pickWin(
        WinInput(
          recovery: 88,
          recoveryLast30: List.filled(20, 70.0),
          bedtimeKeptNights: 7,
        ),
      )!;
      expect(w.kind, WinKind.recoveryBest);
      expect(w.title, 'Recovery 88% · your best in 30 days');
    });

    test('a best that is still low, or too little history, is no win', () {
      expect(
        pickWin(WinInput(recovery: 55, recoveryLast30: List.filled(20, 40.0))),
        isNull,
      );
      expect(
        pickWin(WinInput(recovery: 90, recoveryLast30: List.filled(5, 40.0))),
        isNull,
      );
    });

    test('streaks only at their marks', () {
      expect(
        pickWin(const WinInput(bedtimeKeptNights: 7))!.kind,
        WinKind.bedtimeStreak,
      );
      expect(pickWin(const WinInput(bedtimeKeptNights: 8)), isNull);
      expect(
        pickWin(const WinInput(stepGoalDays: 14, stepGoal: 8000))!.title,
        '14 days in a row at 8k steps',
      );
    });

    test('a kind sent this week is skipped for the next one', () {
      final w = pickWin(
        const WinInput(
          calibratedToday: true,
          bedtimeKeptNights: 3,
          recentWins: {WinKind.calibrated},
        ),
      )!;
      expect(w.kind, WinKind.bedtimeStreak);
    });

    test('week done and longest distance', () {
      expect(
        pickWin(
          const WinInput(
            weekJustDone: true,
            sessionsDone: 4,
            sessionsPlanned: 4,
          ),
        )!.title,
        'Week done: 4 of 4 sessions',
      );
      expect(
        pickWin(const WinInput(longestKmToday: 8.4, longestKmBefore: 7.1))!
            .kind,
        WinKind.longest,
      );
      expect(
        pickWin(const WinInput(longestKmToday: 7.2, longestKmBefore: 7.1)),
        isNull,
      );
    });
  });

  group('weekGoalCopy', () {
    test('progress and the next session', () {
      final c = weekGoalCopy(
        done: 2,
        planned: 4,
        goal: 'your 10K',
        nextTitle: 'Tempo run 35′',
        nextDay: 'Thursday',
      )!;
      expect(c.$1, '2 of 4 sessions for your 10K');
      expect(c.$2, startsWith('Thursday: Tempo run 35′. 2 to go'));
    });

    test('one left finishes the week; nothing to say when done', () {
      expect(
        weekGoalCopy(
          done: 3,
          planned: 4,
          nextTitle: 'Long run',
          nextDay: 'Sat',
        )!.$2,
        'Sat: Long run finishes the week.',
      );
      expect(weekGoalCopy(done: 4, planned: 4, nextTitle: 'x'), isNull);
      expect(weekGoalCopy(done: 0, planned: 1, nextTitle: 'x'), isNull);
    });
  });

  group('comebackCopy', () {
    test('only on day 3 and day 7', () {
      for (final d in [1, 2, 4, 5, 6, 8, 30]) {
        expect(comebackCopy(daysAway: d, nights: 3), isNull, reason: '$d');
      }
    });

    test('a best recovery leads; else the nights scored', () {
      expect(
        comebackCopy(
          daysAway: 3,
          nights: 3,
          recovery: 82,
          recoveryBest14: 80,
        )!.$1,
        'Recovery 82% today, your best in 2 weeks',
      );
      expect(
        comebackCopy(daysAway: 7, nights: 6, avgSleepH: 7.25)!.$2,
        'Average sleep 7h 15m. Your plan for this week is ready.',
      );
    });
  });

  group('planNudges with coach moments', () {
    const run = NudgeDay(title: 'Easy run', minutes: 30, rest: false);
    NudgeContext ctx(
      DateTime now, {
      Win? win,
      (String, String)? wg,
      (String, String)? cb,
      (String, String)? ins,
    }) => NudgeContext(
      now: now,
      wake: 6 * 60 + 30,
      bedtime: 22 * 60 + 30,
      today: run,
      morning: null,
      win: win,
      weekGoal: wg,
      comeback: cb,
      insight: ins,
    );

    test('an evening win goes at 19:30 with its payload', () {
      final n = planNudges(
        ctx(
          DateTime(2026, 11, 4, 9),
          win: const Win(WinKind.bedtimeStreak, '7 nights', 'Keep going'),
        ),
      ).where((x) => x.kind == NudgeKind.win).single;
      expect(n.fireAt, DateTime(2026, 11, 4, 19, 30));
      expect(n.payload['win'], 'bedtimeStreak');
    });

    test('a morning win goes 90 min after waking', () {
      final n = planNudges(
        ctx(
          DateTime(2026, 11, 4, 6),
          win: const Win(WinKind.recoveryBest, 'Best', 'Push'),
        ),
      ).where((x) => x.kind == NudgeKind.win).single;
      expect(n.fireAt, DateTime(2026, 11, 4, 8));
    });

    test('week goal only on its weekday', () {
      // 4 Nov 2026 is a Wednesday.
      expect(
        planNudges(ctx(DateTime(2026, 11, 4, 8), wg: ('2 of 4', 'Next')))
            .any((x) => x.kind == NudgeKind.weekGoal),
        isTrue,
      );
      expect(
        planNudges(ctx(DateTime(2026, 11, 5, 8), wg: ('2 of 4', 'Next')))
            .any((x) => x.kind == NudgeKind.weekGoal),
        isFalse,
      );
    });

    test('insight is quiet; comeback an hour after waking', () {
      final all = planNudges(
        ctx(
          DateTime(2026, 11, 4, 6),
          ins: ('New', 'Found'),
          cb: ('Back', 'Hi'),
        ),
      );
      expect(
        all.firstWhere((x) => x.kind == NudgeKind.insight).level,
        NudgeLevel.passive,
      );
      expect(
        all.firstWhere((x) => x.kind == NudgeKind.comeback).fireAt,
        DateTime(2026, 11, 4, 7, 30),
      );
    });

    test('the brief leads with the call when given', () {
      final n = planNudges(
        NudgeContext(
          now: DateTime(2026, 11, 4, 5),
          wake: 390,
          bedtime: 1350,
          today: run,
          morning: 7 * 60,
          briefTitle: 'Primed · recovery 78%',
        ),
      ).firstWhere((x) => x.kind == NudgeKind.brief);
      expect(n.title, 'Primed · recovery 78%');
    });
  });
}
