/// Running paces from a race (U5): Daniels & Gilbert's VDOT (1979, as used
/// in Daniels' Running Formula). A recent race or time trial gives VDOT;
/// each heart-rate zone gets the pace range of its training intensity, and
/// any race distance gets an equivalent time. Heart rate stays the guide:
/// paces are for flat ground on a mild day. Pure Dart.
library;

import 'dart:math';

import 'block.dart' show BlockGoal;
import 'coach.dart';

/// Oxygen cost of running at [v] metres a minute (ml/kg/min).
double vo2AtSpeed(double v) => -4.60 + .182258 * v + .000104 * v * v;

/// Speed (m/min) whose oxygen cost is [vo2]: the quadratic above solved.
double speedAtVo2(double vo2) {
  const a = .000104, b = .182258;
  final c = -4.60 - vo2;
  return (-b + sqrt(b * b - 4 * a * c)) / (2 * a);
}

/// Share of VO₂max that can be held for [minutes].
double fractionForDuration(double minutes) =>
    .8 +
    .1894393 * exp(-.012778 * minutes) +
    .2989558 * exp(-.1932605 * minutes);

/// VDOT from a race of [metres] in [seconds].
double vdotFromRace(double metres, double seconds) {
  final t = seconds / 60;
  return vo2AtSpeed(metres / t) / fractionForDuration(t);
}

/// Equivalent time (seconds) over [metres] at [vdot], by bisection.
double raceSeconds(double vdot, double metres) {
  var lo = 60.0, hi = 60.0 * 60 * 10;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (vdotFromRace(metres, mid) > vdot) {
      lo = mid; // too fast for this VDOT
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// A pace range, seconds per km: [slow] is the easy end.
typedef PaceRange = ({double slow, double fast});

/// Seconds per km at [pct] of [vdot].
double _secPerKm(double vdot, double pct) => 60000 / speedAtVo2(vdot * pct);

/// Pace range for heart-rate zone [zone] (1–5) at [vdot], from Daniels'
/// intensities: Z1 recovery (under easy), Z2 easy 62–70 % (the fast end
/// is the tables' E pace), Z3 marathon 75–84 %, Z4 threshold 83–88 %, Z5
/// interval 95–100 % of VDOT. TODO(verify) against runners' own paces.
PaceRange zonePace(int zone, double vdot) {
  final (lo, hi) = switch (zone.clamp(1, 5)) {
    1 => (.52, .62),
    2 => (.62, .70),
    3 => (.75, .84),
    4 => (.83, .88),
    _ => (.95, 1.0),
  };
  return (slow: _secPerKm(vdot, lo), fast: _secPerKm(vdot, hi));
}

/// Distance (km) of [minutes] at the middle of zone [zone]'s pace range.
double kmFor(int minutes, int zone, double vdot) {
  final p = zonePace(zone, vdot);
  return minutes * 60 / ((p.slow + p.fast) / 2);
}

/// "5:12" for seconds per km (or per mile when [miles]).
String paceText(double secPerKm, {bool miles = false}) {
  final s = (miles ? secPerKm * 1.609344 : secPerKm).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "3:28:40" or "24:05".
String durationText(double seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${r.toString().padLeft(2, '0')}';
}

/// Race distances in metres.
const raceMetres = {
  '5K': 5000.0,
  '10K': 10000.0,
  'Half marathon': 21097.5,
  'Marathon': 42195.0,
};

/// Race distance of a goal, metres; null for an open-ended goal.
double? goalMetres(BlockGoal g) => switch (g) {
  BlockGoal.run5k => 5000,
  BlockGoal.run10k => 10000,
  BlockGoal.half => 21097.5,
  BlockGoal.marathon => 42195,
  BlockGoal.open => null,
};

/// "Z2 5:38–5:07 · Z4 4:25–4:15 /km" for a run's zones, slowest first;
/// a long run adds "· about 18 km". Null for anything but running.
String? sessionPaces(Session s, double vdot, {bool miles = false}) {
  if (s.sport != Sport.running || s.segments.isEmpty) return null;
  final zones = {for (final g in s.segments) g.zone}.toList()..sort();
  final unit = miles ? '/mi' : '/km';
  final parts = [
    for (final z in zones)
      () {
        final p = zonePace(z, vdot);
        return 'Z$z ${paceText(p.slow, miles: miles)}–${paceText(p.fast, miles: miles)}';
      }(),
  ];
  var line = '${parts.join(' · ')} $unit';
  if (s.key.startsWith('long_') || s.key == 'race') {
    final km = s.segments.fold<double>(
      0,
      (a, g) => a + kmFor(g.minutes, g.zone, vdot),
    );
    final d = miles ? km / 1.609344 : km;
    line += ' · about ${d.round()} ${miles ? 'mi' : 'km'}';
  }
  return line;
}
