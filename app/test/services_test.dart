import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/battery.dart';
import 'package:tempo/src/core/coach_notifier.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/notifications.dart';
import 'package:tempo/src/core/export.dart';
import 'package:tempo/src/core/home_widgets.dart';
import 'package:tempo/src/core/longevity_service.dart';
import 'package:tempo/src/core/pause.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/core/score_service.dart';
import 'package:tempo/src/core/sync_service.dart';
import 'package:tempo/src/core/today.dart';

import 'support/fake_sink.dart';
import 'support/seed.dart';

void main() {
  late TempoDb db;
  setUp(() => db = TempoDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  final t0 = DateTime(2026, 10, 1, 8);
  BatteryPoint at(double days, int pct) =>
      (t0.add(Duration(minutes: (days * 1440).round())), pct);

  group('battery days left', () {
    test('needs a day of readings', () {
      expect(batteryDaysLeft([at(0, 90), at(0.5, 88)]), isNull);
    });
    test('slope over the current discharge run', () {
      // 5% a day, 70% left → 14 days.
      final log = [for (var d = 0; d <= 4; d++) at(d.toDouble(), 90 - 5 * d)];
      expect(batteryDaysLeft(log), closeTo(14, 1e-6));
    });
    test('a charge starts a new run', () {
      final log = [
        at(0, 40),
        at(1, 20),
        at(1.1, 100), // charged
        at(2.1, 90),
        at(3.1, 80),
      ];
      expect(batteryDaysLeft(log), closeTo(8, 1e-6));
    });
    test('flat drain says nothing', () {
      expect(batteryDaysLeft([at(0, 80), at(2, 80)]), isNull);
    });
    test('log keeps one reading an hour', () async {
      await recordBattery(db, 90, at: t0);
      await recordBattery(db, 89, at: t0.add(const Duration(minutes: 20)));
      await recordBattery(db, 88, at: t0.add(const Duration(hours: 2)));
      final log = await batteryLog(db);
      expect(log.map((p) => p.$2), [89, 88]);
      expect(await db.setting(Keys.battery), '88');
    });
    test('labels', () {
      expect(batteryLeftLabel(null), 'learning drain rate');
      expect(batteryLeftLabel(9.4), '~9 days left');
      expect(batteryLeftLabel(0.5), 'under a day left');
    });
  });

  group('pause', () {
    test('start, cover, end', () async {
      final mon = DateTime(2026, 10, 5);
      await startPause(db, PauseReason.ill, on: mon);
      var ps = await loadPauses(db);
      expect(activePause(ps)?.reason, PauseReason.ill);
      expect(isPaused(ps, mon.add(const Duration(days: 3))), isTrue);
      expect(isPaused(ps, mon.subtract(const Duration(days: 1))), isFalse);
      await endPause(db, on: mon.add(const Duration(days: 3)));
      ps = await loadPauses(db);
      expect(activePause(ps), isNull);
      expect(isPaused(ps, mon.add(const Duration(days: 2))), isTrue);
      expect(isPaused(ps, mon.add(const Duration(days: 3))), isFalse);
    });
    test('ending on the start day removes it', () async {
      final d = DateTime(2026, 10, 5);
      await startPause(db, PauseReason.travel, on: d);
      await endPause(db, on: d);
      expect(await loadPauses(db), isEmpty);
    });
    test('paused days are left out of the scoring history', () async {
      final today = dayOf(DateTime.now());
      for (var i = 1; i <= 3; i++) {
        await db.upsertScore(
          DailyScoresCompanion.insert(
            date: dateKey(today.subtract(Duration(days: i))),
            strain: 0,
            trimp: 0,
            hrMax: 190,
            sleptHours: const Value(7),
            needHours: const Value(7.5),
            calibrating: true,
            algoVersion: sc.algoVersion,
          ),
        );
      }
      await startPause(
        db,
        PauseReason.ill,
        on: today.subtract(const Duration(days: 2)),
      );
      // Nap-free day with no data: only history counts toward calibration.
      await ScoreService(db).recomputeFrom(today);
      final t = await loadToday(db);
      expect(t.pause, isNotNull);
    });
  });

  group('coach', () {
    Future<void> rated(int daysAgo, int rpe, double strain) => db.addWorkout(
      WorkoutsCompanion.insert(
        start: toTs(
          dayOf(DateTime.now()).subtract(Duration(days: daysAgo, hours: -9)),
        ),
        end: toTs(
          dayOf(DateTime.now()).subtract(Duration(days: daysAgo, hours: -10)),
        ),
        sport: const Value('running'),
        title: 'Run',
        source: 'live',
        strain: strain,
        trimp: 20,
        zones: '[0,0,0,0,0]',
        rpe: Value(rpe),
      ),
    );
    test('effort reads RPE against the strain each session implied', () async {
      final today = dayOf(DateTime.now());
      expect(await CoachService(db).effort(today), sc.Effort.unknown);
      await rated(1, 8, 5); // easy by strain, felt hard
      await rated(2, 7, 6);
      expect(await CoachService(db).effort(today), sc.Effort.heavy);
    });
    test('no adaptation while paused', () async {
      final today = dayOf(DateTime.now());
      await startPause(db, PauseReason.travel, on: today);
      expect(await CoachService(db).adaptToday(), isEmpty);
    });
  });

  test('strength RPE adds load and rescoring picks it up', () async {
    final today = dayOf(DateTime.now());
    await ScoreService(db).recomputeFrom(today);
    final before = (await db.scoreFor(today))!.trimp;
    final id = await db.addWorkout(
      WorkoutsCompanion.insert(
        start: toTs(today.add(const Duration(hours: 7))),
        end: toTs(today.add(const Duration(hours: 8))),
        sport: Value(sc.Sport.strength.name),
        title: 'Strength',
        source: 'live',
        strain: 2,
        trimp: 5,
        zones: '[0,0,0,0,0]',
      ),
    );
    await saveRpe(db, id, 7);
    final after = (await db.scoreFor(today))!.trimp;
    expect(after - before, closeTo(sc.trimpFromRpe(7, 60) - 5, 1e-6));
  });

  test('restore round-trips an export and rejects other JSON', () async {
    await db.appendMinutes([
      MinuteSamplesCompanion.insert(
        ts: const Value(600),
        steps: 1,
        intensity: 0,
        kind: 1,
        hr: const Value(60),
      ),
    ]);
    final rows = await db.customSelect('SELECT * FROM minute_samples').get();
    final json = jsonEncode({
      'exported_at': '2026-10-04T08:00:00',
      'minute_samples': [
        for (final r in rows) r.data,
        {'ts': 660, 'steps': 2, 'intensity': 0, 'kind': 1, 'hr': 61},
      ],
    });
    final n = await restoreJson(db, json);
    expect(n['minute_samples'], 1);
    expect(
      () => restoreJson(db, '{"hello": 1}'),
      throwsA(isA<FormatException>()),
    );
    expect(() => restoreJson(db, 'nope'), throwsA(isA<FormatException>()));
  });

  test('sync gap: minutes the band no longer had', () {
    final c = DateTime(2026, 10, 4, 6);
    expect(activityGapMinutes(null, c), 0);
    expect(activityGapMinutes(c, c.add(const Duration(minutes: 1))), 0);
    expect(activityGapMinutes(c, c.add(const Duration(hours: 3))), 180);
    expect(SyncService.gapSummary(200), contains('3h 20m'));
  });

  test('widget links name a detail screen', () {
    expect(widgetTarget(Uri.parse('tempo://recovery')), 'recovery');
    expect(widgetTarget(Uri.parse('tempo://sleep')), 'sleep');
    expect(widgetTarget(Uri.parse('tempo://today')), 'today');
    expect(widgetTarget(Uri.parse('https://x.y/recovery')), isNull);
    expect(widgetTarget(Uri.parse('tempo://nope')), isNull);
    expect(widgetTarget(null), isNull);
  });

  test('band workouts become confirmed workouts; a delete sticks', () async {
    final today = dayOf(DateTime.now());
    final a = today.add(const Duration(hours: 7));
    await db.appendMinutes([
      for (var m = 0; m < 30; m++)
        MinuteSamplesCompanion.insert(
          ts: Value(toTs(a.add(Duration(minutes: m)))),
          steps: 160,
          intensity: 90,
          kind: 1,
          hr: const Value(150),
        ),
    ]);
    await db.appendBandWorkouts([
      BandWorkoutsCompanion.insert(
        start: Value(toTs(a)),
        end: toTs(a.add(const Duration(minutes: 30))),
        kind: 0x01,
        raw: '',
        fetchedAt: toTs(a),
      ),
    ]);
    await ScoreService(db).recomputeFrom(today);
    var ws = await db.workoutsBetween(
      today,
      today.add(const Duration(days: 1)),
    );
    final band = ws.where((w) => w.source == 'band').single;
    expect(band.title, 'Outdoor run');
    expect(band.sport, 'running');
    expect(band.confirmed, isTrue);
    expect(band.avgHr, 150);
    expect(band.strain, greaterThan(0));
    // Auto detection doesn't double it.
    expect(ws.where((w) => w.source == 'auto'), isEmpty);

    await db.deleteWorkout(band.id);
    await dismissBandWorkout(db, band.start);
    await ScoreService(db).recomputeFrom(today);
    ws = await db.workoutsBetween(today, today.add(const Duration(days: 1)));
    expect(ws.where((w) => w.source == 'band'), isEmpty);
  });

  group('longevity', () {
    test('inputs come from the last 30 days of band data', () async {
      final d = await seededDb(days: 30);
      final i = await longevityInputs(d);
      expect(i.daysOfData, greaterThanOrEqualTo(25));
      expect(i.restingHr, isNotNull);
      expect(i.vo2max, isNotNull);
      expect(i.steps, isNotNull);
      expect(i.sleepHours, isNotNull);
      expect(i.smoking, isNull);
      await d.close();
    });

    test('manual details round-trip and reach the inputs', () async {
      await saveManualHealth(
        db,
        const ManualHealth(
          smoking: sc.Smoking.former,
          alcohol: 10,
          systolic: 128,
          waist: 90,
        ),
      );
      final i = await longevityInputs(db);
      expect(i.smoking, sc.Smoking.former);
      expect(i.alcoholUnits, 10);
      expect(i.systolic, 128);
      expect(i.waistCm, 90);
      expect(i.daysOfData, 0);
    });

    test('a snapshot is saved with its algo version', () async {
      final d = await seededDb(days: 30);
      final t = await updateLongevity(d);
      final rows = await d.longevitySince(DateTime(2000));
      expect(rows.last.tempoAge, closeTo(t.age, 1e-9));
      expect(rows.last.algoVersion, longevityAlgo);
      expect(decodeContributors(rows.last.contributors), isNotEmpty);
      await d.close();
    });

    test('pace adds calendar time back to the delta', () {
      LongevitySnapshot row(DateTime d, double delta) => LongevitySnapshot(
        date: dateKey(d),
        tempoAge: 31 + delta,
        realAge: 31,
        calibrating: false,
        contributors: '[]',
        algoVersion: longevityAlgo,
      );
      // Delta steady: ageing at the calendar's pace.
      final flat = [
        for (var m = 0; m < 6; m++) row(DateTime(2026, 1 + m, 1), -2),
      ];
      expect(paceFrom(flat), closeTo(1, .01));
      // Delta falls a year over five months: slower than the calendar.
      final better = [
        for (var m = 0; m < 6; m++) row(DateTime(2026, 1 + m, 1), -m / 5),
      ];
      expect(paceFrom(better)!, lessThan(1));
    });

    test('a focus lever reshapes this week’s plan', () async {
      await saveAppProfile(db, const Profile());
      final coach = CoachService(db);
      await setFocus(db, sc.Lever.strength);
      final f = await loadFocus(db);
      expect(f!.lever, sc.Lever.strength);
      expect(f.weeks, 8);
      final week = await coach.ensureWeek(DateTime.now());
      final strength = week
          .where((p) => (jsonDecode(p.session) as Map)['sport'] == 'strength')
          .length;
      expect(strength, greaterThanOrEqualTo(2));
      await setFocus(db, null);
      expect(await loadFocus(db), isNull);
    });
  });

  group('tempo coach', () {
    late FakeNotificationSink sink;
    setUp(() {
      sink = FakeNotificationSink();
      notificationSink = sink;
    });
    final today = dayOf(DateTime.now());
    DateTime at(int h, [int m = 0]) =>
        DateTime(today.year, today.month, today.day, h, m);
    Future<void> planToday(String key) async {
      await saveAppProfile(db, const Profile());
      await CoachService(db).swapToday(sc.sessionTemplate(key), 'test');
    }

    Future<void> runAt(int h, {int minutes = 35, String sport = 'running'}) =>
        db.addWorkout(
          WorkoutsCompanion.insert(
            start: toTs(at(h)),
            end: toTs(at(h).add(Duration(minutes: minutes))),
            sport: Value(sport),
            title: 'Run',
            source: 'auto',
            strain: 6,
            trimp: 30,
            zones: '[5,$minutes,0,0,0]',
          ),
        );

    test('morning slot passed: missed, with an evening rescue', () async {
      await planToday('easy_run');
      await db.putSetting(Keys.coachSlot, 'am');
      final t = await loadToday(db, at: at(11));
      expect(t.plannedMinute, 7 * 60);
      expect(t.status, sc.DayStatus.missedSlot);
      expect(t.rescue.offered, isTrue);
      expect(t.rescue.start, 18 * 60);
    });

    test('a matching workout marks it done, even auto-detected', () async {
      await planToday('easy_run');
      await db.putSetting(Keys.coachSlot, 'am');
      await runAt(7);
      final t = await loadToday(db, at: at(11));
      expect(t.status, sc.DayStatus.done);
      expect(t.rescue.offered, isFalse);
    });

    test('intent: skip, move, done and undo', () async {
      await planToday('easy_run');
      final coach = CoachService(db);
      await coach.setIntent(today, sc.Intent.skipped);
      expect((await loadToday(db, at: at(11))).status, sc.DayStatus.skipped);
      await coach.setIntent(today, sc.Intent.moved, minute: 18 * 60);
      var t = await loadToday(db, at: at(11));
      expect(t.status, sc.DayStatus.moved);
      expect(t.plannedMinute, 18 * 60);
      await coach.setIntent(today, sc.Intent.done);
      expect((await loadToday(db, at: at(11))).status, sc.DayStatus.done);
      await coach.setIntent(today, sc.Intent.planned);
      t = await loadToday(db, at: at(11));
      expect(t.intent, sc.Intent.planned);
    });

    test(
      'a missed key session yesterday is carried; an easy one drops',
      () async {
        await saveAppProfile(db, const Profile());
        final coach = CoachService(db);
        final y = today.subtract(const Duration(days: 1));
        await coach.ensureWeek(y);
        await db.putPlanDay(
          PlanDaysCompanion.insert(
            date: dateKey(y),
            session: jsonEncode(sc.sessionTemplate('threshold_run').toJson()),
            general: false,
          ),
        );
        expect((await coach.missedKeyYesterday(today))?.key, 'threshold_run');
        await db.putPlanDay(
          PlanDaysCompanion.insert(
            date: dateKey(y),
            session: jsonEncode(sc.sessionTemplate('easy_run').toJson()),
            general: false,
          ),
        );
        expect(await coach.missedKeyYesterday(today), isNull);
      },
    );

    test('refresh replaces the pending set and logs changes once', () async {
      await planToday('easy_run');
      final n = CoachNotifier(db, sink: sink);
      final now = at(5);
      final a = await n.refresh(now: now);
      expect(a, isNotEmpty);
      expect(sink.legacyCancelled, 1);
      expect(sink.pending.keys.toSet(), a.map((x) => x.id).toSet());
      final logged = (await db.nudgesSince(DateTime(2000))).length;
      final b = await n.refresh(now: now);
      expect(b.map((x) => x.id), a.map((x) => x.id));
      expect((await db.nudgesSince(DateTime(2000))).length, logged);
      expect(sink.legacyCancelled, 1);
    });

    test('kinds switched off are not scheduled', () async {
      await planToday('easy_run');
      for (final k in sc.NudgeKind.values) {
        await CoachNotifier.setKind(db, k, false);
      }
      expect(await CoachNotifier(db, sink: sink).refresh(now: at(5)), isEmpty);
    });

    test('buttons: Plan 18:00 moves the session, Skip skips it', () async {
      await planToday('easy_run');
      await handleNudgeResponse(
        db,
        jsonEncode({'kind': 'missed', 'id': 120, 'start': 18 * 60}),
        'plan_pm',
        sink: sink,
      );
      var row = (await db.planDay(today))!;
      expect(row.status, 'moved');
      expect(row.plannedMinute, 18 * 60);
      expect(row.statusSource, 'notification');
      await handleNudgeResponse(
        db,
        jsonEncode({'kind': 'session', 'id': 110}),
        'skip',
        sink: sink,
      );
      row = (await db.planDay(today))!;
      expect(row.status, 'skipped');
      final log = await db.nudgesSince(DateTime(2000));
      expect(log.where((r) => r.event == 'action').map((r) => r.action), [
        'plan_pm',
        'skip',
      ]);
    });

    test('rating button saves RPE on the detected workout', () async {
      await saveAppProfile(db, const Profile());
      await runAt(7);
      final w = (await db.workoutsBetween(today, at(23))).single;
      await handleNudgeResponse(
        db,
        jsonEncode({'kind': 'rpe', 'id': 150, 'workout': w.start}),
        'rpe_5',
        sink: sink,
      );
      final after = (await db.workoutsBetween(today, at(23))).single;
      expect(after.rpe, 5);
      expect(after.confirmed, isTrue);
    });

    test('ignore streaks come from posted rows without a response', () {
      NudgeLogData r(int id, String event, int ts, {String kind = 'lever'}) =>
          NudgeLogData(
            id: id,
            ts: ts,
            day: '2026-10-05',
            kind: kind,
            notifId: 130,
            fireAt: ts,
            event: event,
            payload: '{}',
            algoVersion: 'nudge-1',
          );
      final s = ignoreStreaksFrom([
        r(1, 'posted', 1000),
        r(2, 'action', 1100),
        r(3, 'posted', 90000),
        r(4, 'posted', 180000),
      ]);
      expect(s[sc.NudgeKind.lever], 2);
    });
  });
}
