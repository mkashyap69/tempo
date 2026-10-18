import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/state/live_session.dart';

import 'support/seed.dart';

LiveState _live({int? bpm = 110, bool timerOnly = false}) => LiveState(
  phase: LivePhase.live,
  sport: sc.Sport.walking,
  title: 'Walking · open session',
  bpm: bpm,
  hrMax: 190,
  hrRest: 60,
  timerOnly: timerOnly,
);

void main() {
  group('LiveState.advance', () {
    test('sub-second ticks still count toward zone time', () {
      // Timer.periodic(1 s) drifts under a second about half the time; the
      // old whole-second sum dropped those ticks.
      var s = _live();
      for (var i = 0; i < 600; i++) {
        s = s.advance(
          Duration(milliseconds: i.isEven ? 999 : 1001),
          lost: false,
        );
      }
      final zoned = s.zoneSeconds.fold(0.0, (a, b) => a + b);
      expect(zoned, closeTo(s.elapsed.inMicroseconds / 1e6, 1e-6));
      expect(zoned, closeTo(600, .01));
    });

    test('zones plus no-signal time add up to elapsed', () {
      var s = _live();
      for (var i = 0; i < 120; i++) {
        s = s.advance(const Duration(milliseconds: 998), lost: i >= 90);
      }
      final zoned = s.zoneSeconds.fold(0.0, (a, b) => a + b);
      expect(s.noSignalSeconds, closeTo(30 * .998, 1e-6));
      expect(
        zoned + s.noSignalSeconds,
        closeTo(s.elapsed.inMicroseconds / 1e6, 1e-6),
      );
      expect(s.signalLost, isTrue);
      expect(s.bpm, isNull);
    });

    test('below Z1 counts as Z1', () {
      final s = _live(bpm: 80).advance(const Duration(seconds: 2), lost: false);
      expect(s.zoneSeconds.first, 2);
    });

    test('timer-only sessions log no gap', () {
      final s = _live(
        bpm: null,
        timerOnly: true,
      ).advance(const Duration(seconds: 5), lost: false);
      expect(s.noSignalSeconds, 0);
      expect(s.elapsed, const Duration(seconds: 5));
    });

    test('trace keeps only the last 15 minutes', () {
      var s = _live();
      for (var i = 0; i < LiveState.traceWindow + 120; i++) {
        s = s.advance(const Duration(seconds: 1), lost: false);
      }
      expect(s.trace.length, LiveState.traceWindow);
      expect(s.trace.last.$1, s.elapsed.inSeconds);
      expect(s.trace.first.$1, greaterThan(s.elapsed.inSeconds - 900));
    });
  });

  group('projection', () {
    LiveState run(int bpm, int minutes) {
      var s = _live(bpm: bpm);
      for (var i = 0; i < minutes * 60; i++) {
        s = s.advance(const Duration(seconds: 1), lost: false);
      }
      return s;
    }

    test('needs a minute of readings', () {
      expect(run(140, 0).minutesTo(10), isNull);
      expect(run(140, 0).strainRate, isNull);
    });

    test('minutes to a goal match the strain curve', () {
      final s = run(150, 10);
      final goal = s.dayStrain + 2;
      final m = s.minutesTo(goal)!;
      final per = sc.minuteTrimp(150, hrRest: 60, hrMax: 190);
      expect(sc.strainFromTrimp(s.trimp + per * m), greaterThanOrEqualTo(goal));
      expect(sc.strainFromTrimp(s.trimp + per * (m - 1)), lessThan(goal));
    });

    test('null when already there or out of reach', () {
      final s = run(150, 10);
      expect(s.minutesTo(s.dayStrain - .1), isNull);
      expect(run(70, 5).minutesTo(15), isNull);
    });
  });

  test('repairLiveZones rebuilds zones from the recorded heart rate', () async {
    final db = await seededDb(days: 3);
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final a = st.toTs(start), b = a + 56 * 60;
    // A 56-minute walk saved with the old bug: 31 of 56 minutes in zones.
    final id = await db.addWorkout(
      st.WorkoutsCompanion.insert(
        start: a,
        end: b,
        sport: const Value('walking'),
        title: 'Walking',
        source: 'live',
        confirmed: const Value(true),
        strain: 3.4,
        trimp: 9,
        zones: jsonEncode([28, 3, 0, 0, 0]),
      ),
    );
    for (var t = a; t < b; t++) {
      await db.appendHrLive(t, t - a < 50 * 60 ? 105 : 140);
    }
    await repairLiveZones(db);
    final w = (await db.workout(id))!;
    final z = (jsonDecode(w.zones) as List).cast<int>();
    expect(z.reduce((x, y) => x + y), 56);
    expect(z[0], greaterThanOrEqualTo(49));
    expect(w.strain, 3.4);
    expect(await db.setting(Keys.liveZonesV2), '1');

    // Runs once: a later edit is left alone.
    await db.updateWorkout(
      id,
      st.WorkoutsCompanion(zones: Value(jsonEncode([1, 0, 0, 0, 0]))),
    );
    await repairLiveZones(db);
    expect((await db.workout(id))!.zones, jsonEncode([1, 0, 0, 0, 0]));
    await db.close();
  });
}
