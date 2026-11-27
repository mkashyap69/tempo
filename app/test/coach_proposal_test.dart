import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_proposal.dart';
import 'package:tempo/src/core/coach_service.dart' show dayOf;
import 'package:tempo/src/core/plan_changes.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/screens/today.dart';

import 'support/harness.dart';
import 'support/seed.dart';

String session(String key) => jsonEncode(sc.sessionTemplate(key).toJson());

Future<void> plan(TempoDb db, DateTime d, String key) => db.putPlanDay(
  PlanDaysCompanion.insert(
    date: dateKey(d),
    session: session(key),
    general: false,
  ),
);

Proposal swap(DateTime a, DateTime b, {int deadline = 17 * 60}) => Proposal(
  day: dateKey(a),
  deadline: deadline,
  carried: '',
  changes: [
    ProposalChange(
      date: dateKey(a),
      from: session('threshold_run'),
      to: session('easy_run'),
      reason: '■ HRV under your normal two nights running.',
    ),
    ProposalChange(
      date: dateKey(b),
      from: session('easy_run'),
      to: session('threshold_run'),
      reason: '■ Moved from Tuesday.',
    ),
  ],
);

void main() {
  setUpAll(loadFonts);
  final tue = DateTime(2026, 11, 24), sat = DateTime(2026, 11, 28);

  group('deadline', () {
    test('half an hour before the session, 17:00 at the latest', () {
      expect(
        proposalDeadline(nowMinute: 7 * 60, plannedMinute: 12 * 60),
        11 * 60 + 30,
      );
      expect(
        proposalDeadline(nowMinute: 7 * 60, plannedMinute: 19 * 60),
        17 * 60,
      );
      expect(proposalDeadline(nowMinute: 7 * 60), 17 * 60);
    });

    test('never within the hour', () {
      expect(
        proposalDeadline(nowMinute: 7 * 60, plannedMinute: 7 * 60 + 40),
        8 * 60,
      );
    });
  });

  test('round-trips through its setting', () {
    final p = Proposal.parse(swap(tue, sat).toJson())!;
    expect(p.changes.length, 2);
    expect(p.why, 'HRV under your normal two nights running.');
    expect(p.changes.first.toTitle, sc.sessionTemplate('easy_run').title);
    expect(Proposal.parse('nope'), isNull);
  });

  test('accept writes both days with one stamp; Undo restores them', () async {
    final db = TempoDb(NativeDatabase.memory());
    addTearDown(db.close);
    await plan(db, tue, 'threshold_run');
    await plan(db, sat, 'easy_run');
    await db.putSetting(proposalKey, swap(tue, sat).toJson());
    final stamp = await acceptProposal(db, swap(tue, sat));
    expect(await db.setting(proposalKey), isNull);
    final rows = await db.planBetween(tue, sat);
    expect(rows.first.session, session('easy_run'));
    expect(rows.last.session, session('threshold_run'));
    expect(rows.every((r) => r.adaptedAt == stamp), isTrue);
    final changes = planChanges(rows, today: tue);
    expect(changes.first.together, isNotEmpty);
    await undoPlanChange(db, stamp);
    final back = await db.planBetween(tue, sat);
    expect(back.first.session, session('threshold_run'));
    expect(back.last.session, session('easy_run'));
  });

  test('keep my plan changes nothing and holds nothing back', () async {
    final db = TempoDb(NativeDatabase.memory());
    addTearDown(db.close);
    await plan(db, tue, 'threshold_run');
    await db.putSetting(Keys.carried, session('threshold_run'));
    await db.putSetting(proposalKey, swap(tue, sat).toJson());
    await declineProposal(db);
    expect(await db.setting(proposalKey), isNull);
    expect(await db.setting(Keys.carried), '');
    expect((await db.planDay(tue))!.session, session('threshold_run'));
  });

  test('an unanswered suggestion applies itself at its deadline', () async {
    final db = TempoDb(NativeDatabase.memory());
    addTearDown(db.close);
    await plan(db, tue, 'threshold_run');
    await plan(db, sat, 'easy_run');
    await db.putSetting(
      proposalKey,
      swap(tue, sat, deadline: 12 * 60).toJson(),
    );
    expect(await resolveProposal(db, DateTime(2026, 11, 24, 11)), isFalse);
    expect(await resolveProposal(db, DateTime(2026, 11, 24, 12)), isTrue);
    expect((await db.planDay(tue))!.session, session('easy_run'));
    expect((await db.planDay(tue))!.original, session('threshold_run'));
  });

  testWidgets('Today asks before the coach changes the week', (t) async {
    final db = (await t.runAsync(() async {
      final db = await seededDb(days: 30);
      final today = dayOf(DateTime.now());
      final later = today.add(const Duration(days: 2));
      await db.putPlanDay(
        PlanDaysCompanion.insert(
          date: dateKey(later),
          session: session('easy_run'),
          general: false,
          original: const Value(null),
        ),
      );
      await db.putSetting(proposalKey, swap(today, later).toJson());
      return db;
    }))!;
    t.view.physicalSize = const Size(390, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(harness(db, const TodayScreen()));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('coach-suggests')), findsOneWidget);
    expect(find.text('COACH SUGGESTS'), findsOneWidget);
    await t.tap(find.text('Keep my plan'));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(await t.runAsync(() => db.setting(proposalKey)), isNull);
    expect(find.byKey(const ValueKey('coach-suggests')), findsNothing);
    await t.pump(const Duration(seconds: 5));
    await teardown(t, db);
  });
}
