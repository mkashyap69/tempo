import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/screens/today.dart';

import 'support/harness.dart';
import 'support/seed.dart';

/// Today (design B) at small widths and large text: no overflow.
void main() {
  setUpAll(loadFonts);
  for (final (w, scale) in [(320.0, 1.0), (390.0, 1.35), (320.0, 1.35)]) {
    testWidgets('Today lays out at ${w.round()} px, text ×$scale', (t) async {
      final db = (await t.runAsync(() => seededDb(days: 30)))!;
      t.view.physicalSize = Size(w, 2200);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(w, 2200),
            textScaler: TextScaler.linear(scale),
          ),
          child: harness(db, const TodayScreen()),
        ),
      );
      await settle(t, frames: 90);
      expect(t.takeException(), isNull);
      await teardown(t, db);
    });
  }
}
