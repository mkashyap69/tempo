import 'package:drift/native.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_reader.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/profile.dart';

/// Health as a list of records. Reads return records starting in the
/// window, like HealthKit's strict-start query.
class FakeReader implements HealthReader {
  FakeReader(this.records);
  List<HealthRecord> records;
  Set<HealthKind> failing = {};
  Set<HealthKind> emptying = {};
  bool access = true, background = true;
  int reads = 0;

  @override
  Set<HealthKind> get kinds => {
    HealthKind.heartRate,
    HealthKind.steps,
    HealthKind.sleepSession,
    HealthKind.sleepAsleep,
    HealthKind.sleepAwake,
    HealthKind.sleepLight,
    HealthKind.sleepDeep,
    HealthKind.sleepRem,
    HealthKind.hrvRmssd,
    HealthKind.restingHr,
    HealthKind.spo2,
    HealthKind.workout,
  };

  @override
  Future<HealthConnectResult> connect() async => HealthConnectResult.ok;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> canReadInBackground() async => background;

  @override
  Future<List<HealthRecord>> read(
    HealthKind kind,
    DateTime from,
    DateTime to,
  ) async {
    reads++;
    if (failing.contains(kind)) throw Exception('locked');
    if (emptying.contains(kind)) return const [];
    return [
      for (final r in records)
        if (r.kind == kind && !r.start.isBefore(from) && r.start.isBefore(to))
          r,
    ];
  }
}

HealthRecord rec(
  HealthKind k,
  DateTime a,
  double v, {
  DateTime? b,
  String src = 'com.google.android.apps.fitness',
  String? uuid,
  String? extra,
}) => HealthRecord(
  uuid: uuid ?? '$src-${k.name}-${a.millisecondsSinceEpoch}',
  kind: k,
  start: a,
  end: b ?? a,
  value: v,
  sourceApp: src,
  extra: extra,
);

/// [nights] nights of a watch's data ending this morning: sleep sessions
/// with stages, HR every 5 min (every minute in an evening run), HRV,
/// steps from phone and watch, a run logged as a workout.
List<HealthRecord> watchData(int nights, {DateTime? now}) {
  final today = DateTime.now();
  final day0 = DateTime(today.year, today.month, today.day);
  final out = <HealthRecord>[];
  for (var i = nights; i >= 1; i--) {
    final morning = day0.subtract(Duration(days: i - 1));
    final bed = DateTime(morning.year, morning.month, morning.day - 1, 23);
    DateTime at(int min) => bed.add(Duration(minutes: min));
    final session = 'night-$i';
    out
      ..add(rec(HealthKind.sleepSession, at(0), 480, b: at(480), uuid: session))
      ..add(rec(HealthKind.sleepLight, at(0), 0, b: at(120), uuid: session))
      ..add(rec(HealthKind.sleepDeep, at(120), 0, b: at(210), uuid: session))
      ..add(rec(HealthKind.sleepRem, at(210), 0, b: at(270), uuid: session))
      ..add(rec(HealthKind.sleepLight, at(270), 0, b: at(480), uuid: session))
      ..add(rec(HealthKind.hrvRmssd, at(240), 40.0 + (i % 5) * 3));
    for (var m = 0; m < 480; m += 5) {
      out.add(rec(HealthKind.heartRate, at(m), 52.0 + (m ~/ 5) % 4));
    }
    // The day after waking (only days that have finished, plus today
    // until now).
    final wake = at(480);
    for (var m = 5; m < 16 * 60; m += 5) {
      final t = wake.add(Duration(minutes: m));
      if (t.isAfter(today)) break;
      if (t.hour == 18 && t.minute < 40) continue; // the run has its own
      out.add(rec(HealthKind.heartRate, t, 72.0 + (m ~/ 5) % 5));
    }
    for (var h = 1; h < 12; h++) {
      final a = wake.add(Duration(hours: h));
      if (a.isAfter(today)) break;
      final b = a.add(const Duration(minutes: 30));
      out
        ..add(rec(HealthKind.steps, a, 300, b: b, src: 'phone'))
        ..add(rec(HealthKind.steps, a, 330, b: b, src: 'watch'));
    }
    final run = DateTime(morning.year, morning.month, morning.day, 18);
    if (run.add(const Duration(minutes: 40)).isBefore(today)) {
      for (var m = 0; m < 40; m++) {
        out.add(rec(HealthKind.heartRate, run.add(Duration(minutes: m)), 150));
      }
      out.add(
        rec(
          HealthKind.workout,
          run,
          0,
          b: run.add(const Duration(minutes: 40)),
          extra: 'RUNNING',
          uuid: 'run-$i',
        ),
      );
    }
  }
  // Health can't hold the future.
  out.removeWhere((x) => x.start.isAfter(today));
  // Tempo's own export of a night: must never be read back.
  final last = DateTime(day0.year, day0.month, day0.day - 2, 23);
  out.add(
    rec(
      HealthKind.sleepSession,
      last,
      480,
      b: last.add(const Duration(hours: 8)),
      src: tempoAppId,
    ),
  );
  return out;
}

/// An in-memory DB whose source is Health Connect, filled by a real
/// [HealthSyncService] read of [nights] nights of [watchData].
Future<TempoDb> healthDb({int nights = 30}) async {
  final db = TempoDb(NativeDatabase.memory());
  await saveAppProfile(db, const Profile());
  await db.putSetting(Keys.onboarded, '1');
  await saveDataSource(db, DataSource.healthConnect);
  await HealthSyncService(
    db,
    reader: FakeReader(watchData(nights)),
    useLock: false,
  ).run();
  await CoachService(db).ensureWeek(DateTime.now());
  return db;
}
