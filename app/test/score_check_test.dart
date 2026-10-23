import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/score_check.dart';
import 'package:tempo/src/screens/score_check.dart';

import 'support/harness.dart';
import 'support/seed.dart';

void main() {
  setUpAll(loadFonts);

  test('the check reads 40 seeded days of the current algo', () async {
    final db = await seededDb();
    final r = await loadScoreCheck(db);
    expect(r.days, greaterThanOrEqualTo(39));
    expect(r.algoVersions.keys, [sc.algoVersion]);
    expect(r.spread['Sleep score'], isNotNull);
    expect(r.noise['Strain'], isNotNull);
    final shares = r.colours.values.fold<double>(0, (a, b) => a + b);
    expect(shares, anyOf(closeTo(1, 1e-9), 0));
    await db.close();
  });

  testWidgets('the screen shows spread, tracking and algo', (t) async {
    final db = (await t.runAsync(seededDb))!;
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const ScoreCheckScreen()));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('Sleep score'), findsOneWidget);
    expect(find.text('Against morning feel'), findsOneWidget);
    expect(find.text('Algo ${sc.algoVersion}'), findsOneWidget);
    await teardown(t, db);
  });
}
