import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_notifier.dart';
import 'format.dart';
import 'today.dart';
import 'coach_service.dart';
import 'health_export.dart';

/// iOS app group shared with the WidgetKit extension.
const widgetAppGroup = 'group.dev.tempo.tempo';
const _android = [
  'TempoSmallWidget',
  'TempoMediumWidget',
  'TempoSessionWidget',
];
const _ios = ['TempoWidget', 'TempoSessionWidget'];

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
      ...sessionWidgetData(t),
    };
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData(e.key, e.value);
    }
    for (final a in _android) {
      await HomeWidget.updateWidget(androidName: a);
    }
    for (final i in _ios) {
      await HomeWidget.updateWidget(iOSName: i);
    }
  } catch (e) {
    debugPrint('home widgets: $e');
  }
}

/// Tempo Coach session widget: today's session, its status and whether
/// Start applies. Levels: pending, late, done, missed, rest.
Map<String, Object?> sessionWidgetData(TodayData t) {
  final p = t.plan;
  if (p == null || p.isRest || t.restDay) {
    return {
      'session_title': t.restDay ? 'Rest day' : 'Rest',
      'session_detail':
          'Walk if you like · in bed by ${fmtHm(t.bedtimeMinute)}',
      'session_status': '',
      'session_level': 'rest',
    };
  }
  final level = switch (t.status) {
    sc.DayStatus.done || sc.DayStatus.doneEasier => 'done',
    sc.DayStatus.missedDay || sc.DayStatus.skipped => 'missed',
    sc.DayStatus.missedSlot || sc.DayStatus.partial => 'late',
    _ => 'pending',
  };
  final status = switch (t.status) {
    sc.DayStatus.done => 'Done ✓',
    sc.DayStatus.doneEasier => 'Done, easier',
    sc.DayStatus.partial => 'Partly done',
    sc.DayStatus.missedSlot =>
      t.rescue.offered
          ? 'Still time · ${fmtHm(t.rescue.start!)}'
          : 'Not seen yet',
    sc.DayStatus.missedDay => 'Missed',
    sc.DayStatus.skipped => 'Skipped',
    sc.DayStatus.moved || sc.DayStatus.pending =>
      t.plannedMinute == null
          ? 'Any time today'
          : 'Planned ${fmtHm(t.plannedMinute!)}',
    sc.DayStatus.rest => '',
  };
  return {
    'session_title': '${p.title} ${p.minutes}′',
    'session_detail': '${p.zones}${p.note.isEmpty ? '' : ' · ${p.note}'}',
    'session_status': status,
    'session_level': level,
  };
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

/// Rebuilds every pending coach notification from the latest state
/// (Tempo Coach). [t] is accepted for older call sites and ignored.
Future<void> rescheduleNotifications(st.TempoDb db, [TodayData? t]) async {
  try {
    await CoachNotifier(db).refresh();
  } catch (e) {
    debugPrint('notifications: $e');
  }
}

/// Which detail screen a widget tap asks for: recovery, strain, sleep or
/// today (the tab itself). null for anything else.
String? widgetTarget(Uri? uri) {
  if (uri == null || uri.scheme != 'tempo') return null;
  final t = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
  return const {
        'recovery',
        'strain',
        'sleep',
        'today',
        'coach',
        'start',
      }.contains(t)
      ? t
      : null;
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
