import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/screens/activity_detail.dart';
import 'package:tempo/src/screens/baselines.dart';
import 'package:tempo/src/screens/calendar.dart';
import 'package:tempo/src/screens/cardio_load.dart';
import 'package:tempo/src/screens/coach.dart';
import 'package:tempo/src/screens/data_health.dart';
import 'package:tempo/src/screens/day_timeline.dart';
import 'package:tempo/src/screens/insight_detail.dart';
import 'package:tempo/src/screens/journal.dart';
import 'package:tempo/src/screens/learn.dart';
import 'package:tempo/src/screens/live_workout.dart';
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
import 'package:tempo/src/screens/workouts.dart';
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
