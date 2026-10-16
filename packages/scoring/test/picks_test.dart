import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

final thu = DateTime(2026, 10, 15); // a Thursday

PickContext ctx({
  DayState state = DayState.go,
  bool unwell = false,
  bool shortNight = false,
  int? toBed,
  double strainSoFar = 0,
  Goal goal = Goal.fitness,
  Set<Sport> likes = const {Sport.running, Sport.strength},
  Set<Game> games = const {Game.badminton, Game.tableTennis},
  Session? planned,
  Session? tomorrow,
  List<RecentSession> recent = const [],
  int maxMinutes = 60,
  DateTime? today,
}) => PickContext(
  today: today ?? thu,
  state: state,
  unwell: unwell,
  shortNight: shortNight,
  minutesToBed: toBed,
  strainSoFar: strainSoFar,
  targetHi: 18,
  goal: goal,
  likes: likes,
  games: games,
  planned: planned,
  tomorrow: tomorrow,
  recent: recent,
  maxMinutes: maxMinutes,
);

RecentSession done(
  int daysAgo,
  Sport s, {
  bool hard = false,
  int minutes = 40,
  String? key,
  StrengthFocus? focus,
  Game? game,
}) => RecentSession(
  day: thu.subtract(Duration(days: daysAgo)),
  sport: s,
  hard: hard,
  minutes: minutes,
  key: key,
  focus: focus,
  game: game,
);

void main() {
  test('always a run, a strength session and a game, one recommended', () {
    final p = dailyPicks(ctx());
    expect(p.map((x) => x.kind), [
      PickKind.run,
      PickKind.strength,
      PickKind.play,
    ]);
    expect(p.where((x) => x.recommended), hasLength(1));
    for (final x in p) {
      expect(x.session.detail, isNotNull);
      expect(x.why, isNotEmpty);
      expect(x.session.minutes, lessThanOrEqualTo(60));
    }
  });

  group('levels', () {
    test('go, ease off, rest', () {
      expect(pickLevel(ctx()), 2);
      expect(pickLevel(ctx(state: DayState.easeOff)), 1);
      expect(pickLevel(ctx(shortNight: true)), 1);
      expect(pickLevel(ctx(state: DayState.rest)), 0);
      expect(pickLevel(ctx(unwell: true)), 0);
    });

    test('bedtime and today’s strain', () {
      expect(pickLevel(ctx(toBed: 200)), 1);
      expect(pickLevel(ctx(toBed: 45)), 0);
      expect(pickLevel(ctx(strainSoFar: 18)), 0);
    });

    test('unwell: nothing hard, core recommended', () {
      final p = dailyPicks(ctx(unwell: true));
      expect(p.any((x) => x.session.isHard), isFalse);
      expect((p[0].detail as RunDetail).type, RunType.recovery);
      expect((p[1].detail as StrengthDetail).focus, StrengthFocus.core);
      expect(p[1].recommended, isTrue);
      expect(p[2].session.intensity, Intensity.easy);
    });
  });

  group('run', () {
    test('a recovered day with no recent hard work gets quality', () {
      final run = dailyPicks(ctx())[0];
      expect(run.session.isHard, isTrue);
      final d = run.detail as RunDetail;
      expect([
        RunType.threshold,
        RunType.fartlek,
        RunType.vo2,
        RunType.hills,
      ], contains(d.type));
      expect(d.effort, isNotEmpty);
      expect(run.session.structure, contains('×'));
    });

    test('rotates to the quality type done least recently', () {
      final run = dailyPicks(
        ctx(
          recent: [
            done(9, Sport.running, hard: true, key: 'threshold_run'),
            done(16, Sport.running, hard: true, key: 'fartlek_run'),
            done(20, Sport.running, hard: true, key: 'vo2_run'),
          ],
        ),
      )[0];
      expect((run.detail as RunDetail).type, RunType.hills);
    });

    test('no hard run within 48 h of a hard day', () {
      final run = dailyPicks(ctx(recent: [done(1, Sport.hiit, hard: true)]))[0];
      expect(run.session.isHard, isFalse);
      expect(run.why, contains('48 h'));
    });

    test('two hard days this week already: easy', () {
      final run = dailyPicks(
        ctx(
          recent: [
            done(3, Sport.running, hard: true),
            done(2, Sport.sport, hard: true),
            done(1, Sport.running, minutes: 70, key: 'long_run'),
          ],
        ),
      )[0];
      expect(run.session.isHard, isFalse);
    });

    test('a long run when there has not been one this week', () {
      final run = dailyPicks(ctx(state: DayState.easeOff, maxMinutes: 75))[0];
      expect((run.detail as RunDetail).type, RunType.long);
      expect(run.session.minutes, lessThanOrEqualTo(75));
    });

    test('the coach’s run is kept and recommended when today allows', () {
      final plan = sessionTemplate('threshold_run');
      final p = dailyPicks(ctx(planned: plan));
      expect(p[0].session.key, 'threshold_run');
      expect((p[0].detail as RunDetail).type, RunType.threshold);
      expect(p[0].recommended, isTrue);
      // Not on an ease-off day.
      final e = dailyPicks(ctx(planned: plan, state: DayState.easeOff));
      expect(e[0].session.isHard, isFalse);
    });

    test('goal shapes quality: performance never gets fartlek first', () {
      final run = dailyPicks(ctx(goal: Goal.performance))[0];
      expect((run.detail as RunDetail).type, RunType.threshold);
    });
  });

  group('strength', () {
    test('rotates to the half trained least recently', () {
      final s = dailyPicks(
        ctx(
          recent: [
            done(2, Sport.strength, focus: StrengthFocus.upper),
            done(6, Sport.strength, focus: StrengthFocus.lower),
          ],
        ),
      )[1];
      expect((s.detail as StrengthDetail).focus, StrengthFocus.lower);
      expect(s.session.key, 'strength_lower');
      expect(s.session.title, 'Lower body');
      expect(s.why, contains('6 days'));
    });

    test('upper body before a hard run tomorrow, or after one yesterday', () {
      final before = dailyPicks(
        ctx(
          tomorrow: sessionTemplate('vo2_run'),
          recent: [done(6, Sport.strength, focus: StrengthFocus.upper)],
        ),
      )[1];
      expect((before.detail as StrengthDetail).focus, StrengthFocus.upper);
      final after = dailyPicks(
        ctx(recent: [done(1, Sport.running, minutes: 75)]),
      )[1];
      expect((after.detail as StrengthDetail).focus, StrengthFocus.upper);
    });

    test('exercises carry sets, reps, rest and a home option', () {
      final d = dailyPicks(ctx())[1].detail as StrengthDetail;
      expect(d.exercises, hasLength(6));
      final first = d.exercises.first;
      expect(first.sets, greaterThanOrEqualTo(3));
      expect(first.home, isNotNull);
      expect(d.warmup, isNotEmpty);
    });

    test('dose follows the day and the goal', () {
      final go = strengthExercises(StrengthFocus.lower, Goal.performance, 2);
      expect(go.first.reps, '5');
      expect(go.first.sets, 4);
      final easy = strengthExercises(StrengthFocus.lower, Goal.performance, 1);
      expect(easy.first.sets, 3);
      final circuit = strengthDetail(StrengthFocus.full, Goal.fatLoss, 2);
      expect(circuit.circuit, isTrue);
    });

    test('behind on strength late in the week: strength recommended', () {
      final p = dailyPicks(ctx(today: DateTime(2026, 10, 16))); // Friday
      expect(p[1].recommended, isTrue);
    });
  });

  group('play', () {
    test('the game played least recently, sized to the day', () {
      final go = dailyPicks(
        ctx(recent: [done(2, Sport.sport, game: Game.badminton)]),
      )[2];
      expect((go.detail as PlayDetail).game, Game.tableTennis);
      expect(go.session.title, 'Table tennis');
      expect((go.detail as PlayDetail).format, contains('match'));
      final easy = dailyPicks(ctx(state: DayState.easeOff))[2];
      expect((easy.detail as PlayDetail).format, contains('no competitive'));
      expect(easy.session.isHard, isFalse);
    });

    test('no games: another liked sport, else a brisk walk', () {
      final ride = dailyPicks(
        ctx(games: {}, likes: {Sport.running, Sport.cycling}),
      )[2];
      expect(ride.session.sport, Sport.cycling);
      final walk = dailyPicks(ctx(games: {}, likes: {Sport.running}))[2];
      expect(walk.session.title, 'Brisk walk');
      expect(walk.why, contains('Profile'));
    });

    test('game names in workout titles', () {
      expect(gameInTitle('Table tennis'), Game.tableTennis);
      expect(gameInTitle('TABLE_TENNIS'), Game.tableTennis);
      expect(gameInTitle('Morning run'), isNull);
    });
  });

  test('details survive the plan’s JSON round trip', () {
    for (final p in dailyPicks(ctx())) {
      final back = Session.fromJson(p.session.toJson());
      expect(back.detail?.toJson(), p.detail.toJson());
      expect(back.title, p.session.title);
    }
    // Old plans without a detail still load.
    expect(
      Session.fromJson(sessionTemplate('easy_run').toJson()).detail,
      isNull,
    );
  });

  test('every new template exists and eases to something real', () {
    for (final k in [
      'recovery_run',
      'strides_run',
      'tempo_run',
      'hill_run',
      'fartlek_run',
      'strength_upper',
      'strength_core',
    ]) {
      final s = sessionTemplate(k);
      expect(sessionTemplate(easierKeyFor(s)).isHard, isFalse);
    }
  });
}
