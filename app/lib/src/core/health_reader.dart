import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_source/health_source.dart';

/// Outcome of asking for Health access.
enum HealthConnectResult {
  ok,

  /// The user said no (Health Connect tells us; Apple Health never does).
  denied,

  /// No Health Connect on this phone and none installable.
  unavailable,

  /// Health Connect needs installing or updating; the Play Store was opened.
  needsInstall,
}

/// Reads Apple Health or Health Connect. An interface so the sync can be
/// tested without the plugin.
abstract class HealthReader {
  /// The kinds this platform can give.
  Set<HealthKind> get kinds;

  /// Asks for read access to every kind, plus (Health Connect) history
  /// older than 30 days and background reads.
  Future<HealthConnectResult> connect();

  /// False when access is known to be missing. Apple Health hides read
  /// access, so it is only ever "not known missing" there.
  Future<bool> hasAccess();

  /// Whether a read may run with the app in the background. Apple Health
  /// can't be read while the phone is locked, which surfaces as a failed
  /// read instead.
  Future<bool> canReadInBackground();

  /// Records of [kind] starting in [from, to). Throws when the read fails.
  /// (Health Connect turns some failures into an empty list; the sync's
  /// reconcile step is built for that.)
  Future<List<HealthRecord>> read(HealthKind kind, DateTime from, DateTime to);
}

/// The `health` plugin behind [HealthReader]. Types per platform: Apple
/// Health has in-bed and SDNN HRV; Health Connect has sessions with
/// stages and RMSSD HRV.
class PluginHealthReader implements HealthReader {
  PluginHealthReader({Health? health, bool? ios})
    : _h = health ?? Health(),
      _ios = ios ?? Platform.isIOS;

  final Health _h;
  final bool _ios;
  bool _configured = false;

  Future<void> _ready() async {
    if (_configured) return;
    await _h.configure();
    _configured = true;
  }

  Map<HealthKind, List<HealthDataType>> get _types => _ios
      ? const {
          HealthKind.heartRate: [HealthDataType.HEART_RATE],
          HealthKind.steps: [HealthDataType.STEPS],
          HealthKind.sleepInBed: [HealthDataType.SLEEP_IN_BED],
          HealthKind.sleepAsleep: [HealthDataType.SLEEP_ASLEEP],
          HealthKind.sleepAwake: [HealthDataType.SLEEP_AWAKE],
          HealthKind.sleepLight: [HealthDataType.SLEEP_LIGHT],
          HealthKind.sleepDeep: [HealthDataType.SLEEP_DEEP],
          HealthKind.sleepRem: [HealthDataType.SLEEP_REM],
          HealthKind.hrvSdnn: [HealthDataType.HEART_RATE_VARIABILITY_SDNN],
          HealthKind.restingHr: [HealthDataType.RESTING_HEART_RATE],
          HealthKind.spo2: [HealthDataType.BLOOD_OXYGEN],
          HealthKind.workout: [HealthDataType.WORKOUT],
        }
      : const {
          HealthKind.heartRate: [HealthDataType.HEART_RATE],
          HealthKind.steps: [HealthDataType.STEPS],
          HealthKind.sleepSession: [HealthDataType.SLEEP_SESSION],
          HealthKind.sleepAsleep: [HealthDataType.SLEEP_ASLEEP],
          HealthKind.sleepAwake: [
            HealthDataType.SLEEP_AWAKE,
            HealthDataType.SLEEP_AWAKE_IN_BED,
            HealthDataType.SLEEP_OUT_OF_BED,
          ],
          HealthKind.sleepLight: [HealthDataType.SLEEP_LIGHT],
          HealthKind.sleepDeep: [HealthDataType.SLEEP_DEEP],
          HealthKind.sleepRem: [HealthDataType.SLEEP_REM],
          HealthKind.hrvRmssd: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
          HealthKind.restingHr: [HealthDataType.RESTING_HEART_RATE],
          HealthKind.spo2: [HealthDataType.BLOOD_OXYGEN],
          HealthKind.workout: [HealthDataType.WORKOUT],
        };

  @override
  Set<HealthKind> get kinds => _types.keys.toSet();

  /// Everything to ask read access for. On Health Connect the plugin reads
  /// distance, calories and steps inside every workout read, and without
  /// those permissions the whole workout read comes back empty.
  List<HealthDataType> get _permissionTypes => {
    for (final ts in _types.values) ...ts,
    if (!_ios) ...[
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.TOTAL_CALORIES_BURNED,
    ],
  }.toList();

  @override
  Future<HealthConnectResult> connect() async {
    await _ready();
    if (!_ios) {
      final status = await _h.getHealthConnectSdkStatus();
      if (status ==
          HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
        await _h.installHealthConnect();
        return HealthConnectResult.needsInstall;
      }
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        return HealthConnectResult.unavailable;
      }
    }
    final types = _permissionTypes;
    final ok = await _h.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.READ],
    );
    if (!ok) return HealthConnectResult.denied;
    if (!_ios) {
      // Both optional: without them Tempo sees 30 days back and reads only
      // while open.
      try {
        if (await _h.isHealthDataHistoryAvailable() &&
            !await _h.isHealthDataHistoryAuthorized()) {
          await _h.requestHealthDataHistoryAuthorization();
        }
      } catch (e) {
        debugPrint('health history permission: $e');
      }
      try {
        if (await _h.isHealthDataInBackgroundAvailable() &&
            !await _h.isHealthDataInBackgroundAuthorized()) {
          await _h.requestHealthDataInBackgroundAuthorization();
        }
      } catch (e) {
        debugPrint('health background permission: $e');
      }
    }
    return HealthConnectResult.ok;
  }

  @override
  Future<bool> hasAccess() async {
    await _ready();
    if (_ios) return true;
    if (!await _h.isHealthConnectAvailable()) return false;
    // Any of heart rate, sleep or steps is enough to be useful; a type
    // left off simply reads empty.
    for (final t in const [
      HealthDataType.HEART_RATE,
      HealthDataType.SLEEP_SESSION,
      HealthDataType.STEPS,
    ]) {
      final ok = await _h.hasPermissions(
        [t],
        permissions: const [HealthDataAccess.READ],
      );
      if (ok ?? true) return true;
    }
    return false;
  }

  @override
  Future<bool> canReadInBackground() async {
    if (_ios) return true;
    try {
      await _ready();
      if (!await _h.isHealthDataInBackgroundAvailable()) {
        // Older Health Connect: no separate permission to grant.
        return true;
      }
      return await _h.isHealthDataInBackgroundAuthorized();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<HealthRecord>> read(
    HealthKind kind,
    DateTime from,
    DateTime to,
  ) async {
    await _ready();
    final types = _types[kind];
    if (types == null) return const [];
    final out = <HealthRecord>[];
    for (final t in types) {
      final points = await _h.getHealthDataFromTypes(
        types: [t],
        startTime: from,
        endTime: to,
      );
      for (final p in points) {
        final r = recordOf(kind, p);
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  /// One plugin data point as a record; null when it has no usable value.
  @visibleForTesting
  static HealthRecord? recordOf(HealthKind kind, HealthDataPoint p) {
    double value;
    String? extra;
    final v = p.value;
    if (kind == HealthKind.workout) {
      if (v is! WorkoutHealthValue) return null;
      extra = v.workoutActivityType.name;
      value = 0;
    } else if (v is NumericHealthValue) {
      value = v.numericValue.toDouble();
    } else {
      return null;
    }
    return HealthRecord(
      uuid: p.uuid,
      kind: kind,
      start: p.dateFrom,
      end: p.dateTo,
      value: value,
      // iOS: bundle id; Health Connect: package name (its source_id is "").
      sourceApp: p.sourceId.isNotEmpty ? p.sourceId : p.sourceName,
      extra: extra,
    );
  }
}
