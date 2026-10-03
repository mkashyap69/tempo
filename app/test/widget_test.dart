import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/ui/providers.dart';
import 'package:tempo/src/ui/today_screen.dart';

void main() {
  testWidgets('Today shows dials and the empty-state coaching', (t) async {
    final db = TempoDb(NativeDatabase.memory());
    await t.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Recovery'), findsOneWidget);
    expect(find.text('Strain'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('No data yet. Sync your band.'), findsOneWidget);
    await db.close();
    await t.pumpWidget(const SizedBox());
  });
}
