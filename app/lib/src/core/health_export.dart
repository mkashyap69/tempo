import 'dart:io';

import 'package:health/health.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';

import 'profile.dart' show Keys;
import 'stages.dart';

/// Writes finished workouts and nights to Apple Health / Health Connect.
/// Write-only: Tempo never reads Health data. Off unless the user turns it
/// on in Profile; everything stays on the phone either way.
class HealthExport {
  HealthExport(this.db);
  final TempoDb db;
  Health? _health;
  Health get _h => _health ??= Health();

  static List<HealthDataType> get types => [
    HealthDataType.WORKOUT,
    Platform.isAndroid
        ? HealthDataType.SLEEP_SESSION
        : HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
  ];

  Future<bool> get enabled async => await db.setting(Keys.healthExport) == '1';

  /// Asks for write access. On Android, offers to install Health Connect
  /// when it is missing. Returns false when the user said no.
  Future<bool> enable() async {
    await _h.configure();
    if (Platform.isAndroid && !await _h.isHealthConnectAvailable()) {
      await _h.installHealthConnect();
      return false;
    }
    final ok = await _h.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.WRITE],
    );
    if (!ok) return false;
    await db.putSetting(Keys.healthExport, '1');
    // Start from now, plus the last week, rather than all of history.
    await db.putSetting(
      Keys.healthExportedTo,
      DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
    );
    await exportNew();
    return true;
  }

  Future<void> disable() => db.putSetting(Keys.healthExport, '0');

  /// Writes workouts and nights that ended since the last export. Errors
  /// are swallowed: Health is a copy, never the source of truth.
  Future<int> exportNew() async {
    if (!await enabled) return 0;
    final since =
        DateTime.tryParse(await db.setting(Keys.healthExportedTo) ?? '') ??
        DateTime.now().subtract(const Duration(days: 7));
    final now = DateTime.now();
    var n = 0, until = since;
    try {
      await _h.configure();
      for (final w in await db.workoutsBetween(since, now)) {
        final end = fromTs(w.end);
        if (!end.isAfter(since)) continue;
        if (w.source == 'auto' && !w.confirmed) continue;
        if (await _h.writeWorkoutData(
          activityType: activityFor(w.sport),
          start: fromTs(w.start),
          end: end,
          title: w.title,
        )) {
          n++;
        }
        if (end.isAfter(until)) until = end;
      }
      final nights = await db.sleepSessionsBetween(since, now);
      for (final s in nights) {
        final start = fromTs(s.start), end = fromTs(s.end);
        if (!end.isAfter(since)) continue;
        await _write(types[1], start, end);
        final mins = await db.minutesBetween(start, end);
        // One record per run of the same stage.
        DateTime? runStart;
        sc.Stage? stage;
        Future<void> close(DateTime at) async {
          final t = _stageType(stage);
          if (runStart != null && t != null) await _write(t, runStart, at);
        }

        for (final m in mins) {
          final st = stageForKind(m.kind);
          final ts = fromTs(m.ts);
          if (st != stage) {
            await close(ts);
            runStart = ts;
            stage = st;
          }
        }
        await close(end);
        n++;
        if (end.isAfter(until)) until = end;
      }
    } catch (_) {
      // Permission revoked or Health unavailable; try again next sync.
    }
    await db.putSetting(Keys.healthExportedTo, until.toIso8601String());
    return n;
  }

  Future<void> _write(HealthDataType t, DateTime a, DateTime b) =>
      _h.writeHealthData(
        value: b.difference(a).inMinutes.toDouble(),
        type: t,
        startTime: a,
        endTime: b,
      );

  static HealthDataType? _stageType(sc.Stage? s) => switch (s) {
    sc.Stage.light => HealthDataType.SLEEP_LIGHT,
    sc.Stage.deep => HealthDataType.SLEEP_DEEP,
    sc.Stage.rem => HealthDataType.SLEEP_REM,
    sc.Stage.wake => HealthDataType.SLEEP_AWAKE,
    _ => null,
  };

  static HealthWorkoutActivityType activityFor(String? sport) => switch (sc
      .Sport
      .values
      .asNameMap()[sport]) {
    sc.Sport.running => HealthWorkoutActivityType.RUNNING,
    sc.Sport.cycling => HealthWorkoutActivityType.BIKING,
    sc.Sport.walking => HealthWorkoutActivityType.WALKING,
    sc.Sport.strength =>
      HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
    sc.Sport.hiit => HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING,
    sc.Sport.yoga => HealthWorkoutActivityType.YOGA,
    _ => HealthWorkoutActivityType.OTHER,
  };
}
