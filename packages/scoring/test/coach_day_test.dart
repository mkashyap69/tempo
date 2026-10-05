import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

DoneWorkout w(Sport? s, int minutes, {int hard = 0, double strain = 0}) =>
    DoneWorkout(
      start: DateTime(2026, 10, 5, 7),
      minutes: minutes,
      sport: s,
      zoneMinutes: [0, minutes - hard, 0, hard, 0],
      strain: strain,
    );

void main() {
  final easyRun = sessionTemplate('easy_run'); // 35′
  final threshold = sessionTemplate('threshold_run');
  final strength = sessionTemplate('strength_full');

  group('matchSession', () {
    test('80 / 50 % bands', () {
      expect(
        matchSession(easyRun, [w(Sport.running, 28)]).kind,
        MatchKind.done,
      );
      expect(
        matchSession(easyRun, [w(Sport.running, 20)]).kind,
        MatchKind.partial,
      );
      expect(
        matchSession(easyRun, [w(Sport.running, 10)]).kind,
        MatchKind.none,
      );
    });
    test('strain floor counts as done', () {
      expect(
        matchSession(easyRun, [w(Sport.cycling, 10, strain: 6)]).kind,
        MatchKind.done,
      );
    });
    test('sport compatibility', () {
      expect(compatible(easyRun, Sport.cycling), isTrue);
      expect(compatible(easyRun, Sport.walking), isTrue);
      expect(compatible(threshold, Sport.walking), isFalse);
      expect(compatible(strength, Sport.running), isFalse);
      expect(compatible(strength, Sport.strength), isTrue);
      expect(
        matchSession(strength, [w(Sport.running, 60)]).kind,
        MatchKind.none,
      );
    });
    test('hard needs 5 minutes in Z4+', () {
      final m = threshold.minutes;
      expect(
        matchSession(threshold, [w(Sport.running, m, hard: 2)]).kind,
        MatchKind.doneEasier,
      );
      expect(
        matchSession(threshold, [w(Sport.running, m, hard: 12)]).kind,
        MatchKind.done,
      );
    });
    test('rest has nothing to match', () {
      expect(
        matchSession(sessionTemplate('rest'), [w(Sport.running, 60)]).kind,
        MatchKind.none,
      );
    });
  });

  group('deriveStatus', () {
    DayStatus st({
      MatchKind m = MatchKind.none,
      Intent i = Intent.planned,
      int now = 9 * 60,
      int? planned = 7 * 60,
    }) => deriveStatus(
      plan: easyRun,
      intent: i,
      match: SessionMatch(m, 0),
      now: now,
      bedtime: 22 * 60 + 30,
      plannedMinute: planned,
    );
    test('pending until slot + duration + 2 h', () {
      expect(st(now: 9 * 60), DayStatus.pending);
      expect(st(now: 7 * 60 + 35 + 121), DayStatus.missedSlot);
    });
    test('done wins over a manual skip; skip over missed', () {
      expect(st(m: MatchKind.done, i: Intent.skipped), DayStatus.done);
      expect(st(i: Intent.skipped, now: 20 * 60), DayStatus.skipped);
    });
    test('user-marked done', () {
      expect(st(i: Intent.done), DayStatus.done);
    });
    test('missed day an hour before bed', () {
      expect(st(now: 21 * 60 + 30, planned: null), DayStatus.missedDay);
    });
    test('moved, then missed after its new slot', () {
      expect(
        st(i: Intent.moved, planned: 18 * 60, now: 12 * 60),
        DayStatus.moved,
      );
      expect(
        st(i: Intent.moved, planned: 18 * 60, now: 20 * 60 + 40),
        DayStatus.missedDay,
      );
    });
    test('bedtime after midnight', () {
      expect(
        deriveStatus(
          plan: easyRun,
          intent: Intent.planned,
          match: const SessionMatch(MatchKind.none, 0),
          now: 23 * 60 + 45,
          bedtime: 30, // 00:30
          plannedMinute: null,
        ),
        DayStatus.missedDay,
      );
    });
  });

  group('replanToday', () {
    Rescue r(Session s, int now, {DayState state = DayState.go}) => replanToday(
      plan: s,
      status: DayStatus.missedSlot,
      now: now,
      bedtime: 22 * 60 + 30,
      pmSlot: 18 * 60,
      state: state,
    );
    test('table: bedtime 22:30', () {
      // Easy: full at the evening slot.
      expect(r(easyRun, 10 * 60).tier, RescueTier.full);
      expect(r(easyRun, 10 * 60).start, 18 * 60);
      // Hard ends by 18:30: from 17:00 that's too late for 50′+ → easier.
      expect(r(threshold, 17 * 60).tier, RescueTier.easier);
      expect(r(threshold, 17 * 60).session!.isHard, isFalse);
      // 19:30 easy: room until 21:30 → easier (trimmed).
      final late = r(easyRun, 19 * 60 + 30);
      expect(late.tier, anyOf(RescueTier.full, RescueTier.easier));
      expect(
        late.start! + late.session!.minutes,
        lessThanOrEqualTo(21 * 60 + 30),
      );
      // 21:45: nothing fits.
      expect(r(easyRun, 21 * 60 + 45).tier, RescueTier.none);
    });
    test('walk when only a short window is left', () {
      final x = r(easyRun, 21 * 60 + 5);
      expect(x.tier, RescueTier.walk);
      expect(x.session!.minutes, lessThanOrEqualTo(20));
    });
    test('a hard session moves to the evening only with 4 h before bed', () {
      // Bed 22:30: hard must end by 18:30, so it eases.
      expect(r(threshold, 10 * 60).session!.isHard, isFalse);
      // Bed 23:30: ends by 19:30, fits in full from 18:00.
      final x = replanToday(
        plan: threshold,
        status: DayStatus.missedSlot,
        now: 10 * 60,
        bedtime: 23 * 60 + 30,
        pmSlot: 18 * 60,
        state: DayState.go,
      );
      expect(threshold.minutes, lessThanOrEqualTo(90));
      expect(x.tier, RescueTier.full);
      expect(x.session!.isHard, isTrue);
      expect(x.start! + x.session!.minutes, lessThanOrEqualTo(19 * 60 + 30));
    });
    test('ease-off days never rescue the hard version', () {
      final x = r(threshold, 10 * 60, state: DayState.easeOff);
      expect(x.session!.isHard, isFalse);
    });
    test('rest state, already covered and not missed', () {
      expect(r(easyRun, 10 * 60, state: DayState.rest).tier, RescueTier.none);
      expect(
        replanToday(
          plan: easyRun,
          status: DayStatus.missedSlot,
          now: 10 * 60,
          bedtime: 22 * 60,
          pmSlot: 18 * 60,
          state: DayState.go,
          strainSoFar: 12,
          targetLo: 10,
        ).tier,
        RescueTier.alreadyCovered,
      );
      expect(
        replanToday(
          plan: easyRun,
          status: DayStatus.pending,
          now: 10 * 60,
          bedtime: 22 * 60,
          pmSlot: 18 * 60,
          state: DayState.go,
        ).tier,
        RescueTier.none,
      );
    });
  });

  group('rhrFlag', () {
    List<double?> nights(List<double?> recent) => [
      ...recent,
      for (var i = recent.length; i < 41; i++) i.isEven ? 57.0 : 63.0,
    ];
    test('needs 21 baseline nights', () {
      expect(rhrFlag([70, for (var i = 0; i < 20; i++) 60]), RhrFlag.none);
    });
    test('4.9 vs 5.0 bpm', () {
      expect(rhrFlag(nights([64.9, 60, 60, 60, 60, 60, 60])), RhrFlag.none);
      expect(rhrFlag(nights([65, 60, 60, 60, 60, 60, 60])), RhrFlag.elevated);
    });
    test('illness: 10 % over or three nights at +5', () {
      expect(rhrFlag(nights([66.5, 60, 60, 60, 60, 60, 60])), RhrFlag.illness);
      expect(rhrFlag(nights([65, 65, 65, 60, 60, 60, 60])), RhrFlag.illness);
    });
    test('no reading tonight → none', () {
      expect(rhrFlag(nights([null, 70, 70])), RhrFlag.none);
    });
  });

  test('readiness overrides', () {
    expect(readiness(DayState.go, rhr: RhrFlag.elevated), DayState.easeOff);
    expect(readiness(DayState.go, shortNight: true), DayState.easeOff);
    expect(readiness(DayState.easeOff, rhr: RhrFlag.illness), DayState.rest);
    expect(readiness(DayState.general, rhr: RhrFlag.illness), DayState.general);
    expect(readiness(DayState.go), DayState.go);
    expect(shortSleep(5.9, 8), isTrue);
    expect(shortSleep(6.5, 9), isTrue);
    expect(shortSleep(7, 8), isFalse);
    expect(shortSleep(null, 8), isFalse);
  });

  test('monotony', () {
    expect(monotony([0, 0, 0, 0, 0, 0, 0]), 0);
    expect(monotony([50, 50, 50, 50, 50, 50, 50]), 10);
    expect(monotony([100, 0, 100, 0, 100, 0, 100]), closeTo(1.15, .01));
    expect(monotonyHigh([50, 50, 50, 50, 50, 50, 50], 300), isTrue);
    expect(monotonyHigh([50, 50, 50, 50, 50, 50, 50], 400), isFalse);
  });

  test('key sessions carry, easy ones drop', () {
    expect(isKeySession(threshold), isTrue);
    expect(isKeySession(sessionTemplate('long_run')), isTrue);
    expect(isKeySession(easyRun), isFalse);
  });

  test('realign after three missed days', () {
    expect(
      needsRealign([DayStatus.missedDay, DayStatus.done, DayStatus.missedDay]),
      isFalse,
    );
    expect(
      needsRealign([
        DayStatus.missedDay,
        DayStatus.missedDay,
        DayStatus.rest,
        DayStatus.missedDay,
      ]),
      isTrue,
    );
  });

  test('weekly floor', () {
    expect(
      weeklyFloor(
        moderateMinutes: 100,
        strengthDays: 2,
        plannedMinutesLeft: 60,
        plannedStrengthLeft: 0,
      ),
      isNull,
    );
    final g = weeklyFloor(
      moderateMinutes: 60,
      strengthDays: 0,
      plannedMinutesLeft: 40,
      plannedStrengthLeft: 1,
    )!;
    expect(g.minutesShort, 50);
    expect(g.strengthShort, 1);
  });

  group('leverActions', () {
    test('always ends with bedtime', () {
      final a = leverActions(nowMinute: 600, wakeMinute: 420, bedtime: 1350);
      expect(a.single.title, 'In bed by 22:30');
    });
    test('steps behind at 15:00', () {
      final a = leverActions(
        focus: Lever.steps,
        nowMinute: 15 * 60,
        wakeMinute: 7 * 60,
        bedtime: 23 * 60,
        stepsToday: 2000,
      );
      expect(a.first.detail, contains('walk'));
      expect(a.first.done, isFalse);
    });
    test('strength avoids hard days', () {
      final a = leverActions(
        focus: Lever.strength,
        nowMinute: 600,
        wakeMinute: 420,
        bedtime: 1350,
        hardToday: true,
      );
      expect(a.first.title, 'Strength another day');
    });
    test('active minutes per day left', () {
      final a = leverActions(
        focus: Lever.activeMinutes,
        nowMinute: 600,
        wakeMinute: 420,
        bedtime: 1350,
        activeWeek: 90,
        activeTarget: 150,
        daysLeft: 3,
      );
      expect(a.first.title, '20′ in Zone 2+ today');
    });
  });
}
