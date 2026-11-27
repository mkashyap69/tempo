import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_extras.dart' show stepsToday;
import 'coach_notifier.dart';
import 'format.dart';
import 'today.dart';
import 'coach_service.dart';
import 'health_export.dart';
import '../billing/pro.dart' show proOpenInDb;

/// iOS app group shared with the WidgetKit extension.
const widgetAppGroup = 'group.dev.tempo.tempo';
const _android = [
  'TempoSmallWidget',
  'TempoMediumWidget',
  'TempoSessionWidget',
  'TempoDayWidget',
];
const _ios = [
  'TempoWidget',
  'TempoSessionWidget',
  'TempoDayWidget',
  'TempoLockWidget',
];

/// Fills are percentages; each widget lights that share of its ticks.
/// Pushes today's numbers to the home-screen widgets (WidgetKit / Android
/// AppWidget). Widgets show their own timestamp and dim when stale.
Future<void> updateHomeWidgets(
  TodayData t, {
  int? steps,
  bool pro = true,
}) async {
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
      'sleep_value': t.sleepScore == null ? '—' : '${t.sleepScore!.round()}',
      'sleep_state': t.slept == null ? 'No data' : hmShort(t.slept!),
      'sleep_fill': (t.sleepScore ?? 0).round(),
      'updated_at': '${(t.lastSync ?? DateTime.now()).millisecondsSinceEpoch}',
      ...sessionWidgetData(t, pro: pro),
      ...dayWidgetData(t, steps: steps),
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

/// The Day widget (large) and lock-screen widgets: today's call, steps
/// against the goal, strain against its target band, and tonight's bed
/// time and sleep need. Fills are percentages.
Map<String, Object?> dayWidgetData(TodayData t, {int? steps}) {
  final call = callFor(t);
  final goal = t.profile.effectiveStepGoal;
  final target = t.target;
  return {
    'call_lead': call.lead,
    'call_rest': call.rest,
    'call_tone': call.tone.name,
    'steps_value': steps == null ? '—' : grouped(steps),
    'steps_goal': grouped(goal),
    'steps_fill': steps == null
        ? 0
        : (steps * 100 / math.max(1, goal)).round().clamp(0, 100),
    'strain_lo': target.cap ? 0 : (target.lo / 21 * 100).round(),
    'strain_hi': (target.hi / 21 * 100).round(),
    'bed_time': fmtHm(t.bedtimeMinute),
    'sleep_need': hmShort(t.needTonight),
  };
}

/// Tempo Coach session widget: today's session, its status and whether
/// Start applies. Levels: pending, late, done, missed, rest.
///
/// Without Pro the widget shows where the plan lives instead of the plan.
Map<String, Object?> sessionWidgetData(TodayData t, {bool pro = true}) {
  if (!pro) {
    return {
      'session_title': 'Your plan',
      'session_detail': 'A session for today, with Tempo Pro',
      'session_status': '',
      'session_level': 'rest',
    };
  }
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
    sc.DayStatus.done ||
    sc.DayStatus.doneEasier ||
    sc.DayStatus.doneHarder => 'done',
    sc.DayStatus.missedDay || sc.DayStatus.skipped => 'missed',
    sc.DayStatus.missedSlot || sc.DayStatus.partial => 'late',
    _ => 'pending',
  };
  final status = switch (t.status) {
    sc.DayStatus.done => 'Done ✓',
    sc.DayStatus.doneEasier => 'Done, easier',
    sc.DayStatus.doneHarder => 'Done, harder',
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
  try {
    await CoachService(db).reconcileToday();
  } catch (e) {
    debugPrint('coach reconcile: $e');
  }
  final t = await loadToday(db);
  int? steps;
  try {
    steps = await stepsToday(db, DateTime.now());
  } catch (_) {}
  await updateHomeWidgets(t, steps: steps, pro: await proOpenInDb(db));
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
        'workout',
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
