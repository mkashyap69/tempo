import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/block_service.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/longevity_service.dart';
import 'package:tempo/src/core/today.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/screens/activity_detail.dart';
import 'package:tempo/src/screens/baselines.dart';
import 'package:tempo/src/screens/calendar.dart';
import 'package:tempo/src/screens/cardio_load.dart';
import 'package:tempo/src/screens/coach.dart';
import 'package:tempo/src/screens/coach_parts.dart';
import 'package:tempo/src/screens/coach_settings.dart';
import 'package:tempo/src/screens/data_health.dart';
import 'package:tempo/src/screens/feel.dart';
import 'package:tempo/src/screens/goal.dart';
import 'package:tempo/src/screens/goal_setup.dart';
import 'package:tempo/src/screens/nav.dart' show present;
import 'package:tempo/src/core/format.dart' show dayShort;
import 'package:tempo/src/design/components.dart' show Pressable;
import 'package:tempo/src/screens/day_timeline.dart';
import 'package:tempo/src/screens/insight_detail.dart';
import 'package:tempo/src/screens/journal.dart';
import 'package:tempo/src/screens/learn.dart';
import 'package:tempo/src/screens/live_workout.dart';
import 'package:tempo/src/screens/longevity.dart';
import 'package:tempo/src/screens/night_detail.dart';
import 'package:tempo/src/screens/onboarding.dart';
import 'package:tempo/src/screens/recovery.dart';
import 'package:tempo/src/screens/settings.dart';
import 'package:tempo/src/screens/sleep.dart';
import 'package:tempo/src/screens/strain.dart';
import 'package:tempo/src/screens/stress.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/trends.dart';
import 'package:tempo/src/screens/weekly_plan.dart';
import 'package:tempo/src/screens/weekly_report.dart';
import 'package:tempo/src/screens/weekly_review.dart';
import 'package:tempo/src/screens/workouts.dart';
import 'package:tempo/src/screens/band_explorer.dart';
import 'package:tempo/src/screens/workout_detail.dart';
import 'package:tempo/src/state/live_session.dart';
import 'package:tempo/src/state/providers.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// Every screen builds with real derived data, in both themes, without
/// layout overflows or exceptions.
void main() {
  setUpAll(loadFonts);

  Future<void> render(
    WidgetTester t,
    TempoDb db,
    Widget w, {
    double h = 1600,
    Brightness b = Brightness.dark,
    SyncStatus sync = const SyncStatus(),
    BluetoothAdapterState adapter = BluetoothAdapterState.on,
  }) async {
    t.view.physicalSize = Size(390, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, w, b: b, sync: sync, adapter: adapter));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  final screens = <String, (Widget Function(), String)>{
    'Today': (() => const TodayScreen(), 'Today'),
    'Coach': (() => const CoachScreen(standalone: true), 'TODAY’S READINESS'),
    'Cardio load': (() => const CardioLoadScreen(), 'WHAT TO DO THIS WEEK'),
    'Workout detail': (() => const WorkoutDetailScreen(), 'WHY THIS, TODAY'),
    'Weekly plan': (() => const WeeklyPlanScreen(), 'PLANNED VS ACTUAL STRAIN'),
    'Learn': (() => const LearnScreen(), 'How Tempo thinks'),
    'Learn cards': (() => const LearnCardsScreen(), '1 / 6 · RECOVERY'),
    'Recovery': (
      () => const RecoveryScreen(),
      'WHAT DROVE IT · VS YOUR 30-DAY BASELINE',
    ),
    'Strain': (() => const StrainScreen(), 'Time in zones'),
    'Sleep': (() => const SleepScreen(), 'TONIGHT'),
    'Night detail': (
      () => NightDetailScreen(morning: dayOf(DateTime.now())),
      'Overnight heart rate',
    ),
    'Trends': (() => const TrendsScreen(), 'Sleep performance'),
    'Longevity': (() => const LongevityScreen(), 'TEMPO AGE'),
    'Weekly review': (() => const WeeklyReviewScreen(), 'Your week'),
    'Coach notifications': (() => const CoachSettingsScreen(), 'TRAINING TIME'),
    'Day timeline': (() => const DayTimelineScreen(), 'Heart rate'),
    'Activity': (() => const ActivityDetailScreen(id: 1), 'Zones'),
    'Stress': (() => const StressScreen(), 'Through the day'),
    'Baselines': (() => const BaselinesScreen(), 'Resting heart rate'),
    'Calendar': (() => const CalendarScreen(), 'Calendar'),
    'Insight': (
      () => const InsightDetailScreen(tag: 'alcohol'),
      'Next-morning recovery',
    ),
    'Data health': (() => const DataHealthScreen(), 'Wear and gaps'),
    'Workouts': (() => const WorkoutsScreen(), 'Last 7 days'),
    'Band explorer': (() => const BandExplorerScreen(), 'Run explorer'),
    'Journal': (() => const JournalScreen(), 'Yesterday, quickly'),
    'Weekly report': (
      () => const WeeklyReportScreen(),
      'YOUR WEEK IN THREE LINES',
    ),
    'Profile': (() => const SettingsScreen(), 'Profile'),
    'Onboarding': (
      () => const OnboardingScreen(),
      'Know how ready you are, every morning.',
    ),
  };

  for (final b in Brightness.values) {
    for (final e in screens.entries) {
      testWidgets('${e.key} renders (${b.name})', (t) async {
        final db = (await t.runAsync(() => seededDb(days: 30)))!;
        await render(t, db, e.value.$1(), b: b, h: 2000);
        expect(find.text(e.value.$2), findsWidgets);
        await teardown(t, db);
      });
    }
  }

  group('Training goal', () {
    Future<void> half(TempoDb db) => saveBlock(
      db,
      sc.BlockGoal.half,
      event: mondayOf(DateTime.now()).add(const Duration(days: 7 * 11 + 6)),
    );

    for (final b in Brightness.values) {
      testWidgets('card: no goal, then a half marathon (${b.name})', (t) async {
        final db = (await t.runAsync(() => seededDb(days: 30)))!;
        await render(t, db, const GoalCard(), b: b);
        expect(find.text('No training goal'), findsOneWidget);
        await t.runAsync(() => half(db));
        await settle(t);
        expect(find.textContaining('Half marathon'), findsOneWidget);
        expect(find.textContaining('Week 1 of 12 · Base'), findsOneWidget);
        expect(find.textContaining('to go'), findsOneWidget);
        await teardown(t, db);
      });

      testWidgets('goal screen (${b.name})', (t) async {
        final db = (await t.runAsync(() async {
          final db = await seededDb(days: 30);
          await half(db);
          final b = (await loadBlock(db))!;
          await addTuneUp(
            db,
            sc.TuneUp(
              goal: sc.BlockGoal.run10k,
              date: b.start.add(const Duration(days: 7 * 5 + 6)),
            ),
          );
          return db;
        }))!;
        await render(t, db, const GoalScreen(), b: b, h: 3200);
        expect(find.text('Half marathon'), findsOneWidget);
        expect(find.text('Base starts'), findsOneWidget);
        expect(find.text('THE BLOCK'), findsOneWidget);
        expect(find.textContaining('THIS WEEK ·'), findsOneWidget);
        expect(find.text('Sessions'), findsOneWidget);
        expect(find.text('ALSO ON YOUR PLAN'), findsOneWidget);
        expect(find.textContaining('10K tune-up'), findsOneWidget);
        await t.tap(find.text('How the plan grows'));
        await settle(t);
        expect(
          find.text('You earn each step.', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('You earn each step.', findRichText: true),
          findsOneWidget,
        );
        await t.tap(find.text('Got it'));
        await settle(t);
        expect(find.text('Base starts'), findsNothing);
        expect(t.takeException(), isNull);
        await teardown(t, db);
      });

      testWidgets('setting a goal in three steps (${b.name})', (t) async {
        final db = (await t.runAsync(() => seededDb(days: 30)))!;
        await render(
          t,
          db,
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => present<GoalSetupResult>(
                  context,
                  const GoalSetupScreen(mode: SetupMode.newGoal),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          b: b,
          h: 1400,
        );
        await t.tap(find.text('open'));
        await settle(t);
        expect(find.text('What are you training for?'), findsOneWidget);
        await t.tap(find.text('10K'));
        await settle(t);
        await t.tap(find.text('Choose race day'));
        await settle(t);
        expect(find.text('When is the race?'), findsOneWidget);
        final race = mondayOf(
          DateTime.now(),
        ).add(Duration(days: 7 * sc.recommendedWeeks(sc.BlockGoal.run10k) - 1));
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.label == dayShort(race),
          ),
        );
        await settle(t);
        expect(find.textContaining('8 weeks. Enough time'), findsOneWidget);
        await t.tap(find.text('Preview plan'));
        await settle(t);
        expect(find.text('Your 8-week plan'), findsOneWidget);
        await t.tap(find.text('Start plan'));
        await settle(t);
        expect(find.text('open'), findsOneWidget);
        final saved = (await t.runAsync(() => loadBlock(db)))!;
        expect(saved.goal, sc.BlockGoal.run10k);
        expect(saved.weeks, 8);
        expect(t.takeException(), isNull);
        await teardown(t, db);
      });
    }
  });

  group('Morning feel', () {
    for (final b in Brightness.values) {
      testWidgets('check-in card writes the rating (${b.name})', (t) async {
        final db = (await t.runAsync(() => seededDb(days: 3)))!;
        final day = DateTime(2026, 10, 6);
        await render(t, db, FeelCard(day: day), b: b);
        expect(find.text('How do you feel?'), findsOneWidget);
        expect(find.text('Drained'), findsOneWidget);
        await t.tap(find.text('Good'));
        await settle(t, frames: 5);
        final rated = await t.runAsync(() => db.feelSince(day));
        expect(rated!.single.feel, 4);
        await teardown(t, db);
      });
    }

    for (final (fit, word) in [
      (sc.FeelFit.learning, 'Learning'),
      (sc.FeelFit.tracks, 'Tracks'),
      (sc.FeelFit.off, 'Doesn’t match'),
    ]) {
      testWidgets('comparison card: ${fit.name}', (t) async {
        final db = (await t.runAsync(() => seededDb(days: 3)))!;
        await render(
          t,
          db,
          FeelVsRecoveryCard(
            cmp: sc.FeelComparison(
              n: fit == sc.FeelFit.learning ? 5 : 20,
              agree: 12,
              rho: .6,
              fit: fit,
              recoveryHigh: 2,
            ),
          ),
          b: Brightness.light,
        );
        expect(find.text(word), findsOneWidget);
        expect(find.textContaining('Same colour on 12 of'), findsOneWidget);
        await teardown(t, db);
      });
    }
  });

  group('Tempo Coach', () {
    for (final b in Brightness.values) {
      testWidgets('missed morning: rescue card (${b.name})', (t) async {
        final now = DateTime.now();
        final (db, data) = (await t.runAsync(() async {
          final d = await seededDb(days: 30);
          await CoachService(d).swapToday(sc.sessionTemplate('easy_run'), 'x');
          await d.putSetting(Keys.coachSlot, 'am');
          final td = await loadToday(
            d,
            at: DateTime(now.year, now.month, now.day, 11),
          );
          return (d, td);
        }))!;
        expect(data.status, anyOf(sc.DayStatus.missedSlot, sc.DayStatus.done));
        await render(
          t,
          db,
          Scaffold(
            body: ListView(children: [RescueCard(data), SessionActions(data)]),
          ),
          b: b,
        );
        if (data.status == sc.DayStatus.missedSlot && data.rescue.offered) {
          expect(find.text('STILL TIME TODAY'), findsOneWidget);
          expect(find.text('Plan it'), findsOneWidget);
        } else if (data.state == sc.DayState.rest) {
          expect(find.textContaining('rest day now'), findsOneWidget);
        }
        await teardown(t, db);
      });
    }

    testWidgets('rescue offered: Plan it / Skip today', (t) async {
      final now = DateTime.now();
      final (db, data) = (await t.runAsync(() async {
        final d = TempoDb(NativeDatabase.memory());
        await saveAppProfile(d, const Profile());
        await CoachService(d).swapToday(sc.sessionTemplate('easy_run'), 'x');
        await d.putSetting(Keys.coachSlot, 'am');
        final td = await loadToday(
          d,
          at: DateTime(now.year, now.month, now.day, 11),
        );
        return (d, td);
      }))!;
      expect(data.rescue.offered, isTrue);
      await render(
        t,
        db,
        Scaffold(body: ListView(children: [RescueCard(data)])),
      );
      expect(find.text('STILL TIME TODAY'), findsOneWidget);
      expect(find.text('Plan it'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('walk instead of strength: credited, strength stands', (
      t,
    ) async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final (db, data) = (await t.runAsync(() async {
        final d = TempoDb(NativeDatabase.memory());
        await saveAppProfile(d, const Profile());
        await CoachService(d)
            .swapToday(sc.sessionTemplate('strength_full'), 'x');
        await d.addWorkout(
          WorkoutsCompanion.insert(
            start: toTs(day.add(const Duration(hours: 7))),
            end: toTs(day.add(const Duration(hours: 8))),
            sport: const Value('walking'),
            title: 'Walk',
            source: 'band',
            strain: 5,
            trimp: 30,
            zones: '[10,50,0,0,0]',
          ),
        );
        return (d, await loadToday(d, at: day.add(const Duration(hours: 9))));
      }))!;
      expect(data.swap.kind, sc.SwapKind.stands);
      await render(t, db, Scaffold(body: ListView(children: [SwapNote(data)])));
      expect(find.textContaining('Strength is still today'), findsOneWidget);
      expect(find.text('That was my strength session'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('Coach shows status, also-today and week glyphs', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      await render(t, db, const CoachScreen(standalone: true), h: 2600);
      expect(find.text('Tempo Coach'), findsOneWidget);
      expect(find.text('ALSO TODAY'), findsOneWidget);
      expect(find.textContaining('In bed by'), findsWidgets);
      await teardown(t, db);
    });

    testWidgets('Coach at large text: no overflow', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      t.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await render(t, db, const CoachScreen(standalone: true), h: 3600);
      await teardown(t, db);
    });
  });

  group('Longevity', () {
    for (final b in Brightness.values) {
      testWidgets('hero, levers and contributors (${b.name})', (t) async {
        final db = (await t.runAsync(() async {
          final d = await seededDb(days: 30);
          await updateLongevity(d);
          return d;
        }))!;
        await render(t, db, const LongevityScreen(), b: b, h: 3200);
        expect(find.text('WHAT SHAPES IT'), findsOneWidget);
        expect(find.text('HEALTH DETAILS'), findsOneWidget);
        expect(find.text('Trends'), findsOneWidget);
        await teardown(t, db);
      });
    }

    testWidgets('since last week card', (t) async {
      final db = (await t.runAsync(() async {
        final d = await seededDb(days: 40);
        await updateLongevity(d);
        final last = (await d.longevitySince(DateTime(2000))).last;
        final ago = DateTime.now().subtract(const Duration(days: 7));
        await d.putLongevity(
          LongevityCompanion.insert(
            date: dateKey(ago),
            tempoAge: last.tempoAge + .8,
            realAge: last.realAge,
            calibrating: false,
            contributors: '[]',
            algoVersion: longevityAlgo,
          ),
        );
        return d;
      }))!;
      await render(t, db, const LongevityScreen(), h: 3600);
      expect(find.text('SINCE LAST WEEK'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('focus card shows the week and progress', (t) async {
      final db = (await t.runAsync(() async {
        final d = await seededDb(days: 30);
        await updateLongevity(d);
        await setFocus(d, sc.Lever.strength);
        return d;
      }))!;
      await render(t, db, const LongevityScreen(), h: 3200);
      expect(find.text('YOUR FOCUS'), findsOneWidget);
      expect(find.text('Week 1 of 8'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('large text: no overflow', (t) async {
      final db = (await t.runAsync(() async {
        final d = await seededDb(days: 30);
        await updateLongevity(d);
        return d;
      }))!;
      t.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await render(t, db, const LongevityScreen(), h: 4000);
      await teardown(t, db);
    });
  });

  group('Today states', () {
    testWidgets('normal: rings, a plan and the B charts', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      await render(t, db, const TodayScreen());
      expect(find.text('RECOVERY'), findsOneWidget);
      expect(find.text('STRAIN'), findsOneWidget);
      expect(find.text('SLEEP'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Time in zones'), findsOneWidget);
      expect(find.text('Cardio load'), findsOneWidget);
      expect(find.textContaining('Tonight: bed by'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('first day: welcome line and first-week card', (t) async {
      final fresh = (await t.runAsync(emptyPaired))!;
      await render(t, fresh, const TodayScreen());
      expect(find.text('Your first week'), findsOneWidget);
      expect(find.textContaining('Welcome to Tempo.'), findsOneWidget);
      await teardown(t, fresh);
    });

    testWidgets('calibrating: n of 14', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 5)))!;
      await render(t, db, const TodayScreen());
      expect(find.textContaining('of 14'), findsWidgets);
      expect(find.text('Calibrating'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('not paired: connect line and pair banner', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 3, paired: false)))!;
      await render(t, db, const TodayScreen());
      expect(find.text('No band paired'), findsOneWidget);
      expect(find.textContaining('Connect your band'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('no permission: allow banner', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 3)))!;
      await render(
        t,
        db,
        const TodayScreen(),
        adapter: BluetoothAdapterState.unauthorized,
      );
      expect(find.text('Bluetooth access needed'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('sync failed: says where it stopped, one action', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 3)))!;
      await render(
        t,
        db,
        const TodayScreen(),
        sync: const SyncStatus(problem: SyncProblem.failed, failedPct: 41),
      );
      expect(find.text('Sync didn’t finish'), findsOneWidget);
      expect(find.textContaining('41%'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('syncing: progress line', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 3)))!;
      await render(
        t,
        db,
        const TodayScreen(),
        sync: const SyncStatus(running: true, read: 312, total: 504),
      );
      expect(find.text('Reading band · 312 of 504 min'), findsOneWidget);
      await teardown(t, db);
    });

    testWidgets('stale: hedges and offers Sync', (t) async {
      final db = (await t.runAsync(() async {
        final d = await seededDb(days: 20);
        await d.putSetting(
          Keys.lastSync,
          DateTime.now().subtract(const Duration(hours: 14)).toIso8601String(),
        );
        return d;
      }))!;
      await render(t, db, const TodayScreen());
      expect(find.text('Scores are 14 hours old'), findsOneWidget);
      expect(find.textContaining('Yesterday’s data'), findsOneWidget);
      await teardown(t, db);
    });
  });

  group('Live workout', () {
    LiveState state(LivePhase p, {bool guided = true}) => LiveState(
      phase: p,
      sport: sc.Sport.running,
      title: guided ? 'Threshold intervals' : 'Running · open session',
      plan: guided ? sc.sessionTemplate('threshold_run') : null,
      bpm: 158,
      elapsed: const Duration(minutes: 16, seconds: 48),
      trimp: 40,
      zoneSeconds: const [240, 540, 180, 60, 0],
      hrMax: 186,
      dayTrimpBefore: 60,
      target: const sc.StrainTarget(13, 16),
      startedAt: DateTime.now(),
      workoutId: 1,
      avgHr: 142,
      maxHr: 171,
    );

    for (final (name, s, expectText) in [
      ('guided', state(LivePhase.live), 'Rep 2 of 5'),
      (
        'open session',
        state(LivePhase.live, guided: false),
        'Z4 · 149–167 bpm',
      ),
      ('paused', state(LivePhase.paused), 'Resume'),
      ('summary', state(LivePhase.ended), 'How hard did that feel?'),
    ]) {
      testWidgets(name, (t) async {
        final db = (await t.runAsync(() => seededDb(days: 3)))!;
        t.view.physicalSize = const Size(390, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              dbProvider.overrideWithValue(db),
              liveSessionProvider.overrideWith(() => _FixedLive(s)),
            ],
            child: MaterialApp(
              theme: tempoTheme(Brightness.dark),
              home: const LiveWorkoutScreen(),
            ),
          ),
        );
        await settle(t, frames: 10);
        expect(t.takeException(), isNull);
        expect(find.text(expectText), findsOneWidget);
        await teardown(t, db);
      });
    }
  });
}

class _FixedLive extends LiveSession {
  _FixedLive(this.s);
  final LiveState s;
  @override
  LiveState? build() => s;
}
