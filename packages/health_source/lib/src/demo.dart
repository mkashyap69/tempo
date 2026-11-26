import 'dart:math';

import 'record.dart';

/// Demo data (P7, docs/research/Pulse comparison.md §7): Health records for
/// a made-up person, so every screen can be seen without a watch (store
/// screenshots, design review, testing). Never mixed with real data: the
/// app only reads it into its own demo database.
///
/// The person: 34, male, 178 cm, a few runs and a strength session a week,
/// asleep around 23:00. Counting days back from the anchor day (0 = today):
///
/// * 56–70: a training block (a run or ride every day but Friday);
/// * 34–40: a cold (resting HR +7, HRV −30 %, breathing +1.6, SpO₂ −2,
///   temperature +0.6 °C, no workouts, long nights);
/// * 14–20: a short-sleep week (about 5 h 40 m a night);
/// * every 6th evening a drink ([demoAlcohol]): resting HR +5, HRV −20 %
///   that night;
/// * 0–11: getting fitter (HRV up to +12 %, resting HR −2).
///
/// Deterministic: the same day always gives the same records and ids, so a
/// re-read finds nothing new and nothing gone.
List<HealthRecord> demoRecords(
  HealthKind kind,
  DateTime from,
  DateTime to, {
  required DateTime anchor,
  bool apple = true,
}) {
  final now = anchor;
  final first = DateTime(from.year, from.month, from.day - 1);
  final out = <HealthRecord>[];
  for (
    var d = first;
    !d.isAfter(to);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    for (final r in _DemoDay(d, anchor, apple).records(kind)) {
      if (r.start.isBefore(from) || !r.start.isBefore(to)) continue;
      if (r.end.isAfter(now)) continue; // nothing from the future
      out.add(r);
    }
  }
  return out;
}

/// Days before [anchor]'s day (0 = that day).
int demoDaysBack(DateTime day, DateTime anchor) =>
    DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).difference(DateTime(day.year, day.month, day.day)).inHours ~/
    24;

/// The demo person had a drink on the evening of [day].
bool demoAlcohol(DateTime day, DateTime anchor) =>
    demoDaysBack(day, anchor) % 6 == 2;

/// The demo person was ill on [day] (the night ending that morning too).
bool demoIll(DateTime day, DateTime anchor) {
  final i = demoDaysBack(day, anchor);
  return i >= 34 && i <= 40;
}

const demoSourceApp = 'dev.tempo.demo';
const _demoName = 'Demo watch';

final class _DemoDay {
  _DemoDay(this.day, DateTime anchor, this.apple)
    : _anchor = anchor,
      back = demoDaysBack(day, anchor),
      rng = Random(day.year * 10000 + day.month * 100 + day.day),
      drinkLastNight = demoAlcohol(
        DateTime(day.year, day.month, day.day - 1),
        anchor,
      ) {
    ill = back >= 34 && back <= 40;
    training = back >= 56 && back <= 70;
    short = back >= 14 && back <= 20;
    weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    _plan();
  }

  final DateTime day;
  final DateTime _anchor;
  final bool apple;
  final int back;
  final Random rng;
  final bool drinkLastNight;
  late final bool ill, training, short, weekend;

  /// The night ending this morning.
  late DateTime bed, sleepStart, wake;
  late double rhr, hrv, resp, spo2, temp;
  final workouts = <(DateTime, DateTime, String, int)>[];
  final walks = <(DateTime, DateTime)>[];

  double _n(double sd) {
    // Sum of uniforms: close enough to normal for demo noise.
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      s += rng.nextDouble();
    }
    return (s - 2) * sd * 1.73;
  }

  DateTime _at(int minuteOfDay) => DateTime(
    day.year,
    day.month,
    day.day,
  ).add(Duration(minutes: minuteOfDay));

  void _plan() {
    // Weekend nights start an hour later and run longer.
    final bedMin = 23 * 60 + (weekend ? 50 : -5) + _n(20).round();
    final hours = ill
        ? 8.6
        : short
        ? 5.7
        : 7.3 + (weekend ? .6 : 0) + _n(.35);
    bed = _at(bedMin - 1440);
    sleepStart = bed.add(Duration(minutes: 8 + rng.nextInt(12)));
    wake = sleepStart.add(Duration(minutes: (hours * 60).round()));
    // The last 12 days: fitter after the block and the cold (HRV up, resting
    // HR down), so recent mornings run greener.
    final fit = back < 12 ? (12 - back) / 12 : 0.0;
    rhr =
        52 -
        2 * fit +
        (ill ? 7 : 0) +
        (drinkLastNight ? 5 : 0) +
        (training ? 2 : 0) +
        (short ? 2 : 0) +
        _n(1.2);
    hrv =
        (apple ? 58 : 46) *
            (ill ? .7 : 1) *
            (drinkLastNight ? .8 : 1) *
            (short ? .9 : 1) *
            (training ? .95 : 1) *
            (1 + .12 * fit) +
        _n(4);
    resp = 14.2 + (ill ? 1.6 : 0) + _n(.3);
    spo2 = 96.6 - (ill ? 2 : 0) + _n(.4);
    temp = (ill ? .6 : 0) + (drinkLastNight ? .2 : 0) + _n(.12);

    if (!ill) {
      final wd = day.weekday;
      void add(int startMin, int minutes, String type, int bpm) => workouts.add(
        (_at(startMin + rng.nextInt(20)), _at(startMin + minutes), type, bpm),
      );
      if (wd == DateTime.monday) {
        add(18 * 60, 50, 'TRADITIONAL_STRENGTH_TRAINING', 112);
      }
      if (wd == DateTime.tuesday) add(7 * 60, 40, 'RUNNING', 148);
      if (wd == DateTime.thursday) add(18 * 60, 45, 'RUNNING', 158);
      if (wd == DateTime.saturday) add(9 * 60, 75, 'RUNNING', 144);
      if (wd == DateTime.wednesday && !training) {
        add(18 * 60, 45, 'TRADITIONAL_STRENGTH_TRAINING', 110);
      }
      if (training) {
        if (wd == DateTime.wednesday) add(7 * 60, 50, 'RUNNING', 150);
        if (wd == DateTime.sunday) add(10 * 60, 90, 'BIKING', 138);
      }
    }
    for (final m in [8 * 60 + 20, 12 * 60 + 40, 17 * 60 + 30]) {
      final s = _at(m + rng.nextInt(25));
      walks.add((s, s.add(Duration(minutes: 12 + rng.nextInt(10)))));
    }
  }

  HealthRecord _r(
    HealthKind kind,
    int n,
    DateTime start,
    DateTime end,
    double value, {
    String? extra,
  }) => HealthRecord(
    uuid:
        'demo-${kind.name}-${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}-$n',
    kind: kind,
    start: start,
    end: end,
    value: value,
    sourceApp: demoSourceApp,
    sourceName: _demoName,
    extra: extra,
  );

  bool _inWorkout(DateTime t) =>
      workouts.any((w) => !t.isBefore(w.$1) && t.isBefore(w.$2));
  bool _inWalk(DateTime t) =>
      walks.any((w) => !t.isBefore(w.$1) && t.isBefore(w.$2));

  /// Desk stress on work days: a still stretch 10:00–11:30 a little up.
  bool _desk(DateTime t) =>
      !weekend && t.hour >= 10 && (t.hour < 11 || t.minute < 30);

  /// Sleep stages for the night: 90-minute cycles, deep early, REM late,
  /// a short wake now and then.
  List<(DateTime, DateTime, HealthKind)> _stages() {
    final out = <(DateTime, DateTime, HealthKind)>[];
    var t = sleepStart;
    var cycle = 0;
    while (t.isBefore(wake)) {
      final deep = max(0, 28 - cycle * 7) + rng.nextInt(6);
      final rem = 12 + cycle * 6 + rng.nextInt(6);
      final light = 90 - deep - rem;
      for (final (k, m) in [
        (HealthKind.sleepLight, light ~/ 2),
        (HealthKind.sleepDeep, deep),
        (HealthKind.sleepLight, light - light ~/ 2),
        (HealthKind.sleepRem, rem),
        if (rng.nextInt(3) == 0) (HealthKind.sleepAwake, 3 + rng.nextInt(5)),
      ]) {
        if (m <= 0 || !t.isBefore(wake)) continue;
        var e = t.add(Duration(minutes: m));
        if (e.isAfter(wake)) e = wake;
        out.add((t, e, k));
        t = e;
      }
      cycle++;
    }
    return out;
  }

  List<HealthRecord> records(HealthKind kind) {
    final mins = <HealthRecord>[];
    switch (kind) {
      case HealthKind.sleepInBed when apple:
        final out = wake.add(Duration(minutes: 6 + rng.nextInt(10)));
        return [
          _r(kind, 0, bed, out, out.difference(bed).inMinutes.toDouble()),
        ];
      case HealthKind.sleepSession when !apple:
        final out = wake.add(Duration(minutes: 6 + rng.nextInt(10)));
        return [
          _r(kind, 0, bed, out, out.difference(bed).inMinutes.toDouble()),
        ];
      case HealthKind.sleepLight ||
          HealthKind.sleepDeep ||
          HealthKind.sleepRem ||
          HealthKind.sleepAwake:
        var n = 0;
        for (final (a, b, k) in _stages()) {
          n++;
          if (k == kind) {
            mins.add(_r(kind, n, a, b, b.difference(a).inMinutes.toDouble()));
          }
        }
        return mins;
      case HealthKind.heartRate:
        var n = 0;
        final start = DateTime(day.year, day.month, day.day);
        // Last night's sleep this morning, and tonight's from its bed time.
        final tonight = _DemoDay(
          DateTime(day.year, day.month, day.day + 1),
          _anchor,
          apple,
        ).bed;
        for (var m = 0; m < 1440; m++) {
          final t = start.add(Duration(minutes: m));
          final asleep =
              (!t.isBefore(bed) && t.isBefore(wake)) || !t.isBefore(tonight);
          final workout = workouts
              .where((w) => !t.isBefore(w.$1) && t.isBefore(w.$2))
              .firstOrNull;
          // Minute samples in a workout, every 3 min awake, 5 asleep.
          final every = workout != null
              ? 1
              : asleep
              ? 5
              : 3;
          if (m % every != 0) continue;
          double bpm;
          if (workout != null) {
            final into = t.difference(workout.$1).inMinutes;
            final ramp = min(1.0, into / 8);
            bpm = 70 + (workout.$4 - 70) * ramp + _n(5);
          } else if (asleep) {
            bpm = rhr + 3 + _n(2);
          } else if (_inWalk(t)) {
            bpm = 96 + _n(5);
          } else {
            bpm =
                64 +
                (ill ? 8 : 0) +
                (short ? 3 : 0) +
                (_desk(t) ? 9 : 0) +
                _n(3);
          }
          n++;
          mins.add(_r(kind, n, t, t, bpm.roundToDouble()));
        }
        return mins;
      case HealthKind.steps:
        var n = 0;
        for (final w in walks) {
          for (
            var t = w.$1;
            t.isBefore(w.$2);
            t = t.add(const Duration(minutes: 5))
          ) {
            n++;
            final e = t.add(const Duration(minutes: 5));
            mins.add(_r(kind, n, t, e.isAfter(w.$2) ? w.$2 : e, 520));
          }
        }
        for (final w in workouts.where((w) => w.$3 == 'RUNNING')) {
          for (
            var t = w.$1;
            t.isBefore(w.$2);
            t = t.add(const Duration(minutes: 5))
          ) {
            n++;
            final e = t.add(const Duration(minutes: 5));
            mins.add(_r(kind, n, t, e.isAfter(w.$2) ? w.$2 : e, 840));
          }
        }
        // Pottering about: a few short bursts an hour while awake.
        for (var h = 8; h < 22; h++) {
          for (final m in [7, 31, 48]) {
            final t = _at(h * 60 + m);
            if (_inWorkout(t) || _inWalk(t) || _desk(t)) continue;
            if (rng.nextInt(3) == 0) continue;
            n++;
            mins.add(
              _r(
                kind,
                n,
                t,
                t.add(const Duration(minutes: 2)),
                40 + rng.nextInt(80).toDouble(),
              ),
            );
          }
        }
        return mins;
      case HealthKind.hrvSdnn when apple:
      case HealthKind.hrvRmssd when !apple:
        return [
          for (var i = 0; i < 4; i++)
            () {
              final t = sleepStart.add(Duration(minutes: 40 + i * 95));
              return _r(kind, i, t, t, max(10.0, hrv + _n(6)));
            }(),
        ];
      case HealthKind.restingHr:
        final t = _at(20 * 60);
        return [_r(kind, 0, t, t, (rhr + 4).roundToDouble())];
      case HealthKind.respiratoryRate:
        return [
          for (var i = 0; i < 3; i++)
            () {
              final t = sleepStart.add(Duration(minutes: 60 + i * 120));
              return _r(kind, i, t, t, resp + _n(.25));
            }(),
        ];
      case HealthKind.spo2:
        return [
          for (var i = 0; i < 8; i++)
            () {
              final t = sleepStart.add(Duration(minutes: 20 + i * 45));
              final v = min(100.0, spo2 + _n(.5));
              return _r(kind, i, t, t, apple ? v / 100 : v);
            }(),
        ];
      case HealthKind.wristTemp:
        return [_r(kind, 0, sleepStart, wake, (apple ? 34.6 : 0) + temp)];
      case HealthKind.workout:
        var n = 0;
        return [
          for (final w in workouts)
            _r(
              kind,
              n++,
              w.$1,
              w.$2,
              w.$2.difference(w.$1).inMinutes.toDouble(),
              extra: w.$3,
            ),
        ];
      case HealthKind.weight:
        final t = wake.add(const Duration(minutes: 15));
        final kg = 77.2 - back * -0.01 + _n(.3);
        return [_r(kind, 0, t, t, (kg * 10).round() / 10)];
      case HealthKind.bodyFat when day.weekday == DateTime.monday:
        final t = wake.add(const Duration(minutes: 16));
        final pct = 18.4 + _n(.4);
        return [_r(kind, 0, t, t, apple ? pct / 100 : pct)];
      default:
        return const [];
    }
  }
}

/// The kinds the demo writes for [apple] (Apple Health) or Health Connect.
Set<HealthKind> demoKinds({required bool apple}) => {
  HealthKind.heartRate,
  HealthKind.steps,
  apple ? HealthKind.sleepInBed : HealthKind.sleepSession,
  HealthKind.sleepLight,
  HealthKind.sleepDeep,
  HealthKind.sleepRem,
  HealthKind.sleepAwake,
  apple ? HealthKind.hrvSdnn : HealthKind.hrvRmssd,
  HealthKind.restingHr,
  HealthKind.respiratoryRate,
  HealthKind.spo2,
  HealthKind.wristTemp,
  HealthKind.workout,
  HealthKind.weight,
  HealthKind.bodyFat,
};
