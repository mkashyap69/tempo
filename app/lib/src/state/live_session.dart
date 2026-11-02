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
import '../core/data_source.dart';
import '../core/location_feed.dart';
import '../core/route_tracker.dart';
import '../core/workout_presence.dart';
import '../core/score_service.dart' show saveRpe;
import '../core/profile.dart';
import 'providers.dart';

enum LivePhase { connecting, live, paused, ended, failed }

/// Phone GPS for a walk or run: not used (another sport, or off), waiting
/// for a first good fix, giving fixes, or location not allowed.
enum GpsState { off, searching, on, denied }

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
    this.distanceM,
    this.distanceSource,
    this.paceNow,
    this.paceAvg,
    this.splits = const [],
    this.kcal,
    this.metric = true,
    this.gps = GpsState.off,
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

  /// Metres since the start (moving time only), from phone GPS or the
  /// band's counter; null until either has some.
  final double? distanceM;
  final DistanceSource? distanceSource;

  /// Seconds per km: over the last minute or two, and over the session.
  final double? paceNow, paceAvg;

  /// Seconds per completed km (or mile when not [metric]).
  final List<double> splits;

  /// Calories the band counted since the start. TODO(verify) against Mi
  /// Fitness for one walk.
  final int? kcal;

  /// Kilometres, else miles (Profile).
  final bool metric;
  final GpsState gps;

  bool get onFoot => sport == sc.Sport.walking || sport == sc.Sport.running;

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
    double? distanceM,
    DistanceSource? distanceSource,
    double? Function()? paceNow,
    double? Function()? paceAvg,
    List<double>? splits,
    int? kcal,
    GpsState? gps,
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
    distanceM: distanceM ?? this.distanceM,
    distanceSource: distanceSource ?? this.distanceSource,
    paceNow: paceNow == null ? this.paceNow : paceNow(),
    paceAvg: paceAvg == null ? this.paceAvg : paceAvg(),
    splits: splits ?? this.splits,
    kcal: kcal ?? this.kcal,
    metric: metric,
    gps: gps ?? this.gps,
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
  RouteTracker? _gpsRoute, _bandRoute;
  StreamSubscription<GeoFix>? _geo;
  int? _metersAtStart, _kcalAtStart;

  @override
  LiveState? build() {
    ref.onDispose(_teardown);
    ref.onDispose(() => _lateSync?.cancel());
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
    final recovery = today?.calibrating ?? true ? null : today?.recovery;
    final load = await loadFor(db, dayOf(DateTime.now()));
    final t = sc.personalTarget(
      sc.strainTarget(
        recovery: recovery,
        calibrating: today?.calibrating ?? true,
        load: load.status,
        loadRatio: load.ratio,
      ),
      recovery: recovery,
      load: load,
    );
    _beats.clear();
    _beatSum = 0;
    _stepsAtStart = _lastSteps = _lastStepsAt = null;
    _metersAtStart = _kcalAtStart = null;
    _lastBuzzSegment = -1;
    // Walks and runs: phone GPS for distance and pace, asked for once.
    final kind = plan?.sport ?? sport;
    final onFoot = kind == sc.Sport.walking || kind == sc.Sport.running;
    final gpsOk = onFoot && await LocationFeed.ensureAccess();
    final gps = !onFoot
        ? GpsState.off
        : gpsOk
        ? GpsState.searching
        : GpsState.denied;
    final splitM = profile.metric ? 1000.0 : 1609.344;
    _gpsRoute = RouteTracker(splitM: splitM);
    _bandRoute = RouteTracker(splitM: splitM);
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
        metric: profile.metric,
        gps: gps,
      );
      _lastTick = now;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      await WorkoutPresence.start(state!, band: false, location: gpsOk);
      if (gpsOk) _listenGps();
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
      metric: profile.metric,
      gps: gps,
    );
    try {
      final link = _link = await BandLink.open(
        db,
        wait: const Duration(seconds: 15),
      );
      final stream = await link.band.startLiveHr();
      await WorkoutPresence.start(state!, band: true, location: gpsOk);
      HapticFeedback.mediumImpact();
      _hr = stream.listen(_onBeat);
      if (gpsOk) _listenGps();
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
    // Distance and calories: the band's day totals, rebased at midnight
    // and while paused so neither counts.
    final route = _bandRoute;
    var m0 = _metersAtStart ??= r.meters;
    var k0 = _kcalAtStart ??= r.kcal;
    if (route != null) {
      if (r.meters < m0 || s.phase != LivePhase.live) {
        m0 = _metersAtStart = r.meters - route.meters.round();
      }
      if (s.phase == LivePhase.live) {
        route.setTotal((r.meters - m0).toDouble(), _moving(s));
      }
    }
    if (r.kcal < k0 || s.phase != LivePhase.live) {
      k0 = _kcalAtStart = r.kcal - (s.kcal ?? 0);
    }
    state = _withRoute(
      s.copyWith(
        steps: r.steps - _stepsAtStart!,
        cadence: cadence,
        kcal: r.kcal - k0,
      ),
    );
  }

  static double _moving(LiveState s) => s.elapsed.inMilliseconds / 1000;

  void _listenGps() {
    _geo = LocationFeed.fixes().listen(
      _onFix,
      onError: (Object _) {
        final s = state;
        if (s != null && s.gps == GpsState.searching) {
          state = s.copyWith(gps: GpsState.denied);
        }
      },
    );
  }

  void _onFix(GeoFix f) {
    final s = state, r = _gpsRoute;
    if (s == null || r == null || s.phase != LivePhase.live) return;
    r.addFix(f, _moving(s));
    if (s.gps == GpsState.searching &&
        f.accuracyM <= RouteTracker.maxAccuracyM) {
      state = _withRoute(s.copyWith(gps: GpsState.on));
    }
  }

  /// Distance and pace onto [s]: GPS once it has a fix (and from then on,
  /// so the number never jumps between sources), else the band's counter.
  LiveState _withRoute(LiveState s) {
    if (!s.onFoot) return s;
    final g = _gpsRoute, b = _bandRoute;
    final useGps = g != null && (s.gps == GpsState.on || g.meters > 0);
    final r = useGps ? g : (b != null && b.meters > 0 ? b : null);
    if (r == null) return s;
    final t = _moving(s);
    return s.copyWith(
      distanceM: r.meters,
      distanceSource: useGps ? DistanceSource.gps : DistanceSource.band,
      // The band answers every 20 s: a wider window for a steady number.
      paceNow: () =>
          useGps ? r.paceNow(t) : r.paceNow(t, window: 120, minWindowS: 40),
      paceAvg: () => r.paceAvg(t),
      splits: r.splits,
    );
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
    final next = _withRoute(s.advance(dt, lost: lost));
    state = next;
    unawaited(WorkoutPresence.update(next));
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
    _gpsRoute?.breakLeg();
    state = state!.copyWith(phase: LivePhase.paused);
    unawaited(WorkoutPresence.update(state!, now: true));
  }

  void resume() {
    if (state?.phase != LivePhase.paused) return;
    HapticFeedback.mediumImpact();
    _lastTick = DateTime.now();
    _gpsRoute?.breakLeg();
    state = state!.copyWith(phase: LivePhase.live);
    unawaited(WorkoutPresence.update(state!, now: true));
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
            distanceM: Value(
              (s.distanceM ?? 0) >= 50 ? s.distanceM!.roundToDouble() : null,
            ),
          ),
        );
    // Day strain comes from the source's minutes (the band's history, or
    // the watch's heart rate in Health), not from this screen: read them
    // now so Today and the scores move without a manual sync, and once
    // more a few minutes later for minutes that arrive late.
    unawaited(_refreshScores());
    state = s.copyWith(
      phase: LivePhase.ended,
      workoutId: id,
      avgHr: avg,
      maxHr: mx,
      bpm: () => null,
    );
    return id;
  }

  Timer? _lateSync;

  Future<void> _refreshScores() async {
    _lateSync?.cancel();
    final sync = ref.read(syncProvider.notifier);
    try {
      await sync.syncNow();
    } catch (_) {}
    _lateSync = Timer(const Duration(minutes: 3), () {
      final p = state?.phase;
      // Not while another session holds the band.
      if (p == LivePhase.live || p == LivePhase.paused) return;
      if (p == LivePhase.connecting) return;
      sync.syncNow().catchError((Object _) => const SyncStatus());
    });
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
    await WorkoutPresence.stop();
    await _geo?.cancel();
    _geo = null;
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
