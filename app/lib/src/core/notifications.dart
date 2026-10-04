import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Two notifications, nothing else: the morning call and a bedtime nudge.
/// Both are scheduled on the phone; nothing leaves it.
class TempoNotifications {
  TempoNotifications._();
  static final instance = TempoNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _morningId = 1, _bedtimeId = 2;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'tempo_daily',
      'Morning call & bedtime',
      channelDescription: 'Your call for the day and a bedtime nudge.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_stat_tempo',
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('timezone: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_tempo'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks for permission (Android 13+, iOS). Returns whether granted.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  tz.TZDateTime _next(int minuteOfDay) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Daily at [minuteOfDay]; null cancels.
  Future<void> scheduleMorningCall(int? minuteOfDay) async {
    await init();
    await _plugin.cancel(id: _morningId);
    if (minuteOfDay == null) return;
    await _plugin.zonedSchedule(
      id: _morningId,
      scheduledDate: _next(minuteOfDay),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Your call for today',
      body: 'Open Tempo near your band — it syncs last night and sets today’s plan.',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Tonight only, at [minuteOfDay]; rescheduled on every sync. null cancels.
  Future<void> scheduleBedtime(int? minuteOfDay, String bedtimeLabel) async {
    await init();
    await _plugin.cancel(id: _bedtimeId);
    if (minuteOfDay == null) return;
    await _plugin.zonedSchedule(
      id: _bedtimeId,
      scheduledDate: _next(minuteOfDay),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Bedtime in a little while',
      body: 'Aim to be in bed by $bedtimeLabel to cover tonight’s sleep need.',
    );
  }
}
