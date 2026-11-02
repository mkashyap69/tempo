import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android: a foreground service holds the process (and so the band
/// connection and GPS) while a live workout runs, so the screen can lock or
/// the user can switch apps without the session dying. Its notification is
/// the workout's ongoing notification (core/workout_presence.dart). No-op
/// elsewhere. The service runs no task of its own; the workout stays in the
/// app. No notification buttons: they need a second Flutter engine, and
/// attaching the BLE plugin to it risks dropping the band.
abstract final class BackgroundGuard {
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tempo_live',
        channelName: 'Live workout',
        channelDescription: 'Shown while a workout is recording.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        autoRunOnBoot: false,
        allowAutoRestart: false,
      ),
    );
    _ready = true;
  }

  /// Starts the service for a band session and/or phone GPS. Returns false
  /// when it can't run (not Android, nothing to hold, or refused); the
  /// caller then shows a plain ongoing notification instead.
  static Future<bool> start(
    String title, {
    String text = 'Recording',
    bool band = true,
    bool location = false,
  }) async {
    if (!Platform.isAndroid || !(band || location)) return false;
    try {
      _init();
      final r = await FlutterForegroundTask.startService(
        serviceId: 4101,
        serviceTypes: [
          if (band) ForegroundServiceTypes.connectedDevice,
          if (location) ForegroundServiceTypes.location,
        ],
        notificationTitle: title,
        notificationText: text,
        notificationIcon: const NotificationIcon(
          metaDataName: 'dev.tempo.tempo.NOTIFICATION_ICON',
        ),
      );
      return r is ServiceRequestSuccess;
    } catch (_) {
      // Without it the workout still records while Tempo is open.
      return false;
    }
  }

  static Future<void> update(String title, String text) async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  /// Android battery optimisation can stop background syncs. True when
  /// Tempo is exempt, or the platform has no such thing.
  static Future<bool> get batteryExempt async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  /// Shows the system "allow background activity" prompt.
  static Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }
}
