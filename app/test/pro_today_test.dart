import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/screens/picks.dart';
import 'package:tempo/src/screens/today.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// Today in a store build: the coach's session is Pro, the scores aren't.
void main() {
  setUpAll(loadFonts);
  for (final pro in [true, false]) {
    testWidgets('Today ${pro ? 'with' : 'without'} Pro', (t) async {
      final db = (await t.runAsync(() async {
        final d = await seededDb(days: 30);
        // A planned session today, whatever the seeded week holds.
        await CoachService(d).swapToday(sc.sessionTemplate('strength_full'), 'x');
        return d;
      }))!;
      t.view.physicalSize = const Size(390, 3600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, const TodayScreen(), pro: pro));
      await settle(t, frames: 60);
      expect(t.takeException(), isNull);
      expect(find.text('RECOVERY'), findsOneWidget);
      final coach =
          find.byType(WorkoutCard).evaluate().isNotEmpty ||
          find.byType(PicksEntry).evaluate().isNotEmpty;
      expect(coach, pro);
      expect(
        find.text('Your plan for today is ready'),
        pro ? findsNothing : findsOneWidget,
      );
      await teardown(t, db);
    });
  }
}
