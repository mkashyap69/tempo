import 'dart:math';

import 'package:scoring/scoring.dart';

import 'record.dart';

/// What a Health source said about sleep in one minute. Stored by name in
/// `health_minutes.sleep`, so never rename one.
enum SleepMark {
  /// Asleep with no stage: the source only said "asleep" (or only "in
  /// bed", for a phone without a watch).
  asleep,
  awake,
  light,
  deep,
  rem,
}

extension SleepMarkX on SleepMark {
  Stage get stage => switch (this) {
    SleepMark.awake => Stage.wake,
    SleepMark.deep => Stage.deep,
    SleepMark.rem => Stage.rem,
    // Unstaged sleep counts as light, as the band's own sleep flag does
    // before staging; the night is then shown as unstaged.
    SleepMark.light || SleepMark.asleep => Stage.light,
  };
}

final class GridParams {
  const GridParams({
    this.maxHrGapMinutes = 15,
    this.holdMinutes = 2,
    this.minBpm = 25,
    this.maxBpm = 230,
    this.maxStepsPerMinute = 300,
  });

  /// Heart rate is interpolated between readings up to this far apart.
  /// Apple Watch measures every ~4–10 min at rest and Health Connect
  /// writers vary, while strain sums every minute, so without filling an
  /// idle watch would under-count the day several times over. A longer gap
  /// means the watch was off or not measuring, and stays empty.
  final int maxHrGapMinutes;

  /// A reading with no neighbour in reach still covers this many minutes
  /// after it.
  final int holdMinutes;

  /// Readings outside this range are sensor glitches and dropped.
  final int minBpm, maxBpm;

  /// More steps than this in one minute is a bad record (cadence tops out
  /// near 220).
  final int maxStepsPerMinute;
}

/// One minute of Health data, ready for scoring.
final class HealthMinute {
  const HealthMinute(
    this.ts, {
    this.steps = 0,
    this.hr,
    this.hrMeasured = false,
    this.sleep,
    this.spo2,
  });

  final DateTime ts;
  final int steps;

  /// bpm: measured, or interpolated between readings ([hrMeasured] false).
  final int? hr;
  final bool hrMeasured;
  final SleepMark? sleep;
  final int? spo2;

  bool get hasData => hr != null || steps > 0 || sleep != null || spo2 != null;

  /// As scoring sees it. Health gives no movement intensity or worn flag:
  /// a minute with nothing at all counts as not worn, one with any data as
  /// awake unless the source said otherwise.
  Minute toMinute() => Minute(
    ts,
    hr: hr,
    steps: steps,
    stage:
        sleep?.stage ?? (hr != null || steps > 0 ? Stage.wake : Stage.unknown),
    offWrist: !hasData,
  );
}

final class _Span {
  const _Span(this.from, this.to, this.mark);
  final int from, to; // minute keys, [from, to)
  final SleepMark? mark; // null for containers
  bool overlaps(_Span o) => from < o.to && o.from < to;
}

/// Accumulates records (any order, any mix of apps) and answers per-minute
/// data for a range. Streaming, so a multi-GB export.xml never has to be
/// held as records.
///
/// Rules when apps overlap:
/// * **Heart rate**: readings in the same minute are averaged.
/// * **Steps**: each app's steps are spread over its records' minutes,
///   then the highest app wins each minute. iPhone and Watch both write
///   steps for the same walk; summing them would double it.
/// * **Sleep**: a stage beats "asleep", which beats "awake"; deep beats
///   REM beats light. In-bed and session records are containers: they mark
///   "asleep" only when no app wrote any stage inside them (a phone with
///   no watch), since the minutes around a watch's stages are time awake
///   in bed.
class HealthGrid {
  HealthGrid([this.p = const GridParams()]);
  final GridParams p;

  final _hrSum = <int, double>{};
  final _hrN = <int, int>{};
  final _steps = <int, Map<String, double>>{};
  final _spo2Sum = <int, double>{};
  final _spo2N = <int, int>{};
  final _stages = <_Span>[];
  final _containers = <_Span>[];
  List<int>? _hrKeys;
  int? _first, _last;

  static int key(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;
  static DateTime at(int k) => DateTime.fromMillisecondsSinceEpoch(k * 60000);

  void _seen(int k) {
    if (_first == null || k < _first!) _first = k;
    if (_last == null || k > _last!) _last = k;
  }

  /// First and last minute with any data, if any.
  DateTime? get first => _first == null ? null : at(_first!);
  DateTime? get last => _last == null ? null : at(_last!);

  /// Minute span of [r]: every minute it touches, at least one.
  (int, int) _span(HealthRecord r) {
    final a = key(r.start);
    final endMs = r.end.millisecondsSinceEpoch;
    var b = (endMs + 59999) ~/ 60000; // ceil
    if (b <= a) b = a + 1;
    return (a, b);
  }

  void add(HealthRecord r) {
    if (r.fromTempo) return;
    if (r.end.isBefore(r.start)) return;
    switch (r.kind) {
      case HealthKind.heartRate:
        final v = r.value;
        if (v.isNaN || v < p.minBpm || v > p.maxBpm) return;
        final k = key(r.start);
        _hrSum[k] = (_hrSum[k] ?? 0) + v;
        _hrN[k] = (_hrN[k] ?? 0) + 1;
        _hrKeys = null;
        _seen(k);
      case HealthKind.steps:
        _addSteps(r);
      case HealthKind.spo2:
        final v = normalizeSpo2(r.value);
        if (v == null) return;
        final k = key(r.start);
        _spo2Sum[k] = (_spo2Sum[k] ?? 0) + v;
        _spo2N[k] = (_spo2N[k] ?? 0) + 1;
        _seen(k);
      case HealthKind.sleepInBed || HealthKind.sleepSession:
        final (a, b) = _span(r);
        _containers.add(_Span(a, b, null));
        _seen(a);
        _seen(b - 1);
      case HealthKind.sleepAsleep:
        _stage(r, SleepMark.asleep);
      case HealthKind.sleepAwake:
        _stage(r, SleepMark.awake);
      case HealthKind.sleepLight:
        _stage(r, SleepMark.light);
      case HealthKind.sleepDeep:
        _stage(r, SleepMark.deep);
      case HealthKind.sleepRem:
        _stage(r, SleepMark.rem);
      case HealthKind.hrvSdnn ||
          HealthKind.hrvRmssd ||
          HealthKind.restingHr ||
          HealthKind.workout:
        break; // read per night / per day, see vitals.dart, workouts.dart
    }
  }

  void addAll(Iterable<HealthRecord> rs) {
    for (final r in rs) {
      add(r);
    }
  }

  void _stage(HealthRecord r, SleepMark m) {
    final (a, b) = _span(r);
    // A record shorter than a minute still marks its minute, but must not
    // spill into the next one.
    final endKey = r.end.millisecondsSinceEpoch ~/ 60000;
    final to = endKey > a ? endKey : b;
    _stages.add(_Span(a, to, m));
    _seen(a);
    _seen(to - 1);
  }

  void _addSteps(HealthRecord r) {
    final v = r.value;
    if (v.isNaN || v <= 0) return;
    final src = r.sourceApp;
    final s = r.start.millisecondsSinceEpoch, e = r.end.millisecondsSinceEpoch;
    void put(int k, double x) {
      final m = _steps.putIfAbsent(k, () => {});
      m[src] = (m[src] ?? 0) + x;
      _seen(k);
    }

    if (e - s < 60000) {
      put(key(r.start), v);
      return;
    }
    final dur = (e - s).toDouble();
    for (var k = s ~/ 60000; k * 60000 < e; k++) {
      final a = max(s, k * 60000), b = min(e, (k + 1) * 60000);
      if (b > a) put(k, v * (b - a) / dur);
    }
  }

  int _stepsAt(int k) {
    final m = _steps[k];
    if (m == null || m.isEmpty) return 0;
    final best = m.values.reduce(max);
    return min(best.round(), p.maxStepsPerMinute);
  }

  /// Sleep mark per minute in [a, b).
  Map<int, SleepMark> _sleep(int a, int b) {
    final out = <int, SleepMark>{};
    final range = _Span(a, b, null);
    for (final s in _stages) {
      if (!s.overlaps(range)) continue;
      for (var k = max(s.from, a); k < min(s.to, b); k++) {
        final cur = out[k];
        if (cur == null || _rank(s.mark!) > _rank(cur)) out[k] = s.mark!;
      }
    }
    for (final c in _containers) {
      if (!c.overlaps(range)) continue;
      if (_stages.any(c.overlaps)) continue;
      for (var k = max(c.from, a); k < min(c.to, b); k++) {
        out[k] ??= SleepMark.asleep;
      }
    }
    return out;
  }

  static int _rank(SleepMark m) => switch (m) {
    SleepMark.awake => 0,
    SleepMark.asleep => 1,
    SleepMark.light => 2,
    SleepMark.rem => 3,
    SleepMark.deep => 4,
  };

  /// Every minute in [from, to), oldest first, empty minutes included.
  List<HealthMinute> minutes(DateTime from, DateTime to) {
    final a = key(from), b = key(to);
    if (b <= a) return const [];
    final keys = _hrKeys ??= (_hrN.keys.toList()..sort());
    // Readings in reach of the range, for interpolation at its edges.
    var i = _lowerBound(keys, a - p.maxHrGapMinutes);
    final sleep = _sleep(a, b);
    final out = <HealthMinute>[];
    for (var k = a; k < b; k++) {
      while (i < keys.length && keys[i] <= k) {
        i++;
      }
      // keys[i-1] <= k < keys[i]
      final prev = i > 0 ? keys[i - 1] : null;
      final next = i < keys.length ? keys[i] : null;
      int? hr;
      var measured = false;
      if (prev == k) {
        hr = (_hrSum[k]! / _hrN[k]!).round();
        measured = true;
      } else if (prev != null && k - prev <= p.maxHrGapMinutes) {
        final pv = _hrSum[prev]! / _hrN[prev]!;
        if (next != null && next - prev <= p.maxHrGapMinutes) {
          final nv = _hrSum[next]! / _hrN[next]!;
          hr = (pv + (nv - pv) * (k - prev) / (next - prev)).round();
        } else if (k - prev <= p.holdMinutes) {
          hr = pv.round();
        }
      }
      final n = _spo2N[k];
      out.add(
        HealthMinute(
          at(k),
          steps: _stepsAt(k),
          hr: hr,
          hrMeasured: measured,
          sleep: sleep[k],
          spo2: n == null ? null : (_spo2Sum[k]! / n).round(),
        ),
      );
    }
    return out;
  }

  static int _lowerBound(List<int> xs, int v) {
    var lo = 0, hi = xs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// SpO₂ in percent: iOS stores a fraction (0.97), Health Connect a percent
/// (97). Null outside 50–100 %.
int? normalizeSpo2(double v) {
  if (v.isNaN) return null;
  final pct = v <= 1.0 ? v * 100 : v;
  if (pct < 50 || pct > 100) return null;
  return pct.round();
}

/// [minutes] as scoring sees them, and whether any sleep in them came with
/// no stages (the night is then shown as unstaged, as for a band night
/// with too little heart rate).
({List<Minute> minutes, bool unstaged}) scoringMinutes(
  List<HealthMinute> minutes,
) {
  var staged = false, unstagedSleep = false;
  for (final m in minutes) {
    switch (m.sleep) {
      case SleepMark.light || SleepMark.deep || SleepMark.rem:
        staged = true;
      case SleepMark.asleep:
        unstagedSleep = true;
      case SleepMark.awake || null:
        break;
    }
  }
  return (
    minutes: [for (final m in minutes) m.toMinute()],
    unstaged: unstagedSleep && !staged,
  );
}
