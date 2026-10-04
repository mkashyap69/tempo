import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

List<Minute> mins(
  DateTime from,
  int n, {
  int? hr,
  int steps = 0,
  Stage stage = Stage.wake,
}) => [
  for (var i = 0; i < n; i++)
    Minute(
      from.add(Duration(minutes: i)),
      hr: hr,
      steps: steps,
      stage: stage,
    ),
];

void main() {
  group('zones', () {
    test('Tanaka max HR', () {
      expect(maxHrFromAge(31), 186);
    });
    test('zone ranges at 186 match the design', () {
      expect(zoneRange(1, 186), (lo: 93, hi: 111));
      expect(zoneRange(2, 186), (lo: 112, hi: 130));
      expect(zoneRange(4, 186), (lo: 149, hi: 167));
      expect(zoneRange(3, 186), (lo: 131, hi: 148));
      expect(zoneRange(5, 186), (lo: 168, hi: 186));
    });
    test('zoneFor', () {
      expect(zoneFor(80, 186), 0);
      expect(zoneFor(93, 186), 1);
      expect(zoneFor(158, 186), 4);
      expect(zoneFor(186, 186), 5);
    });
    test('time in zones counts below-Z1 as Z1', () {
      expect(timeInZones([60, 100, null, 158], 186), [2, 0, 0, 1, 0]);
      expect(timeInZones([60, 100, null, 158], 186, includeBelow: false), [
        1,
        0,
        0,
        1,
        0,
      ]);
    });
  });

  group('cardio load', () {
    test('learning under 7 days', () {
      expect(cardioLoad([50, 50, 50]).status, LoadStatus.learning);
    });
    test('status thresholds', () {
      expect(loadStatusFor(0.79), LoadStatus.detraining);
      expect(loadStatusFor(0.9), LoadStatus.maintaining);
      expect(loadStatusFor(1.2), LoadStatus.building);
      expect(loadStatusFor(1.31), LoadStatus.overreaching);
    });
    test('acute vs chronic', () {
      final days = [...List.filled(7, 100.0), ...List.filled(21, 60.0)];
      final l = cardioLoad(days);
      expect(l.acute, 100);
      expect(l.chronic, closeTo(70, 1e-9));
      expect(l.status, LoadStatus.overreaching);
      expect(l.percentVsNormal, 43);
    });
    test('history is oldest first', () {
      final h = loadHistory(List.filled(28, 10.0), weeks: 4);
      expect(h.length, 4);
      expect(h.last.acute, 10);
    });
  });

  group('strain target', () {
    test('by recovery', () {
      final t = strainTarget(recovery: 78);
      expect((t.lo, t.hi, t.cap), (13, 16, false));
      expect(strainTarget(recovery: 41).hi, 12);
      expect(strainTarget(recovery: 24).cap, isTrue);
      expect(strainTarget(recovery: 24).hi, 8);
    });
    test('overreaching caps even a green morning', () {
      expect(
        strainTarget(recovery: 80, load: LoadStatus.overreaching).cap,
        isTrue,
      );
    });
    test('calibrating is general 10–14', () {
      final t = strainTarget(calibrating: true);
      expect((t.lo, t.hi, t.general), (10, 14, true));
    });
  });

  group('day state', () {
    test('branch rules', () {
      expect(dayState(recovery: 78), DayState.go);
      expect(dayState(recovery: 78, daysSinceHard: 1), DayState.easeOff);
      expect(dayState(recovery: 50), DayState.easeOff);
      expect(dayState(recovery: 33), DayState.rest);
      expect(
        dayState(recovery: 90, load: LoadStatus.overreaching),
        DayState.rest,
      );
      expect(dayState(recovery: 90, calibrating: true), DayState.general);
    });
  });

  group('sessions', () {
    test('threshold structure and totals', () {
      final s = sessionTemplate('threshold_run');
      expect(s.minutes, 43);
      expect(s.zones, 'Z1–Z4');
      expect(s.structure, '10′ Z2 · 5 × (3′ Z4 / 2′ Z1) · 8′ Z2');
    });
    test('json round trip', () {
      final s = sessionTemplate('tempo_ride');
      final r = Session.fromJson(s.toJson());
      expect(r.structure, s.structure);
      expect(r.sport, Sport.cycling);
    });
    test('session strain is positive and smaller on a busier day', () {
      final s = sessionTemplate('threshold_run');
      final fresh = sessionStrain(s, hrMax: 186, hrRest: 50);
      final later = sessionStrain(s, hrMax: 186, hrRest: 50, dayTrimp: 100);
      expect(fresh, greaterThan(0));
      expect(later, lessThan(fresh));
      expect(sessionStrain(sessionTemplate('rest'), hrMax: 186, hrRest: 50), 0);
    });
    test('fitMinutes trims the longest block', () {
      final s = fitMinutes(sessionTemplate('long_ride'), 60);
      expect(s.minutes, 60);
    });
  });

  group('week plan', () {
    const prefs = CoachPrefs(
      goal: Goal.fitness,
      likes: {Sport.running, Sport.strength, Sport.cycling},
      days: {1, 2, 4, 5, 6, 7},
      maxMinutes: 75,
    );
    test('respects availability and one rest day', () {
      final w = weekPlan(prefs);
      expect(w.length, 7);
      expect(w[2].isRest, isTrue); // Wednesday unavailable
      expect(w.every((s) => s.minutes <= 75), isTrue);
    });
    test('at most two hard days, never back to back', () {
      final w = weekPlan(prefs);
      final hard = [
        for (var i = 0; i < 7; i++)
          if (w[i].isHard) i,
      ];
      expect(hard.length, lessThanOrEqualTo(2));
      for (var i = 1; i < hard.length; i++) {
        expect(hard[i] - hard[i - 1], greaterThanOrEqualTo(2));
      }
    });
    test('all days available still rests once', () {
      final w = weekPlan(
        const CoachPrefs(
          goal: Goal.fitness,
          likes: {Sport.running},
          days: {1, 2, 3, 4, 5, 6, 7},
          maxMinutes: 60,
        ),
      );
      expect(w.where((s) => s.isRest).length, greaterThanOrEqualTo(1));
    });
    test('general plan has no hard sessions', () {
      expect(weekPlan(prefs, general: true).any((s) => s.isHard), isFalse);
    });
  });

  group('adaptation', () {
    List<Session> week() => [
      for (final k in [
        'strength_full',
        'easy_run',
        'rest',
        'threshold_run',
        'strength_lower',
        'long_ride',
        'easy_run',
      ])
        sessionTemplate(k),
    ];
    test('rest morning swaps the hard day and carries it forward', () {
      final a = adaptWeek(week(), 3, DayState.rest, reason: 'Recovery 32%');
      expect(a.week[3].isRest, isTrue);
      expect(a.changes.first.from.key, 'threshold_run');
      // Sunday takes it (Saturday's long ride is not hard, Sunday is easy).
      expect(a.week[6].key, 'threshold_run');
      expect(a.carried, isNull);
    });
    test('ease off turns intervals into the Z2 version', () {
      final a = adaptWeek(week(), 3, DayState.easeOff, reason: 'Recovery 50%');
      expect(a.week[3].key, 'steady_run');
      expect(a.changes.length, greaterThanOrEqualTo(1));
    });
    test('go keeps the plan and takes a carried session', () {
      final carried = sessionTemplate('threshold_run');
      final w = week()..[3] = sessionTemplate('easy_run');
      final a = adaptWeek(
        w,
        6,
        DayState.go,
        reason: 'Recovery 78%',
        carried: carried,
      );
      expect(a.week[6].key, 'threshold_run');
      expect(a.carried, isNull);
    });
    test('go with nothing carried changes nothing', () {
      final a = adaptWeek(week(), 0, DayState.go, reason: 'x');
      expect(a.changes, isEmpty);
    });
  });

  group('activity detection', () {
    final t = DateTime(2026, 10, 4, 11);
    test('a 35-minute ride is found as cycling', () {
      final m = [
        ...mins(t, 10, hr: 70, steps: 5),
        ...mins(t.add(const Duration(minutes: 10)), 35, hr: 136, steps: 0),
        ...mins(t.add(const Duration(minutes: 45)), 10, hr: 70, steps: 5),
      ];
      final a = detectActivities(m, hrMax: 186);
      expect(a.length, 1);
      expect(a.first.duration.inMinutes, 35);
      expect(a.first.sport, Sport.cycling);
      expect(a.first.avgHr, 136);
    });
    test('a walk is found from steps', () {
      final a = detectActivities(mins(t, 20, hr: 95, steps: 100), hrMax: 186);
      expect(a.single.sport, Sport.walking);
    });
    test('short bursts and sleep are ignored', () {
      expect(detectActivities(mins(t, 5, hr: 150), hrMax: 186), isEmpty);
      expect(
        detectActivities(mins(t, 30, hr: 150, stage: Stage.light), hrMax: 186),
        isEmpty,
      );
    });
  });

  group('insights', () {
    test('needs enough nights in both groups', () {
      final i = tagInsight([
        for (var k = 0; k < 4; k++) const TaggedNight(true, 40),
        for (var k = 0; k < 20; k++) const TaggedNight(false, 70),
      ]);
      expect(i.confidence, Confidence.notEnough);
    });
    test('moderate effect', () {
      final i = tagInsight([
        for (final v in [31, 44, 52, 38, 61, 47, 29, 68, 41])
          TaggedNight(true, v.toDouble()),
        for (var k = 0; k < 41; k++)
          TaggedNight(false, 60 + (k % 20).toDouble()),
      ]);
      expect(i.diff, lessThan(-15));
      expect(i.nWith, 9);
      expect(i.confidence, Confidence.moderate);
    });
    test('no clear effect', () {
      final i = tagInsight([
        for (var k = 0; k < 10; k++)
          TaggedNight(k.isEven, 60 + (k % 3).toDouble()),
      ]);
      expect(i.confidence, Confidence.none);
    });
  });

  group('sleep plan', () {
    test('bedtime for 8h10m need, wake 6:50 → 10:30 pm with latency', () {
      expect(bedtimeMinute(8 + 10 / 60, 6 * 60 + 50), 22 * 60 + 30);
    });
    test('median clock wraps midnight', () {
      expect(medianClock([23 * 60 + 50, 10, 23 * 60 + 55]), 23 * 60 + 55);
    });
    test('consistency', () {
      expect(consistency([1380, 1390, 1400, 60]), 0.75);
    });
    test('wake-ups inside a night', () {
      final t = DateTime(2026, 10, 4, 1);
      final n = [
        ...mins(t, 10, stage: Stage.rem),
        ...mins(
          t.add(const Duration(minutes: 10)),
          4,
          stage: Stage.wake,
          steps: 3,
        ),
        ...mins(t.add(const Duration(minutes: 14)), 10, stage: Stage.light),
      ];
      final w = wakeUps(n);
      expect(w.single.minutes, 4);
      expect(w.single.afterStage, Stage.rem);
      expect(w.single.moved, isTrue);
    });
    test('latency counts still minutes before sleep', () {
      final t = DateTime(2026, 10, 4, 23);
      expect(sleepLatency([...mins(t, 3, steps: 20), ...mins(t, 9)]), 9);
    });
    test('quantile', () {
      expect(quantile([1, 2, 3, 4, 5], 0.5), 3);
      expect(quantile([0, 10], 0.1), 1);
      expect(quantile([], 0.5), isNull);
    });
  });
}
