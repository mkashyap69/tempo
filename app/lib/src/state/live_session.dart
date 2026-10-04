import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import '../core/coach_service.dart';
import '../core/background_guard.dart';
import '../core/score_service.dart' show saveRpe;
import '../core/profile.dart';
import 'providers.dart';

enum LivePhase { connecting, live, paused, ended, failed }

@immutable
class LiveState {
  const LiveState({
    required this.phase,
    required this.sport,
    required this.title,
    this.plan,
    this.bpm,
    this.signalLost = false,
    this.elapsed = Duration.zero,
    this.trimp = 0,
    this.zoneSeconds = const [0, 0, 0, 0, 0],
    this.hrMax = 190,
    this.dayTrimpBefore = 0,
    this.target,
    this.error,
    this.workoutId,
    this.avgHr,
    this.maxHr,
    this.startedAt,
  });

  final LivePhase phase;
  final sc.Sport? sport;
  final String title;
  final sc.Session? plan;
  final int? bpm;
  final bool signalLost;
  final Duration elapsed;
  final double trimp;
  final List<int> zoneSeconds;
  final int hrMax;
  final double dayTrimpBefore;
  final sc.StrainTarget? target;
  final String? error;
  final int? workoutId;
  final int? avgHr, maxHr;
  final DateTime? startedAt;

  bool get guided => plan != null && plan!.segments.isNotEmpty;
  int get zone => bpm == null ? 0 : sc.zoneFor(bpm!, hrMax);
  double get dayStrainBefore => sc.strainFromTrimp(dayTrimpBefore);
  double get dayStrain => sc.strainFromTrimp(dayTrimpBefore + trimp);
  double get sessionStrain => dayStrain - dayStrainBefore;

  /// Index of the current segment and seconds left in it.
  (int, int) get segment {
    if (!guided) return (-1, 0);
    var acc = 0;
    final s = elapsed.inSeconds;
    for (final (i, seg) in plan!.segments.indexed) {
      acc += seg.minutes * 60;
      if (s < acc) return (i, acc - s);
    }
    return (plan!.segments.length, 0);
  }

  LiveState copyWith({
    LivePhase? phase,
    int? Function()? bpm,
    bool? signalLost,
    Duration? elapsed,
    double? trimp,
    List<int>? zoneSeconds,
    String? error,
    int? workoutId,
    int? avgHr,
    int? maxHr,
    DateTime? startedAt,
  }) => LiveState(
    phase: phase ?? this.phase,
    sport: sport,
    title: title,
    plan: plan,
    bpm: bpm == null ? this.bpm : bpm(),
    signalLost: signalLost ?? this.signalLost,
    elapsed: elapsed ?? this.elapsed,
    trimp: trimp ?? this.trimp,
    zoneSeconds: zoneSeconds ?? this.zoneSeconds,
    hrMax: hrMax,
    dayTrimpBefore: dayTrimpBefore,
    target: target,
    error: error ?? this.error,
    workoutId: workoutId ?? this.workoutId,
    avgHr: avgHr ?? this.avgHr,
    maxHr: maxHr ?? this.maxHr,
    startedAt: startedAt ?? this.startedAt,
  );
}

final liveSessionProvider = NotifierProvider<LiveSession, LiveState?>(
  LiveSession.new,
);

/// One workout at a time. Holds the band (and its lock) until the session
/// ends, so minimising the screen keeps it running.
class LiveSession extends Notifier<LiveState?> {
  BandLink? _link;
  StreamSubscription<int>? _hr;
  Timer? _clock;
  DateTime? _lastBeat, _lastTick;
  final _beats = <int>[];
  bool _buzz = true;
  int _lastBuzzSegment = -1;

  @override
  LiveState? build() {
    ref.onDispose(_teardown);
    return null;
  }

  Future<void> start({sc.Session? plan, sc.Sport? sport}) async {
    if (state != null &&
        state!.phase != LivePhase.ended &&
        state!.phase != LivePhase.failed) {
      return;
    }
    final db = ref.read(dbProvider);
    final profile = await loadAppProfile(db) ?? const Profile();
    final today = await db.scoreFor(dayOf(DateTime.now()));
    final recent = await db.scoresBefore(
      dayOf(DateTime.now()).add(const Duration(days: 1)),
      limit: 1,
    );
    final hrMax = recent.isEmpty ? profile.effectiveMaxHr : recent.first.hrMax;
    final rest = recent.isEmpty ? 60.0 : (recent.first.rhr ?? 60);
    _rest = rest;
    _buzz = (await db.setting(Keys.buzzCues) ?? '1') == '1';
    final t = sc.strainTarget(
      recovery: today?.calibrating ?? true ? null : today?.recovery,
      calibrating: today?.calibrating ?? true,
    );
    _beats.clear();
    _lastBuzzSegment = -1;
    state = LiveState(
      phase: LivePhase.connecting,
      sport: plan?.sport ?? sport,
      title: plan?.title ?? '${sportName(plan?.sport ?? sport)} · open session',
      plan: plan,
      hrMax: hrMax,
      dayTrimpBefore: today?.trimp ?? 0,
      target: t,
    );
    try {
      final link = _link = await BandLink.open(
        db,
        wait: const Duration(seconds: 15),
      );
      final stream = await link.band.startLiveHr();
      await BackgroundGuard.start(state!.title);
      HapticFeedback.mediumImpact();
      _hr = stream.listen(_onBeat);
      _lastTick = DateTime.now();
      // Timer starts on the first beat (design: States × screens).
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      state = state!.copyWith(phase: LivePhase.failed, error: '$e');
      await _teardown();
    }
  }

  double _rest = 60;

  void _onBeat(int bpm) {
    final s = state;
    if (s == null) return;
    final now = DateTime.now();
    final wasLost = s.signalLost;
    _lastBeat = now;
    if (s.phase == LivePhase.connecting) {
      state = s.copyWith(phase: LivePhase.live, bpm: () => bpm, startedAt: now);
      return;
    }
    ref
        .read(dbProvider)
        .appendHrLive(st.toTs(now), bpm)
        .catchError((Object _) {});
    if (s.phase == LivePhase.live) _beats.add(bpm);
    state = s.copyWith(bpm: () => bpm, signalLost: false);
    if (wasLost && _buzz) _link?.band.buzz().catchError((Object _) {});
  }

  void _tick() {
    final s = state;
    if (s == null) return;
    final now = DateTime.now();
    final dt = now.difference(_lastTick ?? now);
    _lastTick = now;
    if (s.phase != LivePhase.live) return;
    final lost =
        _lastBeat == null ||
        now.difference(_lastBeat!) > const Duration(seconds: 10);
    var trimp = s.trimp;
    final zones = [...s.zoneSeconds];
    if (!lost && s.bpm != null) {
      trimp +=
          sc.minuteTrimp(s.bpm!, hrRest: _rest, hrMax: s.hrMax.toDouble()) *
          dt.inMilliseconds /
          60000;
      final z = sc.zoneFor(s.bpm!, s.hrMax);
      zones[(z < 1 ? 1 : z) - 1] += dt.inSeconds;
    }
    final next = s.copyWith(
      elapsed: s.elapsed + dt,
      trimp: trimp,
      zoneSeconds: zones,
      signalLost: lost,
      bpm: lost ? () => null : null,
    );
    state = next;
    if (next.elapsed.inSeconds % 15 == 0 && next.bpm != null) {
      final m = next.elapsed.inMinutes;
      final sec = (next.elapsed.inSeconds % 60).toString().padLeft(2, '0');
      BackgroundGuard.update('${next.bpm} bpm · $m:$sec');
    }
    // Interval cues: buzz the band 5 s before a change; haptic on change.
    if (next.guided) {
      final (i, left) = next.segment;
      if (left == 5 && _lastBuzzSegment != i && _buzz) {
        _lastBuzzSegment = i;
        _link?.band.buzz().catchError((Object _) {});
      }
      final (pi, _) = s.segment;
      if (pi != i) HapticFeedback.mediumImpact();
    }
    // Rest-day cap: one warning when the day passes it.
    final cap = s.target;
    if (cap != null &&
        cap.cap &&
        s.dayStrain < cap.hi &&
        next.dayStrain >= cap.hi) {
      HapticFeedback.heavyImpact();
      if (_buzz) _link?.band.buzz(strong: true).catchError((Object _) {});
    }
  }

  void pause() {
    if (state?.phase != LivePhase.live) return;
    HapticFeedback.mediumImpact();
    state = state!.copyWith(phase: LivePhase.paused);
  }

  void resume() {
    if (state?.phase != LivePhase.paused) return;
    HapticFeedback.mediumImpact();
    _lastTick = DateTime.now();
    state = state!.copyWith(phase: LivePhase.live);
  }

  /// Saves the workout and moves to the summary.
  Future<int?> end() async {
    final s = state;
    if (s == null) return null;
    HapticFeedback.mediumImpact();
    final started = s.startedAt;
    await _teardown();
    if (started == null || s.elapsed.inSeconds < 30) {
      state = null;
      return null;
    }
    final avg = _beats.isEmpty
        ? null
        : (_beats.reduce((a, b) => a + b) / _beats.length).round();
    final mx = _beats.isEmpty ? null : _beats.reduce((a, b) => a > b ? a : b);
    final id = await ref
        .read(dbProvider)
        .addWorkout(
          st.WorkoutsCompanion.insert(
            start: st.toTs(started),
            end: st.toTs(started.add(s.elapsed)),
            sport: Value(s.sport?.name),
            title: s.plan?.title ?? sportName(s.sport),
            source: 'live',
            confirmed: const Value(true),
            strain: s.sessionStrain,
            trimp: s.trimp,
            avgHr: Value(avg),
            maxHr: Value(mx),
            zones: jsonEncode([
              for (final z in s.zoneSeconds) (z / 60).round(),
            ]),
            plan: Value(s.plan == null ? null : jsonEncode(s.plan!.toJson())),
          ),
        );
    state = s.copyWith(
      phase: LivePhase.ended,
      workoutId: id,
      avgHr: avg,
      maxHr: mx,
      bpm: () => null,
    );
    return id;
  }

  Future<void> rate(int rpe) async {
    final id = state?.workoutId;
    if (id == null) return;
    HapticFeedback.selectionClick();
    await saveRpe(ref.read(dbProvider), id, rpe);
  }

  /// Leaves the summary.
  void close() => state = null;

  Future<void> _teardown() async {
    await BackgroundGuard.stop();
    _clock?.cancel();
    _clock = null;
    await _hr?.cancel();
    _hr = null;
    final link = _link;
    _link = null;
    if (link != null) {
      try {
        await link.band.stopLiveHr();
      } catch (_) {}
      await link.close();
    }
  }
}

String sportName(sc.Sport? s) => sportLabel(s);
