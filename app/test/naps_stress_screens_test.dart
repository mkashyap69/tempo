import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/screens/sleep.dart';
import 'package:tempo/src/screens/stress.dart';

import 'support/harness.dart';
import 'support/seed.dart';

Future<void> render(WidgetTester t, TempoDb db, Widget w) async {
  t.view.physicalSize = const Size(390, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(harness(db, w));
  await settle(t);
  expect(t.takeException(), isNull);
}

void main() {
  testWidgets('Naps card lists the nap with its times', (t) async {
    final morning = DateTime(2026, 10, 6);
    final db = (await t.runAsync(() async {
      final db = TempoDb(NativeDatabase.memory());
      final rows = <MinuteSamplesCompanion>[];
      void add(DateTime from, int n, int kind, {int steps = 0}) {
        for (var i = 0; i < n; i++) {
          rows.add(
            MinuteSamplesCompanion.insert(
              ts: Value(toTs(from.add(Duration(minutes: i)))),
              steps: steps,
              intensity: 5,
              kind: kind,
              hr: Value(kind == 0xf0 ? 52 + i % 5 : 70),
            ),
          );
        }
      }

      add(morning.add(const Duration(minutes: 7)), 491, 0xf0);
      add(
        morning.add(const Duration(hours: 8, minutes: 18)),
        442,
        0x50,
        steps: 20,
      );
      add(morning.add(const Duration(hours: 15, minutes: 40)), 46, 0xf0);
      add(
        morning.add(const Duration(hours: 16, minutes: 26)),
        60,
        0x50,
        steps: 20,
      );
      await db.appendMinutes(rows);
      return db;
    }))!;
    await render(t, db, Scaffold(body: NapsCard(morning: morning)));
    expect(find.text('Nap'), findsOneWidget);
    expect(find.text('3:40 pm – 4:26 pm'), findsOneWidget);
    expect(find.text('46m asleep'), findsOneWidget);
    await teardown(t, db);
  });

  testWidgets('Stress steps back a day and zooms', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 5)))!;
    await render(t, db, const StressScreen());
    expect(find.text('Today'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Previous day'));
    await settle(t);
    expect(find.text('Today'), findsNothing);
    await t.tap(find.text('6–12'));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('6:00 am'), findsWidgets);
    await teardown(t, db);
  });
}
