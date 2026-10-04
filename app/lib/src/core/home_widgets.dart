import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:store/store.dart' as st;

import 'notifications.dart';
import 'profile.dart';
import 'today.dart';
import 'coach_service.dart';
import 'format.dart';
import 'health_export.dart';

/// iOS app group shared with the WidgetKit extension.
const widgetAppGroup = 'group.dev.tempo.tempo';
const _android = ['TempoSmallWidget', 'TempoMediumWidget'];
const _ios = 'TempoWidget';

/// Fills are percentages; each widget lights that share of its ticks.
/// Pushes today's numbers to the home-screen widgets (WidgetKit / Android
/// AppWidget). Widgets show their own timestamp and dim when stale.
Future<void> updateHomeWidgets(TodayData t) async {
  try {
    await HomeWidget.setAppGroupId(widgetAppGroup);
    final rec = t.recovery;
    final data = <String, Object?>{
      'rec_value': t.calibrating
          ? '${t.nights}'
          : (rec == null ? '—' : '${rec.round()}'),
      'rec_unit': t.calibrating ? '/14' : (rec == null ? '' : '%'),
      'rec_state': t.calibrating
          ? 'Calibrating'
          : rec == null
          ? 'Wear tonight'
          : '${recoveryGlyph(rec)} ${recoveryWord(rec)}${t.restDay ? ' · rest' : ''}',
      'rec_level': t.calibrating || rec == null
          ? 'none'
          : (rec >= 67
                ? 'high'
                : rec >= 34
                ? 'mid'
                : 'low'),
      'rec_fill': t.calibrating
          ? (t.nights * 100 / 14).round()
          : (rec ?? 0).round(),
      'strain_value': t.strain.toStringAsFixed(1),
      'strain_state': t.target.cap
          ? 'Cap ${t.target.hi.round()}'
          : 'Target ${t.target.lo.round()}–${t.target.hi.round()}',
      'strain_fill': (t.strain / 21 * 100).round(),
      'sleep_value': t.sleepPerf == null ? '—' : '${t.sleepPerf!.round()}',
      'sleep_state': t.slept == null ? 'No data' : hmShort(t.slept!),
      'sleep_fill': (t.sleepPerf ?? 0).round(),
      'updated_at': '${(t.lastSync ?? DateTime.now()).millisecondsSinceEpoch}',
    };
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData(e.key, e.value);
    }
    for (final a in _android) {
      await HomeWidget.updateWidget(androidName: a);
    }
    await HomeWidget.updateWidget(iOSName: _ios);
  } catch (e) {
    debugPrint('home widgets: $e');
  }
}

/// Runs after every successful sync (foreground or background): adapts the
/// plan, refreshes widgets and reschedules tonight's bedtime nudge.
Future<void> afterSync(st.TempoDb db) async {
  try {
    await CoachService(db).adaptToday();
  } catch (e) {
    debugPrint('coach adapt: $e');
  }
  final t = await loadToday(db);
  await updateHomeWidgets(t);
  await rescheduleNotifications(db, t);
  try {
    await HealthExport(db).exportNew();
  } catch (e) {
    debugPrint('health export: $e');
  }
}

Future<void> rescheduleNotifications(st.TempoDb db, TodayData t) async {
  try {
    final n = TempoNotifications.instance;
    final morning = await db.setting(Keys.morningCall) ?? '07:00';
    await n.scheduleMorningCall(parseHm(morning));
    final nudge = await db.setting(Keys.bedtimeNudge) ?? '30';
    final before = int.tryParse(nudge);
    await n.scheduleBedtime(
      before == null ? null : (t.bedtimeMinute - before) % 1440,
      clock12(t.bedtimeMinute),
    );
  } catch (e) {
    debugPrint('notifications: $e');
  }
}

/// Which detail screen a widget tap asks for: recovery, strain, sleep or
/// today (the tab itself). null for anything else.
String? widgetTarget(Uri? uri) {
  if (uri == null || uri.scheme != 'tempo') return null;
  final t = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
  return const {'recovery', 'strain', 'sleep', 'today'}.contains(t) ? t : null;
}

/// Widget taps, both the one that launched the app and later ones. Skipped
/// under `flutter test`, where the platform channels don't exist.
StreamSubscription<Uri?>? listenWidgetTaps(void Function(String) open) {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  HomeWidget.initiallyLaunchedFromHomeWidget()
      .then((u) {
        final t = widgetTarget(u);
        if (t != null) open(t);
      })
      .catchError((Object _) {});
  return HomeWidget.widgetClicked.listen((u) {
    final t = widgetTarget(u);
    if (t != null) open(t);
  }, onError: (Object _) {});
}
