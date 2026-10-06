import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/screens/activity_detail.dart';

import 'support/harness.dart';

void main() {
  testWidgets('Gait card shows steps, cadence, distance, pace, splits', (
    t,
  ) async {
    // 40 min at ~108 spm with the band's 0.766 m stride, like 6 Oct.
    final mins = [
      for (var i = 0; i < 40; i++)
        sc.Minute(
          DateTime(2026, 10, 6, 19, 1).add(Duration(minutes: i)),
          steps: i == 0 ? 68 : 108,
        ),
    ];
    final g = sc.gaitOf(mins, strideM: .766)!;
    final db = TempoDb(NativeDatabase.memory());
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      harness(
        db,
        Scaffold(
          body: SingleChildScrollView(
            child: GaitCard(gait: g, strideFromBand: true),
          ),
        ),
      ),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Pace & cadence'), findsOneWidget);
    expect(find.text('4,280'), findsOneWidget);
    expect(find.text('Km 3'), findsOneWidget);
    expect(find.textContaining("the band's own stride"), findsOneWidget);
    await teardown(t, db);
  });
}
