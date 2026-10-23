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
import '../core/data_source.dart';
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
    this.noSignalSeconds = 0,
    this.trace = const [],
    this.hrMax = 190,
    this.hrRest = 60,
    this.female = false,
    this.zoneRest,
    this.dayTrimpBefore = 0,
    this.target,
    this.error,
    this.workoutId,
    this.avgHr,
    this.maxHr,
    this.startedAt,
    this.timerOnly = false,
    this.steps,
    this.cadence,
  });

  final LivePhase phase;
  final sc.Sport? sport;
  final String title;
  final sc.Session? plan;
  final int? bpm;
  final bool signalLost;
  final Duration elapsed;
  final double trimp;

  /// Seconds in Z1..Z5 (below Z1 counts as Z1), from the ticks' exact
  /// durations: a 999 ms tick still adds 0.999 s.
  final List<double> zoneSeconds;

  /// Seconds the band sent nothing, so zones plus this add up to [elapsed].
  final double noSignalSeconds;

  /// (elapsed seconds, bpm), one per tick, the last [traceWindow] only.
  final List<(int, int)> trace;
  final int hrMax;
  final double hrRest;

  /// Banister's female TRIMP weighting, as the day's score uses.
  final bool female;

  /// Resting HR for reserve zones (Profile), else null: % of max HR.
  final double? zoneRest;
  final double dayTrimpBefore;
  final sc.StrainTarget? target;
  final String? error;
  final int? workoutId;
  final int? avgHr, maxHr;
  final DateTime? startedAt;

  /// A Health source gives no live heart rate: the session is timed only,
  /// and its heart rate and strain are filled in from Health after the
  /// next read (ScoreService._activities).
  final bool timerOnly;

  /// Steps since the start and steps per minute lately, from the band's
  /// day totals; null until the band answers or with no band.
  final int? steps, cadence;

  static const traceWindow = 15 * 60;

  bool get guided => plan != null && plan!.segments.isNotEmpty;
  int get zone => bpm == null ? 0 : sc.zoneFor(bpm!, hrMax, hrRest: zoneRest);
  double get dayStrainBefore => sc.strainFromTrimp(dayTrimpBefore);
  double get dayStrain => sc.strainFromTrimp(dayTrimpBefore + trimp);
  double get sessionStrain => dayStrain - dayStrainBefore;

  /// One clock tick of [dt]: TRIMP and zone time grow with the exact
  /// duration; with no signal the time counts as [noSignalSeconds].
  LiveState advance(Duration dt, {required bool lost}) {
    final sec = dt.inMicroseconds / 1e6;
    final b = lost ? null : bpm;
    var t = trimp, gap = noSignalSeconds;
    final zones = [...zoneSeconds];
    final at = (elapsed + dt).inSeconds;
    var tr = trace;
    if (b != null) {
      t +=
          sc.minuteTrimp(
            b,
            hrRest: hrRest,
            hrMax: hrMax.toDouble(),
            female: female,
          ) *
          sec /
          60;
      final z = sc.zoneFor(b, hrMax, hrRest: zoneRest);
      zones[(z < 1 ? 1 : z) - 1] += sec;
      tr = [
        for (final e in trace)
          if (e.$1 > at - traceWindow) e,
        (at, b),
      ];
    } else if (!timerOnly) {
      gap += sec;
    }
    return copyWith(
      elapsed: elapsed + dt,
      trimp: t,
      zoneSeconds: zones,
      noSignalSeconds: gap,
      trace: tr,
      signalLost: lost,
      bpm: lost ? () => null : null,
    );
  }

  /// Mean bpm over the last [seconds] of the trace, or null with under a
  /// minute of readings.
  double? recentBpm([int seconds = 300]) {
    final from = elapsed.inSeconds - seconds;
    final r = [
      for (final e in trace)
        if (e.$1 > from) e.$2,
    ];
    if (r.length < 60) return null;
    return r.reduce((a, b) => a + b) / r.length;
  }

  /// Strain per minute at the last five minutes' heart rate.
  double? get strainRate {
    final hr = recentBpm();
    if (hr == null) return null;
    final per = sc.minuteTrimp(
      hr.round(),
      hrRest: hrRest,
      hrMax: hrMax.toDouble(),
      female: female,
    );
    return sc.strainFromTrimp(dayTrimpBefore + trimp + per) - dayStrain;
  }

  /// Minutes more at the last five minutes' heart rate until the day
  /// reaches [goal] strain. Null when already there, with too little data,
  /// or when it would take over three hours.
  int? minutesTo(double goal) {
    if (dayStrain >= goal) return null;
    final hr = recentBpm();
    if (hr == null) return null;
    final per = sc.minuteTrimp(
      hr.round(),
      hrRest: hrRest,
      hrMax: hrMax.toDouble(),
      female: female,
    );
    if (per <= 0) return null;
    for (var m = 1; m <= 180; m++) {
      if (sc.strainFromTrimp(dayTrimpBefore + trimp + per * m) >= goal) {
        return m;
      }
    }
    return null;
  }

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
    List<double>? zoneSeconds,
    double? noSignalSeconds,
    List<(int, int)>? trace,
    String? error,
    int? workoutId,
    int? avgHr,
    int? maxHr,
    DateTime? startedAt,
    int? steps,
    int? cadence,
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
    noSignalSeconds: noSignalSeconds ?? this.noSignalSeconds,
    trace: trace ?? this.trace,
    hrMax: hrMax,
    hrRest: hrRest,
    female: female,
    zoneRest: zoneRest,
    dayTrimpBefore: dayTrimpBefore,
    timerOnly: timerOnly,
    target: target,
    error: error ?? this.error,
    workoutId: workoutId ?? this.workoutId,
    avgHr: avgHr ?? this.avgHr,
    maxHr: maxHr ?? this.maxHr,
    startedAt: startedAt ?? this.startedAt,
    steps: steps ?? this.steps,
    cadence: cadence ?? this.cadence,
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
  int _beatSum = 0;
  Timer? _stepClock;
  int? _stepsAtStart, _lastSteps;
  DateTime? _lastStepsAt;
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
    _buzz = (await db.setting(Keys.buzzCues) ?? '1') == '1';
    final t = sc.strainTarget(
      recovery: today?.calibrating ?? true ? null : today?.recovery,
      calibrating: today?.calibrating ?? true,
    );
    _beats.clear();
    _beatSum = 0;
    _stepsAtStart = _lastSteps = _lastStepsAt = null;
    _lastBuzzSegment = -1;
    if ((await loadDataSource(db)).isHealth) {
      final now = DateTime.now();
      HapticFeedback.mediumImpact();
      state = LiveState(
        phase: LivePhase.live,
        sport: plan?.sport ?? sport,
        title:
            plan?.title ?? '${sportName(plan?.sport ?? sport)} · open session',
        plan: plan,
        hrMax: hrMax,
        hrRest: rest,
        female: !profile.male,
        zoneRest: profile.zonesByReserve ? rest : null,
        dayTrimpBefore: today?.trimp ?? 0,
        target: t,
        startedAt: now,
        timerOnly: true,
      );
      _lastTick = now;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      return;
    }
    state = LiveState(
      phase: LivePhase.connecting,
      sport: plan?.sport ?? sport,
      title: plan?.title ?? '${sportName(plan?.sport ?? sport)} · open session',
      plan: plan,
      hrMax: hrMax,
      hrRest: rest,
      female: !profile.male,
      zoneRest: profile.zonesByReserve ? rest : null,
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
      unawaited(_readSteps());
      _stepClock = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _readSteps(),
      );
    } catch (e) {
      state = state!.copyWith(phase: LivePhase.failed, error: '$e');
      await _teardown();
    }
  }

  /// Session steps from the band's day total, and cadence from the last
  /// two reads. Skipped while paused so cadence reflects moving time.
  Future<void> _readSteps() async {
    final link = _link;
    if (link == null) return;
    final r = await link.band.readRealtimeSteps();
    final s = state;
    if (r == null || s == null || _link != link) return;
    final now = DateTime.now();
    final start = _stepsAtStart ??= r.steps;
    int? cadence;
    final last = _lastSteps, at = _lastStepsAt;
    if (last != null && at != null && s.phase == LivePhase.live) {
      final min = now.difference(at).inSeconds / 60;
      if (min > 0 && r.steps >= last) {
        cadence = ((r.steps - last) / min).round();
      }
    }
    _lastSteps = r.steps;
    _lastStepsAt = now;
    // Midnight resets the band's total; keep the count already reached.
    if (r.steps < start) {
      _stepsAtStart = r.steps - (s.steps ?? 0);
    }
    state = s.copyWith(steps: r.steps - _stepsAtStart!, cadence: cadence);
  }

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
    var avg = s.avgHr, mx = s.maxHr;
    if (s.phase == LivePhase.live) {
      _beats.add(bpm);
      _beatSum += bpm;
      avg = (_beatSum / _beats.length).round();
      mx = mx == null || bpm > mx ? bpm : mx;
    }
    state = s.copyWith(
      bpm: () => bpm,
      signalLost: false,
      avgHr: avg,
      maxHr: mx,
    );
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
        !s.timerOnly &&
        (_lastBeat == null ||
            now.difference(_lastBeat!) > const Duration(seconds: 10));
    final next = s.advance(dt, lost: lost);
    state = next;
    if (next.elapsed.inSeconds % 15 == 0 && next.bpm != null) {
      final m = next.elapsed.inMinutes;
      final sec = (next.elapsed.inSeconds % 60).toString().padLeft(2, '0');
      final z = next.zone;
      BackgroundGuard.update(
        '${next.bpm} bpm${z > 0 ? ' · Z$z' : ''} · $m:$sec'
        ' · strain +${next.sessionStrain.toStringAsFixed(1)}',
      );
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
    final avg = _beats.isEmpty ? null : (_beatSum / _beats.length).round();
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
    // Timed only: the watch's heart rate for it arrives with the next read.
    if (s.timerOnly) unawaited(ref.read(syncProvider.notifier).syncNow());
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
    _stepClock?.cancel();
    _stepClock = null;
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

/// Live workouts saved before 2026-10-18 lost about half their zone time
/// (the tick added whole seconds only). Rebuilds their zones once from the
/// live heart rate they recorded; strain was right and stays.
Future<void> repairLiveZones(st.TempoDb db) async {
  if (await db.setting(Keys.liveZonesV2) == '1') return;
  final profile = await loadAppProfile(db) ?? const Profile();
  final all = await db.workoutsBetween(
    DateTime(2000),
    DateTime.now().add(const Duration(minutes: 1)),
  );
  for (final w in all) {
    if (w.source != 'live') continue;
    final a = st.fromTs(w.start);
    final hr = await db.hrLiveBetween(a, st.fromTs(w.end));
    if (hr.length < 60) continue;
    // The max HR the session itself used: the latest score up to that day.
    final recent = await db.scoresBefore(
      dayOf(a).add(const Duration(days: 1)),
      limit: 1,
    );
    final zones = sc.zoneSecondsFromSamples(
      [for (final h in hr) (h.ts, h.bpm)],
      recent.isEmpty ? profile.effectiveMaxHr : recent.first.hrMax,
      end: w.end,
    );
    await db.updateWorkout(
      w.id,
      st.WorkoutsCompanion(
        zones: Value(jsonEncode([for (final z in zones) (z / 60).round()])),
      ),
    );
  }
  await db.putSetting(Keys.liveZonesV2, '1');
}
