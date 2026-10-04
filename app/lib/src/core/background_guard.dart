import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android: a foreground service holds the process (and so the band
/// connection) while a live workout runs, so the screen can lock or the
/// user can switch apps without the session dying. No-op elsewhere.
/// The service runs no task of its own; the workout stays in the app.
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

  static Future<void> start(String title) async {
    if (!Platform.isAndroid) return;
    try {
      _init();
      await FlutterForegroundTask.startService(
        serviceId: 4101,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
        notificationTitle: title,
        notificationText: 'Recording heart rate from your band',
        notificationIcon: const NotificationIcon(
          metaDataName: 'dev.tempo.tempo.NOTIFICATION_ICON',
        ),
      );
    } catch (_) {
      // Without it the workout still records while Tempo is open.
    }
  }

  static Future<void> update(String text) async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationText: text);
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
