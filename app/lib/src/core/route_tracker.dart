/// Distance and pace for a live walk or run, from phone GPS fixes or the
/// band's own distance counter. Pure Dart: the location plugin feeds it
/// (core/location_feed.dart) and LiveSession reads it each tick.
///
/// TODO(verify) every threshold here on a real outdoor run on both phones:
/// the accuracy cut, the jitter floor and the speed cap.
library;

import 'dart:math' as math;

/// One GPS fix.
class GeoFix {
  const GeoFix(
    this.lat,
    this.lon, {
    required this.accuracyM,
    required this.at,
    this.altitudeM,
    this.altitudeAccuracyM,
  });
  final double lat, lon;

  /// Horizontal accuracy radius, metres.
  final double accuracyM;
  final DateTime at;

  /// Height above sea level and its accuracy, metres; null when unknown.
  final double? altitudeM, altitudeAccuracyM;
}

/// A point of the drawn route in metres east and north of the start; null
/// marks a break (a pause or a GPS jump) so the line isn't joined across it.
typedef RoutePoint = ({double x, double y});

/// Great-circle distance in metres (haversine, mean Earth radius).
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Where a session's distance comes from.
enum DistanceSource { gps, band }

/// Distance against moving time, plus the pace over the last stretch and
/// one split per km (or mile).
class RouteTracker {
  RouteTracker({this.splitM = 1000});

  /// Split length: 1000 m, or 1609.344 m for miles.
  final double splitM;

  /// Fixes worse than this are skipped.
  static const maxAccuracyM = 30.0;

  /// Faster than this between two fixes is a GPS jump, not a run.
  static const maxSpeedMs = 10.0;

  /// The window for "pace now".
  static const paceWindowS = 60;

  double _m = 0;
  GeoFix? _last;

  /// Climbs of at least this much count toward [elevationGainM], so GPS
  /// altitude noise doesn't add up.
  static const climbStepM = 3.0;

  /// Fixes whose altitude is worse than this don't count toward the gain.
  static const maxAltitudeAccuracyM = 15.0;

  /// The most points kept for drawing; past it every other one is dropped.
  static const maxPathPoints = 1500;

  double _gain = 0;
  double? _altAnchor;
  double? _accuracy;
  GeoFix? _origin;
  final _path = <RoutePoint?>[];

  /// Metres climbed, from GPS altitude. TODO(verify) against a known hill.
  double get elevationGainM => _gain;

  /// The latest fix's horizontal accuracy, metres.
  double? get accuracyM => _accuracy;

  /// The route so far, for drawing only; kept in memory, never stored.
  List<RoutePoint?> get path => List.unmodifiable(_path);

  /// (moving seconds, metres) samples, the last few minutes only.
  final _trail = <(double, double)>[];

  /// Moving seconds at each split.
  final _splitAt = <double>[];

  double get meters => _m;

  /// Seconds each completed split took.
  List<double> get splits => [
    for (var i = 0; i < _splitAt.length; i++)
      _splitAt[i] - (i == 0 ? 0 : _splitAt[i - 1]),
  ];

  /// After a pause: the next fix starts a new leg, so ground covered while
  /// paused isn't counted.
  void breakLeg() {
    _last = null;
    if (_path.isNotEmpty && _path.last != null) _path.add(null);
  }

  /// A GPS fix at [movingS] seconds of moving time. Returns true when it
  /// was used.
  bool addFix(GeoFix f, double movingS) {
    if (f.accuracyM <= 0) return false;
    _accuracy = f.accuracyM;
    if (f.accuracyM > maxAccuracyM) return false;
    final last = _last;
    if (last == null) {
      _last = f;
      _point(f);
      _climb(f);
      _mark(movingS);
      return true;
    }
    final d = haversineM(last.lat, last.lon, f.lat, f.lon);
    final dt = f.at.difference(last.at).inMilliseconds / 1000;
    // Standing still: fixes wander inside their accuracy circle. Wait for
    // a move bigger than that before counting it.
    // The legs stay measured from the last counted fix, so a high floor
    // delays distance a little but loses none of it on a straight line.
    final floor = math.max(
      3.0,
      math.min(20.0, (last.accuracyM + f.accuracyM) / 2),
    );
    if (d < floor) return false;
    if (dt > 0 && d / dt > maxSpeedMs) {
      // A jump: start again from here rather than add it.
      _last = f;
      if (_path.isNotEmpty && _path.last != null) _path.add(null);
      _point(f);
      return false;
    }
    _last = f;
    _point(f);
    _climb(f);
    _add(d, movingS);
    return true;
  }

  /// Metres east and north of the first fix (equirectangular: plenty for
  /// a few km).
  void _point(GeoFix f) {
    final o = _origin ??= f;
    const mPerDeg = 111195.0;
    _path.add((
      x: (f.lon - o.lon) * mPerDeg * math.cos(o.lat * math.pi / 180),
      y: (f.lat - o.lat) * mPerDeg,
    ));
    if (_path.length > maxPathPoints) {
      // Halve, keeping breaks and the latest point.
      final kept = <RoutePoint?>[];
      for (var i = 0; i < _path.length; i++) {
        final p = _path[i];
        if (p == null || i.isEven || i == _path.length - 1) kept.add(p);
      }
      _path
        ..clear()
        ..addAll(kept);
    }
  }

  void _climb(GeoFix f) {
    final alt = f.altitudeM;
    final acc = f.altitudeAccuracyM;
    if (alt == null ||
        (acc != null && (acc <= 0 || acc > maxAltitudeAccuracyM))) {
      return;
    }
    // Hysteresis both ways: a rise of a step counts, a fall of a step
    // moves the base down; wobble inside the band does neither.
    final a = _altAnchor;
    if (a == null || alt <= a - climbStepM) {
      _altAnchor = alt;
    } else if (alt >= a + climbStepM) {
      _gain += alt - a;
      _altAnchor = alt;
    }
  }

  /// The band's running distance total, metres since the start.
  void setTotal(double metres, double movingS) {
    if (metres <= _m) {
      _mark(movingS);
      return;
    }
    _add(metres - _m, movingS);
  }

  void _add(double d, double movingS) {
    final before = _m;
    _m += d;
    // Split crossings, placed by interpolating inside this leg.
    final prevT = _trail.isEmpty ? movingS : _trail.last.$1;
    var k = (before / splitM).floor() + 1;
    while (k * splitM <= _m) {
      final frac = (k * splitM - before) / d;
      _splitAt.add(prevT + (movingS - prevT) * frac);
      k++;
    }
    _mark(movingS);
  }

  void _mark(double movingS) {
    _trail.add((movingS, _m));
    final cut = movingS - 10 * 60;
    while (_trail.length > 2 && _trail.first.$1 < cut) {
      _trail.removeAt(0);
    }
  }

  /// Seconds per km over the last [paceWindowS] (at least [minWindowS] of
  /// samples, and 15 m covered), or null while standing or too early.
  double? paceNow(
    double movingS, {
    int window = paceWindowS,
    int minWindowS = 20,
  }) {
    if (_trail.isEmpty) return null;
    final from = movingS - window;
    (double, double)? a;
    for (final p in _trail) {
      if (p.$1 >= from) {
        a = p;
        break;
      }
    }
    // The sample just before the window, so the window is full width.
    final i = a == null ? -1 : _trail.indexOf(a);
    if (i > 0) a = _trail[i - 1];
    a ??= _trail.last;
    final dt = movingS - a.$1, dm = _m - a.$2;
    if (dt < minWindowS || dm < 15) return null;
    final p = dt / dm * 1000;
    // Slower than 30 min/km is standing about, not a pace.
    return p > 1800 ? null : p;
  }

  /// Seconds per km over the whole session's moving time.
  double? paceAvg(double movingS) =>
      _m < 50 || movingS <= 0 ? null : movingS / _m * 1000;
}
