import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/core/sync_service.dart';
import 'package:tempo/src/screens/today.dart';

import 'support/harness.dart';
import 'support/seed.dart';

void main() {
  test('a gap after a recent cursor is another app, not a full memory', () {
    final now = DateTime(2026, 10, 21, 13, 17);
    expect(clearedNotFull(now.subtract(const Duration(hours: 3)), now), isTrue);
    expect(clearedNotFull(now.subtract(const Duration(days: 3)), now), isTrue);
    expect(
      clearedNotFull(now.subtract(const Duration(days: 13)), now),
      isFalse,
    );
    expect(
      SyncService.gapSummary(75, otherApp: true),
      'Another app cleared the band · 1h 15m not recovered',
    );
    expect(SyncService.gapSummary(75), contains('Band memory was full'));
  });

  group('Today', () {
    setUpAll(loadFonts);

    testWidgets('says another app is clearing the band', (t) async {
      final db = (await t.runAsync(() async {
        final db = await seededDb(days: 3);
        await db.putSetting(
          Keys.bandCleared,
          '${DateTime.now().toIso8601String()}|75',
        );
        return db;
      }))!;
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(db, const TodayScreen()));
      await settle(t);
      expect(find.text('Another app is clearing your band'), findsOneWidget);
      expect(find.textContaining('1 h 15 m'), findsOneWidget);
      await t.tap(find.text('Got it'));
      await settle(t);
      expect(find.text('Another app is clearing your band'), findsNothing);
      expect(t.takeException(), isNull);
      await teardown(t, db);
    });
  });
}
