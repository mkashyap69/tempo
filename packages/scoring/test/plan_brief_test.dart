import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  Session t(String k) => sessionTemplate(k);

  group('effortCue', () {
    test('easy and long sessions use the talk test', () {
      for (final k in ['easy_run', 'long_run', 'easy_ride']) {
        expect(effortCue(t(k)), contains('talk in full sentences'), reason: k);
      }
    });
    test('hard sessions by their work zone', () {
      expect(effortCue(t('vo2_run')), contains('a word or two'));
      expect(effortCue(t('threshold_run')), startsWith('Work pieces'));
      expect(effortCue(t('tempo_run')), isNot(contains('full sentences')));
    });
    test('strength, mobility, rest and race', () {
      expect(effortCue(t('strength_full')), contains('reps'));
      expect(effortCue(t('strength_core')), startsWith('Gentle'));
      expect(effortCue(t('yoga')), startsWith('Gentle'));
      expect(effortCue(t('rest')), startsWith('Rest'));
      expect(effortCue(raceSession(BlockGoal.run10k)), contains('goal pace'));
    });
  });

  group('sessionPurpose', () {
    test('one line per kind', () {
      expect(sessionPurpose(t('long_run')), contains('endurance'));
      expect(sessionPurpose(t('long_ride')), contains('endurance'));
      expect(sessionPurpose(t('threshold_run')), contains('pace'));
      expect(sessionPurpose(t('vo2_run')), contains('top-end'));
      expect(sessionPurpose(t('strength_full')), contains('resilient'));
      expect(sessionPurpose(t('easy_run')), contains('aerobic base'));
      expect(sessionPurpose(t('recovery_run')), contains('recover'));
      expect(sessionPurpose(t('rest')), contains('sinks in'));
    });
  });

  test('effortTag', () {
    expect(effortTag(t('easy_run')), 'Easy');
    expect(effortTag(t('long_run')), 'Moderate');
    expect(effortTag(t('threshold_run')), 'Hard');
  });

  group('moveTargets', () {
    // Mon strength · Tue rest · Wed easy · Thu easy · Fri long ·
    // Sat threshold · Sun rest.
    final week = [
      t('strength_full'),
      t('rest'),
      t('easy_run'),
      t('easy_run'),
      t('long_run'),
      t('threshold_run'),
      t('rest'),
    ];

    test('the long run swaps only where no heavy days touch', () {
      // From Friday (today): Saturday is hard, Sunday follows it.
      expect(moveTargets(week, 4, today: 4), isEmpty);
      // A long run on Tuesday can go to Wed or Thu; Fri and Sun sit next to
      // Saturday's threshold.
      final w = [...week]..[4] = t('easy_run');
      w[1] = t('long_run');
      expect(moveTargets(w, 1, today: 1), [2, 3]);
    });

    test('never into the past, never a race, never onto a key day', () {
      expect(moveTargets(week, 2, today: 3), isEmpty);
      expect(moveTargets(week, 3, today: 3), [6]);
      final race = [...week]..[6] = raceSession(BlockGoal.run10k);
      expect(moveTargets(race, 6, today: 3), isEmpty);
      expect(moveTargets(race, 3, today: 3), isNot(contains(6)));
    });

    test('only onto days you train, unless swapping with rest', () {
      expect(moveTargets(week, 3, today: 2, available: {1, 3, 4, 5, 6}), [2]);
    });

    test('swapDays', () {
      final w = swapDays(week, 4, 6);
      expect(w[4].key, 'rest');
      expect(w[6].key, 'long_run');
      expect(week[4].key, 'long_run');
    });
  });

  group('weekRuleLine', () {
    WeekForecast f(double done, {double rec = 60}) => forecastWeek(
      WeekOutcome(planned: 5, done: done, recovery: rec, feel: 3.5),
      left: 2,
    );

    test('no goal: sessions left', () {
      expect(
        weekRuleLine(phase: null, forecast: null, left: 2),
        '2 sessions left this week.',
      );
      expect(
        weekRuleLine(phase: null, forecast: null, left: 0),
        'Nothing else planned this week.',
      );
    });
    test('patchy week: what holds, what grows', () {
      expect(
        weekRuleLine(phase: Phase.base, forecast: f(1.5), left: 2),
        'Do 1 more session and next week stays the same size; 2 more '
        'sessions and it grows.',
      );
    });
    test('on track and earned', () {
      expect(
        weekRuleLine(phase: Phase.build, forecast: f(3), left: 2),
        'Do 1 more session and next week grows about 5%.',
      );
      expect(
        weekRuleLine(phase: Phase.build, forecast: f(4), left: 1),
        startsWith('Enough done'),
      );
    });
    test('nothing left to hold', () {
      final g = forecastWeek(
        const WeekOutcome(planned: 5, done: 0, recovery: 60, feel: 3.5),
        left: 1,
      );
      expect(
        weekRuleLine(phase: Phase.base, forecast: g, left: 1),
        startsWith('Not enough of the week'),
      );
    });
    test('low recovery and fixed phases', () {
      expect(
        weekRuleLine(phase: Phase.base, forecast: f(3, rec: 30), left: 2),
        startsWith('Recovery has been low'),
      );
      expect(
        weekRuleLine(phase: Phase.taper, forecast: f(3), left: 2),
        '2 sessions left this week. Tapering: don’t add extra.',
      );
      expect(
        weekRuleLine(phase: Phase.race, forecast: f(3), left: 2),
        startsWith('Race week'),
      );
    });
  });
}
