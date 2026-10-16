import 'dart:math' as math;

import 'package:health_source/health_source.dart' as hs;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'data_source.dart';
import 'minutes.dart';
import 'pause.dart';
import 'score_service.dart' show parseDateKey;

/// Everyday metrics for one day, from the active source (decisions.md,
/// 2026-10-15). Each loader reads only what its card needs.

// ---- Rhythm: sleep regularity and social jetlag ---------------------------

final class Rhythm {
  const Rhythm({this.sri, this.jetlag, required this.days});

  /// Sleep Regularity Index over the last 7 days (null while learning).
  final double? sri;
  final sc.SocialJetlag? jetlag;

  /// Days with data in the SRI window, for "learning · 4 of 7".
  final int days;

  sc.Regularity? get band => sri == null ? null : sc.regularityBand(sri!);
}

/// Days of minutes the SRI is computed over.
const rhythmDays = 7;

Future<Rhythm> loadRhythm(st.TempoDb db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final today = dayOf(at);
  final from = today.subtract(const Duration(days: rhythmDays));
  final mins = (await loadMinutes(db, from, at)).minutes;
  final withData = <String>{
    for (final m in mins)
      if (!m.offWrist && m.stage != sc.Stage.unknown) st.dateKey(m.ts),
  };
  final nights = [
    for (final s in await db.scoresBetween(
      today.subtract(const Duration(days: 28)),
      today,
    ))
      if (s.sleepStart != null && s.sleepEnd != null)
        (start: st.fromTs(s.sleepStart!), end: st.fromTs(s.sleepEnd!)),
  ];
  return Rhythm(
    sri: sc.sleepRegularity(mins),
    jetlag: sc.socialJetlag(nights),
    days: withData.length.clamp(0, rhythmDays),
  );
}

// ---- Body signals ------------------------------------------------------------

/// Body signals for the night ending on [day]'s morning, against up to 60
/// earlier nights of the same source (paused days left out).
Future<sc.BodySignals> loadBodySignals(
  st.TempoDb db, {
  DateTime? day,
  ({DateTime a, DateTime b})? tonight,
}) async {
  final d = dayOf(day ?? DateTime.now());
  final score = await db.scoreFor(d);
  final source = score?.source ?? (await loadDataSource(db)).key;
  final pauses = await loadPauses(db);
  final past = [
    for (final s in await db.scoresBefore(d, limit: 60))
      if (s.source == source && !isPaused(pauses, parseDateKey(s.date))) s,
  ];
  final health = source != sc.bandSource;
  final hrvKind = score?.hrvKind;

  // Nights as spans, today's first, for SpO₂ and breathing rate.
  ({DateTime a, DateTime b})? span(st.DailyScore? s) =>
      s?.sleepStart == null || s?.sleepEnd == null
      ? null
      : (a: st.fromTs(s!.sleepStart!), b: st.fromTs(s.sleepEnd!));
  // [tonight] stands in for the stored night while the day is being
  // scored (score_service: the recovery penalty).
  final spans = [tonight ?? span(score), for (final s in past) span(s)];
  final real = spans.whereType<({DateTime a, DateTime b})>().toList();
  final lo = real.isEmpty
      ? d
      : real.map((x) => x.a).reduce((x, y) => x.isBefore(y) ? x : y);
  final hi = real.isEmpty
      ? d
      : real.map((x) => x.b).reduce((x, y) => x.isAfter(y) ? x : y);
  final spo2 = await loadSpo2(db, lo, hi.add(const Duration(minutes: 1)));
  final resp = health
      ? await loadHealthRecords(
          db,
          lo.subtract(const Duration(hours: 1)),
          hi.add(const Duration(hours: 1)),
          kinds: const [hs.HealthKind.respiratoryRate, hs.HealthKind.wristTemp],
        )
      : const <hs.HealthRecord>[];
  double? nightSpo2(({DateTime a, DateTime b})? n) {
    if (n == null) return null;
    final a = st.toTs(n.a), b = st.toTs(n.b);
    final v = [
      for (final x in spo2)
        if (x.ts >= a &&
            x.ts < b &&
            x.value > 0 &&
            (x.quality == null || x.quality! >= 40))
          x.value,
    ];
    // A night needs a few readings to say anything.
    return v.length < 5 ? null : v.reduce((p, q) => p + q) / v.length;
  }

  double? nightResp(({DateTime a, DateTime b})? n) =>
      n == null ? null : hs.nightRespiratoryRate(resp, n.a, n.b);
  double? nightTemp(({DateTime a, DateTime b})? n) =>
      n == null ? null : hs.nightTemperature(resp, n.a, n.b);

  return sc.bodySignals([
    sc.SignalInput(
      key: 'rhr',
      value: score?.rhr,
      history: [for (final s in past) ?s.rhr],
      higherIsWorse: true,
      minDelta: 3,
    ),
    if (health && (score?.hrv != null || past.any((s) => s.hrv != null)))
      sc.SignalInput(
        key: 'hrv',
        value: score?.hrv == null ? null : math.log(score!.hrv!),
        history: [
          for (final s in past)
            if (s.hrv != null && s.hrv! > 0 && s.hrvKind == hrvKind)
              math.log(s.hrv!),
        ],
        higherIsWorse: false,
        minDelta: math.log(1.15), // 15 % lower
      ),
    if (!health)
      sc.SignalInput(
        key: 'stress',
        value: score?.hrvProxy,
        history: [for (final s in past) ?s.hrvProxy],
        higherIsWorse: true,
        minDelta: 5,
      ),
    if (health)
      sc.SignalInput(
        key: 'resp',
        value: nightResp(spans.first),
        history: [for (final n in spans.skip(1)) ?nightResp(n)],
        higherIsWorse: true,
        minDelta: 1,
      ),
    sc.SignalInput(
      key: 'spo2',
      value: nightSpo2(spans.first),
      history: [for (final n in spans.skip(1)) ?nightSpo2(n)],
      higherIsWorse: false,
      minDelta: 1.5,
    ),
    if (health)
      sc.SignalInput(
        key: 'temp',
        value: nightTemp(spans.first),
        history: [for (final n in spans.skip(1)) ?nightTemp(n)],
        higherIsWorse: true,
        minDelta: .3,
      ),
  ]);
}

/// How far last night's breathing rate, SpO₂ and temperature sit the wrong
/// way from your normal (z, positive = worse), for the recovery penalty.
/// Resting HR and HRV are already in recovery, so they're left out here.
Future<List<double?>> nightVitalsZ(
  st.TempoDb db,
  DateTime day,
  ({DateTime a, DateTime b}) night,
) async {
  final s = await loadBodySignals(db, day: day, tonight: night);
  return [
    for (final r in s.readings)
      if (const {'resp', 'spo2', 'temp'}.contains(r.key)) r.z,
  ];
}

String signalName(String key) => switch (key) {
  'rhr' => 'Resting heart rate',
  'hrv' => 'HRV',
  'stress' => 'Overnight stress',
  'resp' => 'Breathing rate',
  'spo2' => 'Blood oxygen',
  'temp' => 'Night temperature',
  _ => key,
};

/// A signal value as shown: HRV comes in as ln(ms).
String signalValue(String key, double v) => switch (key) {
  'rhr' => '${v.round()} bpm',
  'hrv' => '${math.exp(v).round()} ms',
  'stress' => '${v.round()}',
  'resp' => '${v.toStringAsFixed(1)} /min',
  'spo2' => '${v.toStringAsFixed(1)} %',
  'temp' => '${v.toStringAsFixed(2)} °C',
  _ => v.toStringAsFixed(1),
};

// ---- Movement: brisk minutes and stillness ---------------------------------

final class Movement {
  const Movement({
    required this.brisk,
    required this.briskAvg,
    required this.still,
    required this.watchOnly,
  });

  /// Brisk minutes so far on the day.
  final int brisk;

  /// Mean brisk minutes over the 7 days before it (days with steps).
  final double? briskAvg;

  /// Longest still stretch while awake; null without heart rate.
  final sc.StillStretch? still;

  /// No heart rate at all on the day: stillness can't be judged.
  final bool watchOnly;
}

Future<Movement> loadMovement(st.TempoDb db, {DateTime? day}) async {
  final now = DateTime.now();
  final d = dayOf(day ?? now);
  final end = d.add(const Duration(days: 1));
  final source = await loadDataSource(db);
  final mins = (await loadMinutes(
    db,
    d,
    end.isAfter(now) ? now : end,
    source: source,
  )).minutes;
  final score = await db.scoreFor(d);
  final workouts = await db.workoutsBetween(d, end);
  // Only the waking day: from waking to now (or the end of the day).
  final wake = score?.sleepEnd == null ? d : st.fromTs(score!.sleepEnd!);
  final awake = [
    for (final m in mins)
      if (!m.ts.isBefore(wake)) m,
  ];
  final daily = <double>[];
  for (var i = 1; i <= 7; i++) {
    final a = d.subtract(Duration(days: i));
    final ms = (await loadMinutes(
      db,
      a,
      a.add(const Duration(days: 1)),
      source: source,
    )).minutes;
    if (ms.any((m) => m.steps > 0)) daily.add(sc.briskMinutes(ms).toDouble());
  }
  return Movement(
    brisk: sc.briskMinutes(mins),
    briskAvg: daily.length < 3
        ? null
        : daily.reduce((a, b) => a + b) / daily.length,
    still: sc.longestStill(
      awake,
      hrRest: score?.rhr ?? 60,
      busy: [for (final w in workouts) (st.fromTs(w.start), st.fromTs(w.end))],
    ),
    watchOnly: !mins.any((m) => m.hr != null),
  );
}

// ---- Heart-rate recovery after workouts ----------------------------------

/// Measured heart rate only, around [end]: band minutes as stored; Health
/// minutes only where a reading fell in that minute (interpolated ones
/// would invent the drop).
Future<List<sc.Minute>> _measuredAround(
  st.TempoDb db,
  DateTime end,
  DataSource source,
) async {
  final a = end.subtract(const Duration(minutes: 4));
  final b = end.add(const Duration(minutes: 4));
  if (!source.isHealth) {
    return [
      for (final r in await db.minutesBetween(a, b))
        sc.Minute(st.fromTs(r.ts), hr: r.hr),
    ];
  }
  return [
    for (final r in await db.healthMinutesBetween(a, b))
      sc.Minute(st.fromTs(r.ts), hr: r.hrMeasured ? r.hr : null),
  ];
}

/// Heart-rate drop in the 2 minutes after [w] ended, or null.
Future<int?> workoutRecovery(st.TempoDb db, st.Workout w, int hrMax) async {
  final source = await loadDataSource(db);
  final end = st.fromTs(w.end);
  return sc.recoveryDrop(
    await _measuredAround(db, end, source),
    end,
    hrMax: hrMax,
  );
}

/// Your usual recovery: the median drop over workouts in the last 60 days
/// before [before] (null under 3).
Future<double?> usualRecovery(
  st.TempoDb db,
  int hrMax, {
  required DateTime before,
}) async {
  final drops = <int>[];
  for (final w in await db.workoutsBetween(
    before.subtract(const Duration(days: 60)),
    before,
  )) {
    if (w.source == 'auto' && !w.confirmed) continue;
    final x = await workoutRecovery(db, w, hrMax);
    if (x != null) drops.add(x);
  }
  if (drops.length < 3) return null;
  drops.sort();
  final k = drops.length ~/ 2;
  return drops.length.isOdd
      ? drops[k].toDouble()
      : (drops[k - 1] + drops[k]) / 2;
}
