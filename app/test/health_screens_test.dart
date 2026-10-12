import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/screens/onboarding.dart';
import 'package:tempo/src/screens/activity_detail.dart';
import 'package:tempo/src/screens/baselines.dart';
import 'package:tempo/src/screens/coach.dart';
import 'package:tempo/src/screens/data_health.dart';
import 'package:tempo/src/screens/day_timeline.dart';
import 'package:tempo/src/screens/live_workout.dart';
import 'package:tempo/src/screens/longevity.dart';
import 'package:tempo/src/screens/night_detail.dart';
import 'package:tempo/src/screens/recovery.dart';
import 'package:tempo/src/screens/settings.dart';
import 'package:tempo/src/screens/sleep.dart';
import 'package:tempo/src/screens/strain.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/trends.dart';
import 'package:tempo/src/screens/workouts.dart';
import 'package:tempo/src/state/live_session.dart';

import 'support/harness.dart';
import 'support/health_fake.dart';
import 'support/seed.dart';

/// Every screen a Health user reaches builds from Health-derived data,
/// shows Health wording and none of the band's.
void main() {
  setUpAll(loadFonts);

  final screens = <String, (Widget Function(), List<String>, List<String>)>{
    'Today': (
      () => const TodayScreen(),
      ['Today'],
      ['No band paired', 'Bluetooth access needed', 'Band not connected'],
    ),
    'Recovery': (
      () => const RecoveryScreen(),
      ['HRV (RMSSD), overnight'],
      ['Stress index, overnight'],
    ),
    'Strain': (() => const StrainScreen(), ['Time in zones'], []),
    'Sleep': (() => const SleepScreen(), ['TONIGHT'], ['Smart alarm']),
    'Night detail': (
      () => NightDetailScreen(
        morning: dayOf(DateTime.now()).subtract(const Duration(days: 1)),
      ),
      ['Overnight heart rate'],
      [],
    ),
    'Trends': (() => const TrendsScreen(), ['HRV'], ['Stress index']),
    'Day timeline': (() => const DayTimelineScreen(), ['Heart rate'], []),
    'Workouts': (() => const WorkoutsScreen(), ['Last 7 days'], []),
    'Activity': (() => const ActivityDetailScreen(id: 1), ['Zones'], []),
    'Baselines': (() => const BaselinesScreen(), ['Resting heart rate'], []),
    'Longevity': (() => const LongevityScreen(), ['TEMPO AGE'], []),
    'Coach': (
      () => const CoachScreen(standalone: true),
      ['TODAY’S READINESS'],
      [],
    ),
    'Data health': (
      () => const DataHealthScreen(),
      ['Wear and gaps', 'Health Connect'],
      ['Battery', 'Re-download band history', 'Band explorer'],
    ),
    'Profile': (
      () => const SettingsScreen(),
      ['Health Connect', 'DATA SOURCE', 'Health access'],
      ['BAND SETTINGS', 'Re-pair or change band', 'Rewrite band settings'],
    ),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key} on Health Connect', (t) async {
      final db = (await t.runAsync(() => healthDb(nights: 20)))!;
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, e.value.$1()));
      await settle(t);
      expect(t.takeException(), isNull);
      for (final s in e.value.$2) {
        expect(find.textContaining(s), findsWidgets, reason: s);
      }
      for (final s in e.value.$3) {
        expect(find.textContaining(s), findsNothing, reason: s);
      }
      await teardown(t, db);
    });
  }

  testWidgets('a live workout is a timer on Health', (t) async {
    final db = (await t.runAsync(() => healthDb(nights: 3)))!;
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const LiveWorkoutScreen()));
    await settle(t);
    final container = ProviderScope.containerOf(
      t.element(find.byType(LiveWorkoutScreen)),
    );
    await t.runAsync(
      () => container
          .read(liveSessionProvider.notifier)
          .start(sport: sc.Sport.running),
    );
    await settle(t, frames: 5);
    final s = container.read(liveSessionProvider)!;
    expect(s.timerOnly, isTrue);
    expect(s.phase, LivePhase.live);
    expect(find.textContaining('HR from Health later'), findsOneWidget);
    expect(t.takeException(), isNull);
    // Too short to keep; ending stops the clock.
    await t.runAsync(() => container.read(liveSessionProvider.notifier).end());
    await settle(t, frames: 3);
    await teardown(t, db);
  });

  testWidgets('onboarding: choosing Health Connect', (t) async {
    final db = (await t.runAsync(() async {
      final db = TempoDb(NativeDatabase.memory());
      return db;
    }))!;
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const OnboardingScreen()));
    await settle(t, frames: 5);
    await t.tap(find.text('Skip'));
    await settle(t, frames: 5);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Continue'));
      await settle(t, frames: 5);
    }
    expect(find.text('Where does your data come from?'), findsOneWidget);
    await t.tap(find.text('Health Connect'));
    await settle(t, frames: 5);
    await t.tap(find.text('Continue'));
    await settle(t, frames: 5);
    expect(find.text('Connect Health Connect'), findsWidgets);
    expect(find.text('Allow Bluetooth'), findsNothing);
    await t.tap(find.text('Not now — I’ll connect later'));
    await settle(t, frames: 10);
    expect(t.takeException(), isNull);
    expect(
      await t.runAsync(() => db.setting(Keys.dataSource)),
      'health_connect',
    );
    expect(await t.runAsync(() => db.setting(Keys.onboarded)), '1');
    await teardown(t, db);
  });
}
