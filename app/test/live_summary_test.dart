import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/screens/live_workout.dart';
import 'package:tempo/src/state/live_session.dart';

import 'support/harness.dart';

/// A session that has already ended, as the summary sees it.
class _Ended extends LiveSession {
  _Ended(this.s);
  final LiveState s;
  @override
  LiveState? build() => s;
}

LiveState ended(String template) {
  final plan = sc.sessionTemplate(template);
  return LiveState(
    phase: LivePhase.ended,
    sport: plan.sport,
    title: plan.title,
    plan: plan,
    elapsed: const Duration(minutes: 25),
    zoneSeconds: const [1500, 0, 0, 0, 0],
  );
}

void main() {
  test('a single-block guided session has no work blocks to judge', () {
    // Easy walk: one steady segment. take(length - 2) used to throw here.
    expect(sc.sessionTemplate('easy_walk').segments.length, lessThan(3));
    expect(landedLine(ended('easy_walk')), 'Session complete.');
  });

  testWidgets('ending a guided easy walk shows the summary, not an error', (
    t,
  ) async {
    final db = TempoDb(NativeDatabase.memory());
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      harness(
        db,
        ProviderScope(
          overrides: [
            liveSessionProvider.overrideWith(() => _Ended(ended('easy_walk'))),
          ],
          child: const LiveWorkoutScreen(),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.textContaining('WORKOUT SAVED'), findsOneWidget);
    expect(
      find.textContaining('Session complete.', findRichText: true),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    await t.runAsync(db.close);
  });
}
