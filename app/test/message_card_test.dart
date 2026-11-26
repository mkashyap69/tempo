import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/design/components.dart';
import 'package:tempo/src/design/icons.dart';
import 'package:tempo/src/screens/message_card.dart';

import 'support/harness.dart';

void main() {
  testWidgets('an empty card leaves no gap: visible cards stay evenly spaced', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Material(
          child: ListView(
            children: const [
              GapBefore(gap: 0, child: SizedBox(key: Key('a'), height: 50)),
              GapBefore(gap: 20, child: SizedBox.shrink()),
              GapBefore(gap: 20, child: SizedBox.shrink()),
              GapBefore(gap: 20, child: SizedBox(key: Key('b'), height: 50)),
              GapBefore(gap: 20, child: SizedBox(key: Key('c'), height: 50)),
            ],
          ),
        ),
      ),
    );
    final a = t.getTopLeft(find.byKey(const Key('a'))).dy;
    final b = t.getTopLeft(find.byKey(const Key('b'))).dy;
    final c = t.getTopLeft(find.byKey(const Key('c'))).dy;
    expect(b - a, 70);
    expect(c - b, 70);
  });

  test('put away for today only', () async {
    final db = TempoDb(NativeDatabase.memory());
    final today = DateTime(2026, 11, 26, 9);
    await dismissToday(db, 'insight:load:detraining', now: today);
    expect(await loadDismissedToday(db, now: today), {
      'insight:load:detraining',
    });
    expect(
      await loadDismissedToday(db, now: today.add(const Duration(days: 1))),
      isEmpty,
    );
    await db.close();
  });

  testWidgets('✕ puts a message away', (t) async {
    final db = TempoDb(NativeDatabase.memory());
    await t.pumpWidget(
      harness(
        db,
        const Scaffold(
          body: MessageCard(
            id: 'insight:strength',
            icon: TempoIcons.strength,
            color: Colors.orange,
            overline: 'Today’s insight',
            title: '30 days since strength',
            body: 'Two strength days a week keep muscle and bone.',
            markers: [
              (glyph: '▲', text: '4 bpm resting HR', color: Colors.red),
            ],
          ),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    expect(find.text('30 days since strength'), findsOneWidget);
    expect(
      find.textContaining('4 bpm resting HR', findRichText: true),
      findsOneWidget,
    );
    await t.tap(find.byType(TempoIconButton));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('30 days since strength'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(db.close);
  });
}
