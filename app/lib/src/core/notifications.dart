import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'coach_notifier.dart';
import 'db.dart';

/// Where coach notifications go. The app uses [TempoNotifications]; tests
/// swap in a fake so scheduling can be checked without a platform.
abstract class NotificationSink {
  Future<void> schedule(sc.NudgeSpec n, {bool precise = false});
  Future<void> cancel(int id);

  /// Removes the pre-Coach notifications (ids 1, 2, channel tempo_daily).
  Future<void> cancelLegacy();
}

/// The sink in use. Overridden in tests.
NotificationSink notificationSink = TempoNotifications.instance;

/// A notification tap that should open something: 'coach' or 'workouts'.
final notificationTaps = StreamController<String>.broadcast();

/// Payload carried by every coach notification.
String nudgePayload(sc.NudgeSpec n) => jsonEncode({
  'kind': n.kind.name,
  'id': n.id,
  'fireAt': n.fireAt.millisecondsSinceEpoch,
  ...n.payload,
});

/// Android channel per kind. Users own channels once created, so these
/// names are part of the UI.
({String id, String name, String desc, Importance imp}) channelFor(
  sc.NudgeKind k,
) => switch (k) {
  sc.NudgeKind.brief || sc.NudgeKind.weekly => (
    id: 'coach_brief',
    name: 'Morning brief & weekly',
    desc: 'Today’s plan when you wake, and the weekly look-back.',
    imp: Importance.low,
  ),
  sc.NudgeKind.session || sc.NudgeKind.missed || sc.NudgeKind.lever => (
    id: 'coach_nudge',
    name: 'Coach nudges',
    desc: 'Your session reminder, a missed-session check and daily actions.',
    imp: Importance.defaultImportance,
  ),
  sc.NudgeKind.winddown => (
    id: 'coach_bedtime',
    name: 'Bedtime',
    desc: 'A wind-down reminder before tonight’s bedtime.',
    imp: Importance.defaultImportance,
  ),
  sc.NudgeKind.rpe => (
    id: 'coach_checkin',
    name: 'Workout check-ins',
    desc: 'How hard a detected workout felt.',
    imp: Importance.defaultImportance,
  ),
  sc.NudgeKind.health => (
    id: 'coach_health',
    name: 'Health signals',
    desc: 'When your night heart rate runs well above usual.',
    imp: Importance.defaultImportance,
  ),
};

/// iOS categories: fixed buttons per kind (titles can't vary per alert).
List<DarwinNotificationCategory> _categories() {
  DarwinNotificationAction a(String id, String t, {bool fg = false}) =>
      DarwinNotificationAction.plain(
        id,
        t,
        options: fg
            ? {DarwinNotificationActionOption.foreground}
            : const <DarwinNotificationActionOption>{},
      );
  return [
    DarwinNotificationCategory(
      'coach_brief',
      actions: [
        a('open', 'Open', fg: true),
        a('easier', 'Easier'),
        a('rest', 'Rest today'),
      ],
    ),
    DarwinNotificationCategory(
      'coach_session',
      actions: [
        a('start', 'Start', fg: true),
        a('later', 'Later 1h'),
        a('skip', 'Skip'),
      ],
    ),
    DarwinNotificationCategory(
      'coach_missed',
      actions: [
        a('done', 'Done already'),
        a('plan_pm', 'Plan this evening'),
        a('skip', 'Skip'),
      ],
    ),
    DarwinNotificationCategory(
      'coach_lever',
      actions: [a('got_it', 'Got it'), a('not_today', 'Not today')],
    ),
    DarwinNotificationCategory(
      'coach_winddown',
      actions: [a('got_it', 'Got it'), a('not_today', 'Not tonight')],
    ),
    DarwinNotificationCategory(
      'coach_rpe',
      actions: [a('rpe_3', 'Easy'), a('rpe_5', 'Moderate'), a('rpe_8', 'Hard')],
    ),
    DarwinNotificationCategory(
      'coach_health',
      actions: [a('pause3', 'Pause 3 days'), a('fine', 'I’m fine')],
    ),
    DarwinNotificationCategory(
      'coach_weekly',
      actions: [a('open', 'Open', fg: true)],
    ),
  ];
}

/// Handles a button pressed while Tempo isn't running (Android: a fresh
/// engine; iOS: a background launch). Applies the answer, then replaces
/// the schedule so nothing stale is left pending.
@pragma('vm:entry-point')
void notificationActionBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final db = openDb();
  try {
    await TempoNotifications.instance.init();
    await handleNudgeResponse(db, r.payload, r.actionId);
  } catch (e) {
    debugPrint('notification action: $e');
  } finally {
    await db.close();
  }
}

/// Owns flutter_local_notifications. Everything is scheduled on the phone;
/// nothing leaves it.
class TempoNotifications implements NotificationSink {
  TempoNotifications._();
  static final instance = TempoNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Set by the app: applies a response while it's running.
  Future<void> Function(String? payload, String? actionId)? onResponse;

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
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_tempo'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: _categories(),
        ),
      ),
      onDidReceiveNotificationResponse: _foreground,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    final android = _android;
    if (android != null) {
      for (final k in sc.NudgeKind.values) {
        final ch = channelFor(k);
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            ch.id,
            ch.name,
            description: ch.desc,
            importance: ch.imp,
          ),
        );
      }
    }
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  void _foreground(NotificationResponse r) {
    final action = r.actionId;
    final payload = r.payload;
    String? kind;
    try {
      kind = (jsonDecode(payload ?? '{}') as Map)['kind'] as String?;
    } catch (_) {}
    if (action == null || action == 'open' || action == 'start') {
      notificationTaps.add(kind == 'rpe' ? 'workouts' : 'coach');
    }
    onResponse?.call(payload, action);
  }

  /// The notification that launched the app, if any.
  Future<String?> launchPayload() async {
    await init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d?.didNotificationLaunchApp == true
        ? d!.notificationResponse?.payload ?? ''
        : null;
  }

  /// Asks for permission (Android 13+, iOS). Returns whether granted.
  Future<bool> requestPermission() async {
    await init();
    final android = _android;
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

  /// Android: whether exact alarms are allowed (the user grants it in
  /// Settings). Always false elsewhere — iOS is exact already.
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  Future<void> requestExact() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> schedule(sc.NudgeSpec n, {bool precise = false}) async {
    await init();
    final ch = channelFor(n.kind);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        ch.id,
        ch.name,
        channelDescription: ch.desc,
        importance: ch.imp,
        priority: ch.imp == Importance.low
            ? Priority.low
            : Priority.defaultPriority,
        icon: 'ic_stat_tempo',
        visibility: NotificationVisibility.private,
        groupKey: 'tempo.coach',
        timeoutAfter: n.kind == sc.NudgeKind.rpe
            ? const Duration(hours: 6).inMilliseconds
            : null,
        actions: [
          for (final a in n.actions)
            AndroidNotificationAction(
              a.id,
              a.title,
              showsUserInterface: a.foreground,
              cancelNotification: true,
            ),
        ],
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: 'coach_${n.kind.name}',
        threadIdentifier: 'tempo.coach',
        interruptionLevel: n.level == sc.NudgeLevel.passive
            ? InterruptionLevel.passive
            : InterruptionLevel.active,
      ),
    );
    final when = tz.TZDateTime.from(n.fireAt, tz.local);
    final exact = precise && await canScheduleExact();
    await _plugin.zonedSchedule(
      id: n.id,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      title: n.title,
      body: n.body,
      payload: nudgePayload(n),
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelLegacy() async {
    await init();
    await _plugin.cancel(id: 1);
    await _plugin.cancel(id: 2);
    await _android?.deleteNotificationChannel(channelId: 'tempo_daily');
  }

  /// "Send a test notification" in Settings.
  Future<void> test() async {
    await init();
    await schedule(
      sc.NudgeSpec(
        kind: sc.NudgeKind.session,
        id: 99,
        fireAt: DateTime.now().add(const Duration(seconds: 5)),
        title: 'Tempo Coach test',
        body: 'Buttons work from here too',
        actions: const [
          sc.NudgeAction('got_it', 'Got it'),
          sc.NudgeAction('open', 'Open', foreground: true),
        ],
      ),
    );
  }
}
