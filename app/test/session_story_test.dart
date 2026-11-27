import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/session_story.dart';
import 'package:tempo/src/screens/live_workout.dart';
import 'package:tempo/src/screens/workout_detail.dart';
import 'package:tempo/src/state/live_session.dart';

import 'support/harness.dart';
import 'support/seed.dart';

class _Ended extends LiveSession {
  _Ended(this.s);
  final LiveState s;
  @override
  LiveState? build() => s;
}

/// Threshold intervals: five 3-minute Z4 blocks, 15 planned minutes.
LiveState threshold({required double z4Seconds}) {
  final plan = sc.sessionTemplate('threshold_run');
  return LiveState(
    phase: LivePhase.ended,
    sport: plan.sport,
    title: plan.title,
    plan: plan,
    elapsed: const Duration(minutes: 43),
    zoneSeconds: [600.0, 900.0, 300.0, z4Seconds, 0.0],
    target: const sc.StrainTarget(11, 14),
  );
}

void main() {
  setUpAll(loadFonts);
  const t = sc.StrainTarget(11, 14);

  group('sessionHeadline', () {
    test('landed blocks inside the range is Nailed it', () {
      expect(
        sessionHeadline(guided: true, landed: true, dayStrain: 12, target: t),
        'Nailed it.',
      );
    });

    test('blocks short of the plan say so', () {
      expect(
        sessionHeadline(guided: true, landed: false, dayStrain: 12, target: t),
        'Done, a little short of the plan.',
      );
    });

    test('open sessions are judged against the range', () {
      expect(
        sessionHeadline(guided: false, dayStrain: 12, target: t),
        'Done, right in today’s range.',
      );
      expect(
        sessionHeadline(guided: false, dayStrain: 8, target: t),
        'Done, with room left today.',
      );
      expect(
        sessionHeadline(guided: false, dayStrain: 16, target: t),
        'Done, and past today’s range.',
      );
    });

    test('a rest day over its cap is named', () {
      expect(
        sessionHeadline(
          guided: false,
          dayStrain: 10,
          target: const sc.StrainTarget(0, 8, cap: true),
        ),
        'Done. That took today past its cap.',
      );
    });

    test('next: done for the day, or room for a walk', () {
      expect(sessionNext(dayStrain: 12, target: t), contains('work done'));
      expect(sessionNext(dayStrain: 8, target: t), contains('walk'));
    });
  });

  test('blocks landed at 80 % of the planned work minutes', () {
    expect(blocksLanded(threshold(z4Seconds: 720)), isTrue);
    expect(blocksLanded(threshold(z4Seconds: 600)), isFalse);
  });

  testWidgets('the summary leads with how it went and what is next', (t) async {
    final db = TempoDb(NativeDatabase.memory());
    t.view.physicalSize = const Size(390, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      harness(
        db,
        ProviderScope(
          overrides: [
            liveSessionProvider.overrideWith(
              () => _Ended(threshold(z4Seconds: 900)),
            ),
          ],
          child: const LiveWorkoutScreen(),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    final head = find.byKey(const ValueKey('session-headline'));
    expect(head, findsOneWidget);
    expect((t.widget(head) as Text).data, 'Nailed it, with room left today.');
    expect(find.byKey(const ValueKey('session-next')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(db.close);
  });

  testWidgets('the session page says what to do if it feels wrong', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    t.view.physicalSize = const Size(390, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const WorkoutDetailScreen()));
    await t.pumpWidget(harness(db, const WorkoutDetailScreen()));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('IF IT FEELS WRONG'), findsOneWidget);
    expect(find.text('Sharp or growing pain'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('rating the effort gets an answer from the coach', (t) async {
    final db = TempoDb(NativeDatabase.memory());
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final plan = sc.sessionTemplate('easy_run');
    await t.pumpWidget(
      harness(
        db,
        ProviderScope(
          overrides: [
            liveSessionProvider.overrideWith(
              () => _Ended(
                LiveState(
                  phase: LivePhase.ended,
                  sport: plan.sport,
                  title: plan.title,
                  plan: plan,
                  elapsed: const Duration(minutes: 40),
                  zoneSeconds: const [600.0, 1800.0, 0.0, 0.0, 0.0],
                ),
              ),
            ),
          ],
          child: const LiveWorkoutScreen(),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('coach-reply')), findsNothing);
    await t.tap(find.text('9').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('coach-reply')), findsOneWidget);
    expect(find.text('Harder than planned.'), findsOneWidget);
    expect(find.textContaining('isn’t a pattern'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(db.close);
  });
}
