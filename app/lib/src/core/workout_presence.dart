import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:scoring/scoring.dart' as sc;

import '../state/live_session.dart';
import 'background_guard.dart';
import 'format.dart';
import 'notifications.dart';

/// A running workout outside the app: the Live Activity on iOS (lock
/// screen and Dynamic Island) and an ongoing notification on Android (the
/// foreground service's own, or a plain one when no service runs).
/// Everything shown is computed on the phone; nothing leaves it.
abstract final class WorkoutPresence {
  static const _channel = MethodChannel('tempo/live_activity');
  static bool _service = false, _plain = false, _activity = false;
  static DateTime? _lastPush;

  /// Starts it. [band] and [location] decide the Android service types.
  static Future<void> start(
    LiveState s, {
    required bool band,
    required bool location,
  }) async {
    final v = WorkoutView.of(s);
    _lastPush = DateTime.now();
    if (Platform.isAndroid) {
      _service = await BackgroundGuard.start(
        v.clockTitle,
        text: v.line,
        band: band,
        location: location,
      );
      if (!_service) {
        _plain = true;
        await TempoNotifications.instance
            .showWorkout(title: v.title, body: v.line, since: v.since)
            .catchError((Object _) {});
      }
    } else if (Platform.isIOS) {
      try {
        _activity =
            await _channel.invokeMethod<bool>('start', v.toMap()) ?? false;
      } catch (e) {
        debugPrint('live activity: $e');
      }
    }
  }

  /// Pushes the latest numbers, at most every [every] unless [now].
  static Future<void> update(
    LiveState s, {
    bool now = false,
    Duration every = const Duration(seconds: 5),
  }) async {
    final last = _lastPush;
    final t = DateTime.now();
    if (!now && last != null && t.difference(last) < every) return;
    _lastPush = t;
    final v = WorkoutView.of(s);
    if (_service) {
      await BackgroundGuard.update(v.clockTitle, v.line);
    } else if (_plain) {
      await TempoNotifications.instance
          .showWorkout(
            title: v.title,
            body: v.line,
            since: v.since,
            paused: v.paused,
          )
          .catchError((Object _) {});
    } else if (_activity) {
      try {
        await _channel.invokeMethod('update', v.toMap());
      } catch (_) {}
    }
  }

  static Future<void> stop() async {
    if (_service) await BackgroundGuard.stop();
    if (_plain) await TempoNotifications.instance.cancelWorkout();
    if (_activity) {
      try {
        await _channel.invokeMethod('end');
      } catch (_) {}
    }
    _service = _plain = _activity = false;
    _lastPush = null;
  }

  /// Ends Live Activities a crash or a force-quit left behind.
  static Future<void> endStale() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('end');
    } catch (_) {}
  }
}

/// What the notification and the Live Activity show, as text, so both
/// platforms and the tests read the same thing.
@immutable
class WorkoutView {
  const WorkoutView({
    required this.title,
    required this.sport,
    required this.since,
    required this.elapsed,
    required this.paused,
    this.bpm,
    this.zone = 0,
    this.distance,
    this.distanceUnit = 'km',
    this.pace,
    this.paceUnit = '/km',
    required this.strain,
    this.segment,
  });

  factory WorkoutView.of(LiveState s) {
    final miles = !s.metric;
    final d = s.distanceM;
    final pace = s.paceNow ?? s.paceAvg;
    String? seg;
    if (s.guided) {
      final (i, left) = s.segment;
      if (i < s.plan!.segments.length) {
        seg =
            'Z${s.plan!.segments[i].zone} · ${mmss(Duration(seconds: left))} left';
      }
    }
    return WorkoutView(
      title: s.title,
      sport: s.sport?.name ?? 'other',
      since: DateTime.now().subtract(s.elapsed),
      elapsed: s.elapsed,
      paused: s.phase == LivePhase.paused,
      bpm: s.signalLost ? null : s.bpm,
      zone: s.bpm == null ? 0 : s.zone,
      distance: d == null || !s.onFoot
          ? null
          : (d / (miles ? 1609.344 : 1000)).toStringAsFixed(2),
      distanceUnit: miles ? 'mi' : 'km',
      pace: pace == null || !s.onFoot ? null : sc.paceText(pace, miles: miles),
      paceUnit: miles ? '/mi' : '/km',
      strain: s.timerOnly ? null : '+${n1(s.sessionStrain)}',
      segment: seg,
    );
  }

  final String title, sport;

  /// The start as a running clock sees it: now minus the moving time.
  final DateTime since;
  final Duration elapsed;
  final bool paused;
  final int? bpm;
  final int zone;
  final String? distance, pace, strain, segment;
  final String distanceUnit, paceUnit;

  /// "114 bpm · Z2 · 3.42 km · 6:12 /km · strain +2.4", shortest first
  /// when there's nothing to say: "Timing · heart rate from Health later".
  String get line {
    final parts = [
      if (paused) 'Paused',
      if (bpm != null) '$bpm bpm${zone > 0 ? ' · Z$zone' : ''}',
      if (distance != null) '$distance $distanceUnit',
      if (pace != null) '$pace $paceUnit',
      ?segment,
      if (strain != null) 'strain $strain',
    ];
    return parts.isEmpty
        ? 'Timing · heart rate from Health later'
        : parts.join(' · ');
  }

  /// "Walking · 51:03": the service's notification can't run a clock, so
  /// the time is in its title.
  String get clockTitle =>
      '${title.split(' · ').first} · ${mmss(elapsed)}${paused ? ' · paused' : ''}';

  /// The Live Activity's state (ios/Shared/TempoWorkoutAttributes.swift).
  Map<String, Object?> toMap() => {
    'title': title,
    'sport': sport,
    'since': since.millisecondsSinceEpoch,
    'elapsed': elapsed.inSeconds,
    'paused': paused,
    'bpm': bpm,
    'zone': zone,
    'distance': distance,
    'distanceUnit': distanceUnit,
    'pace': pace,
    'paceUnit': paceUnit,
    'strain': strain,
    'segment': segment,
  };
}
