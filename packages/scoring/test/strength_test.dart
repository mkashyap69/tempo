import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final d0 = DateTime(2026, 10, 1, 18);
  SetLog s(String ex, double kg, int reps, {int day = 0, int? rir}) => SetLog(
    exercise: ex,
    at: d0.add(Duration(days: day)),
    kg: kg,
    reps: reps,
    rir: rir,
  );

  group('library', () {
    test('ids unique, about 150, home swaps exist', () {
      final ids = [for (final e in exerciseLibrary) e.id];
      expect(ids.toSet().length, ids.length);
      expect(ids.length, greaterThanOrEqualTo(150));
      for (final e in exerciseLibrary) {
        if (e.home != null) {
          expect(exerciseById[e.home], isNotNull, reason: e.id);
        }
      }
    });

    test('every exercise the picks prescribe is in the library', () {
      for (final f in StrengthFocus.values) {
        for (final g in Goal.values) {
          for (final x in strengthExercises(f, g, 2)) {
            expect(exerciseByName(x.name), isNotNull, reason: x.name);
          }
        }
      }
    });

    test('load steps by equipment', () {
      expect(exerciseById['back_squat']!.stepKg, 2.5);
      expect(exerciseById['dumbbell_curl']!.stepKg, 2);
      expect(exerciseById['lat_pulldown']!.stepKg, 5);
      expect(exerciseById['back_squat']!.lower, isTrue);
      expect(exerciseById['bench_press']!.lower, isFalse);
    });
  });

  test('e1RM (Epley), only for 1–10 reps with load', () {
    expect(e1rm(100, 1), 100);
    expect(e1rm(100, 5), closeTo(116.67, .01));
    expect(e1rm(100, 12), isNull);
    expect(e1rm(0, 5), isNull);
    final ss = sessionsOf('back_squat', [
      s('back_squat', 100, 5),
      s('back_squat', 90, 8, day: 3),
      s('bench_press', 60, 8),
    ]);
    expect(ss.length, 2);
    expect(ss.first.bestE1rm, closeTo(116.67, .01));
    expect(ss.last.volume, 720);
  });

  group('double progression', () {
    final squat = exerciseById['back_squat']!;
    List<ExerciseSession> h(List<SetLog> xs) => sessionsOf('back_squat', xs);

    test('top of the range on every set with reps to spare: add a step', () {
      final t = nextTarget(
        squat,
        h([for (var i = 0; i < 3; i++) s('back_squat', 80, 10, rir: 2)]),
        range: (8, 10),
        sets: 3,
      )!;
      expect(t.kg, 82.5);
      expect(t.reps, 8);
      expect(t.why, contains('Up 2.5 kg'));
    });

    test('top reached but at failure: same weight', () {
      final t = nextTarget(
        squat,
        h([for (var i = 0; i < 3; i++) s('back_squat', 80, 10, rir: 0)]),
        range: (8, 10),
        sets: 3,
      )!;
      expect(t.kg, 80);
    });

    test('in the range: same weight, one more rep', () {
      final t = nextTarget(
        squat,
        h([s('back_squat', 80, 9), s('back_squat', 80, 8)]),
        range: (8, 10),
        sets: 3,
      )!;
      expect(t.kg, 80);
      expect(t.reps, 9);
    });

    test('missed twice: hold; three times: 10 % off', () {
      final miss = [
        for (var d = 0; d < 3; d++) s('back_squat', 100, 5, day: d * 3),
      ];
      expect(
        nextTarget(squat, h(miss.sublist(1)), range: (6, 8), sets: 3)!.why,
        contains('two sessions'),
      );
      expect(nextTarget(squat, h(miss), range: (6, 8), sets: 3)!.kg, 90);
    });

    test('low recovery holds the weight and drops a set; lighter week', () {
      final hist = h([
        for (var i = 0; i < 3; i++) s('back_squat', 80, 10, rir: 2),
      ]);
      final hold = nextTarget(
        squat,
        hist,
        range: (8, 10),
        sets: 4,
        day: LiftDay.hold,
      )!;
      expect(hold.kg, 80);
      expect(hold.sets, 3);
      final light = nextTarget(
        squat,
        hist,
        range: (8, 10),
        sets: 4,
        day: LiftDay.lighter,
      )!;
      expect(light.sets, 2);
    });

    test('no history or a bodyweight move: no target', () {
      expect(nextTarget(squat, const [], range: (8, 10), sets: 3), isNull);
      expect(
        nextTarget(
          exerciseById['push_up']!,
          sessionsOf('push_up', [s('push_up', 0, 15)]),
          range: (8, 12),
          sets: 3,
        ),
        isNull,
      );
    });

    test('rep ranges', () {
      expect(parseRepRange('8–12'), (8, 12));
      expect(parseRepRange('5'), (5, 5));
      expect(parseRepRange('30 s'), isNull);
    });
  });

  group('freshness', () {
    test('squats tire legs, not arms; it fades over days', () {
      final sets = [for (var i = 0; i < 5; i++) s('back_squat', 100, 5)];
      final now = d0.add(const Duration(hours: 2));
      final f = freshness(muscleLoad(sets, now));
      expect(f[Muscle.quads]!, lessThan(50));
      expect(f[Muscle.biceps], 100);
      expect(lowerFreshness(f), lessThan(upperFreshness(f)));
      final later = freshness(
        muscleLoad(sets, now.add(const Duration(days: 4))),
      );
      expect(later[Muscle.quads]!, greaterThan(f[Muscle.quads]!));
      expect(later[Muscle.quads]!, greaterThan(80));
    });

    test('easy sets (4+ in reserve) do not count; runs load the legs', () {
      final f = freshness(muscleLoad([s('back_squat', 60, 5, rir: 5)], d0));
      expect(f[Muscle.quads], 100);
      final run = freshness(
        muscleLoad(
          const [],
          d0,
          cardio: [LegCardio(at: d0, minutes: 60, hard: true)],
        ),
      );
      expect(run[Muscle.calves]!, lessThan(50));
      expect(run[Muscle.chest], 100);
    });
  });

  test('set load for strain', () {
    expect(setTrimp(s('bench_press', 60, 8, rir: 5)), 0);
    expect(
      setTrimp(s('bench_press', 60, 8, rir: 0)),
      greaterThan(setTrimp(s('bench_press', 60, 8, rir: 2))),
    );
    // Heavy low-rep sets count more, long light ones less (algo 10).
    expect(
      setTrimp(s('bench_press', 90, 3)),
      closeTo(1.15 * setTrimp(s('bench_press', 60, 8)), 1e-9),
    );
    expect(
      setTrimp(s('bench_press', 30, 20)),
      closeTo(.85 * setTrimp(s('bench_press', 60, 8)), 1e-9),
    );
    final sets = [for (var i = 0; i < 15; i++) s('bench_press', 60, 8)];
    expect(trimpFromSets(sets), closeTo(24, 1e-9));
    expect(
      strengthCorrection(hrTrimp: 10, setsTrimp: trimpFromSets(sets)),
      closeTo(14, 1e-9),
    );
    expect(
      strengthCorrection(hrTrimp: 10, rpe: 7, minutes: 60, setsTrimp: 5),
      closeTo(.11 * 420 - 10, 1e-9),
    );
  });

  group('picks use freshness', () {
    PickContext ctx(Map<Muscle, double>? fr) => PickContext(
      today: DateTime(2026, 10, 7),
      state: DayState.go,
      likes: const {Sport.strength, Sport.running},
      freshness: fr,
    );
    StrengthDetail detail(PickContext c) =>
        dailyPicks(c)
                .firstWhere((p) => p.kind == PickKind.strength)
                .session
                .detail
            as StrengthDetail;

    test('tired legs: upper body', () {
      final fr = freshness(
        muscleLoad([
          for (var i = 0; i < 8; i++) s('back_squat', 100, 5),
        ], DateTime(2026, 10, 6, 20)),
      );
      final p = dailyPicks(ctx(fr))
          .firstWhere((p) => p.kind == PickKind.strength);
      expect((p.session.detail as StrengthDetail).focus, StrengthFocus.upper);
      expect(p.why, contains('% fresh'));
    });

    test('tired upper body: legs', () {
      final fr = freshness(
        muscleLoad([
          for (var i = 0; i < 8; i++) s('bench_press', 80, 5),
        ], DateTime(2026, 10, 6, 20)),
      );
      expect(detail(ctx(fr)).focus, StrengthFocus.lower);
    });

    test('everything fresh: full body', () {
      expect(
        detail(ctx(freshness(muscleLoad(const [], DateTime(2026))))).focus,
        StrengthFocus.full,
      );
    });

    test('exercise targets survive the plan JSON', () {
      final e = const Exercise(
        'Back squat',
        sets: 3,
        reps: '6–8',
      ).withTarget(82.5, 3, '8', 'Up 2.5 kg');
      final back = Exercise.fromJson(e.toJson());
      expect(back.kg, 82.5);
      expect(back.target, 'Up 2.5 kg');
    });
  });
}
