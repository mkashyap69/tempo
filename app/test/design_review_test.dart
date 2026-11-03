import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart' show mondayOf;
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/skip_reasons.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/screens/feedback.dart';
import 'package:tempo/src/screens/sleep.dart' show BreathingCard;
import 'package:tempo/src/screens/today.dart';
import 'package:tempo/src/screens/today_charts.dart' show NestedRings;
import 'package:tempo/src/screens/week_story.dart';

import 'support/harness.dart';
import 'support/seed.dart';

void main() {
  Future<void> render(
    WidgetTester t,
    TempoDb db,
    Widget w, {
    double h = 2600,
  }) async {
    t.view.physicalSize = Size(390, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, w));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  test('feedback text: category, words, details, never health values', () {
    final text = feedbackText(
      kind: FeedbackKind.score,
      words: '  Recovery said 20% but I felt great. ',
      details: {'App': 'Tempo 1.0', 'Reads from': 'Apple Health'},
    );
    expect(
      text,
      'Tempo feedback · A score looks off\n'
      '\n'
      'Recovery said 20% but I felt great.\n'
      '\n'
      '— App details —\n'
      'App: Tempo 1.0\n'
      'Reads from: Apple Health',
    );
    expect(
      feedbackText(kind: FeedbackKind.idea, words: ''),
      'Tempo feedback · An idea\n\n(no message)',
    );
  });

  test('skip reasons: each has a note and a skipped line', () {
    for (final r in SkipReason.values) {
      expect(skipReasonNote(r), isNotEmpty);
      expect(skippedLine(r), startsWith('Skipped'));
    }
    expect(skippedLine(null), 'Skipped. Nothing to make up.');
    expect(skippedLine(SkipReason.busy), 'Skipped · busy. Nothing to make up.');
  });

  testWidgets('skip reasons are stored per day and cleared', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 3)))!;
    final day = DateTime.now();
    await t.runAsync(() async {
      await saveSkipReason(db, day, SkipReason.sore);
      expect(await loadSkipReason(db, day), SkipReason.sore);
      await saveSkipReason(db, day, null);
      expect(await loadSkipReason(db, day), isNull);
    });
    await teardown(t, db);
  });

  testWidgets('Today: holding the rings explains them', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayScreen());
    expect(find.text('Today'), findsOneWidget);
    await t.longPress(find.byType(NestedRings));
    await settle(t);
    expect(find.text('Your three rings'), findsOneWidget);
    expect(find.text('Outer ring · Recovery'), findsOneWidget);
    await t.tap(find.text('Got it'));
    await settle(t);
    await teardown(t, db);
  });

  testWidgets('Today: the arrows step to earlier days and back', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(t, db, const TodayScreen());
    await t.tap(find.bySemanticsLabel('Earlier day').first);
    await settle(t);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('THE PLAN'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Earlier day').first);
    await settle(t);
    expect(find.text('Yesterday'), findsNothing);
    await t.ensureVisible(find.text('Back to today'));
    await t.tap(find.text('Back to today'));
    await settle(t);
    expect(find.text('Today'), findsOneWidget);
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });

  testWidgets('Week in review story: four pages, then done', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 30)))!;
    await render(
      t,
      db,
      WeekStoryScreen(monday: mondayOf(DateTime.now())),
      h: 900,
    );
    expect(find.textContaining('WEEK OF'), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('RECOVERY AND SLEEP'), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('EFFORT'), findsOneWidget);
    await t.tap(find.text('Back'));
    await settle(t);
    expect(find.text('RECOVERY AND SLEEP'), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle(t);
    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('WHAT’S NEXT'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(t.takeException(), isNull);
    await teardown(t, db);
  });

  testWidgets('Feedback: preview shows exactly what is sent', (t) async {
    final db = (await t.runAsync(() => seededDb(days: 3)))!;
    await render(t, db, const FeedbackScreen(), h: 1800);
    expect(find.textContaining('Tempo feedback · Something broke'), findsOne);
    await t.enterText(find.byType(TextField), 'The rings froze');
    await settle(t, frames: 3);
    expect(find.textContaining('The rings froze'), findsWidgets);
    expect(find.textContaining('— App details —'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Include app details').last);
    await settle(t, frames: 3);
    expect(find.textContaining('— App details —'), findsNothing);
    await teardown(t, db);
  });

  testWidgets('Sleep: a watch’s sparse SpO₂ still shows', (t) async {
    final at = DateTime(2026, 11, 3, 3);
    await t.pumpWidget(
      MaterialApp(
        theme: tempoTheme(Brightness.dark),
        home: Scaffold(
          body: Column(
            children: [
              BreathingCard(
                breathing: null,
                source: DataSource.appleHealth,
                spo2: [
                  Spo2Sample(ts: toTs(at), value: 96),
                  Spo2Sample(
                    ts: toTs(at.add(const Duration(hours: 1))),
                    value: 93,
                  ),
                ],
              ),
              const BreathingCard(
                breathing: null,
                source: DataSource.appleHealth,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Blood oxygen'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget); // 94.5 rounds up
    expect(find.text('93%'), findsOneWidget);
    expect(find.textContaining('Blood Oxygen measurements'), findsOneWidget);
    expect(find.textContaining('Mi Fitness'), findsNothing);
  });
}
