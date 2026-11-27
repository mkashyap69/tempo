import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/today_charts.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// P9: the three numbers stay in view once Today's rings scroll away.
void main() {
  setUpAll(loadFonts);
  testWidgets('mini rings show after the rings scroll away', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    // A short screen, so even a short Today (a rest day) scrolls the rings
    // out of view.
    t.view.physicalSize = const Size(390, 520);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const TodayScreen()));
    await settle(t, frames: 90);

    bool shown() => find.byType(MiniRingsBar).evaluate().isNotEmpty;
    expect(find.byType(TodayRings), findsOneWidget);
    expect(shown(), isFalse);

    await t.drag(find.byType(TodayRings), const Offset(0, -900));
    await settle(t, frames: 30);
    expect(shown(), isTrue);

    // Tapping it scrolls back up and the bar goes again.
    await t.tap(find.byType(MiniRingsBar));
    await settle(t, frames: 60);
    expect(shown(), isFalse);
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });
}
