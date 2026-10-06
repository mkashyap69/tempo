import 'dart:math';

/// One minute of overnight SpO₂: average % and the band's confidence
/// (0–64, null when unknown).
typedef Spo2Point = ({DateTime ts, int avg, int? quality});

/// One oxygen-desaturation event and its drop in SpO₂ points.
typedef DropEvent = ({DateTime ts, int drop});

final class BreathingParams {
  const BreathingParams({
    this.minQuality = 40,
    this.minMinutes = 60,
    this.minDrop = 3,
    this.plateauDrop = 4,
    this.plateauMinutes = 8,
    this.plateauMaxSd = 2.5,
    this.plateauEdge = 3,
  });

  /// Minutes with lower confidence are left out (band quality 0–64).
  final int minQuality;

  /// Minutes of good SpO₂ a night needs before it gets a score.
  final int minMinutes;

  /// Drops smaller than this (SpO₂ points) don't count as events.
  final int minDrop;

  /// Flat low plateaus: at least [plateauMinutes] minutes ≥ [plateauDrop]
  /// points under the night's median, varying by at most [plateauMaxSd],
  /// read as a sensor or arm-position artifact rather than breathing.
  /// 6 Oct: 114 of 370 minutes sat in five such steps (84–89 % for 11–39
  /// min, abrupt edges, no heart-rate response) while the real dip
  /// clusters came at 94–96 %. Events within [plateauEdge] minutes of a
  /// plateau are the step itself and don't count. TODO(verify) against
  /// Mi Fitness for more nights.
  final int plateauDrop, plateauMinutes, plateauEdge;
  final double plateauMaxSd;
}

/// A night's breathing from the band's sleep SpO₂ and desaturation
/// events. A wellness signal, not a sleep-apnea test.
final class BreathingNight {
  const BreathingNight({
    required this.minutes,
    required this.avgSpo2,
    required this.lowestSpo2,
    required this.belowNinety,
    required this.events,
    required this.eventsPerHour,
    required this.score,
    this.artifactMinutes = 0,
  });

  /// Minutes left out as flat low plateaus (likely the band, not you).
  final int artifactMinutes;

  /// Minutes of good SpO₂ used.
  final int minutes;
  final double avgSpo2;
  final int lowestSpo2;

  /// Share of those minutes below 90 %.
  final double belowNinety;
  final int events;

  /// Desaturation events per hour asleep (an ODI-style rate).
  final double eventsPerHour;

  /// 0–100, higher is calmer breathing.
  final int score;

  /// Good from 90 (Mi Fitness's reference range is 90–100).
  String get label => score >= 90
      ? 'Good'
      : score >= 70
      ? 'Fair'
      : 'Poor';
}

/// Events/hour → 0–100. Under 5/h is the normal band (100–90, Mi
/// Fitness's "reference range 90–100"); above that it falls 3.5 a dip
/// through the mild band (5–15 → 90–55), then 15–30 → 55–35, then 1 a
/// dip to 0. Calibrated on one night where Mi Fitness scored 61 (11.6/h,
/// avg 94 %); to refine as more nights are compared.
double scoreForRate(double perHour) {
  final r = max(0.0, perHour);
  if (r <= 5) return 100 - 2 * r;
  if (r <= 15) return 90 - 3.5 * (r - 5);
  if (r <= 30) return 55 - (r - 15) * 4 / 3;
  return max(0, 35 - (r - 30));
}

/// Scores the sleep from [start] to [end] ([sleptHours] asleep). Null
/// when there are fewer than [BreathingParams.minMinutes] good minutes.
/// Score = rate score − 1.5 per % of time below 90 % − 2 per point the
/// average sits under 95 %, clamped 0–100.
BreathingNight? breathingNight({
  required DateTime start,
  required DateTime end,
  required double sleptHours,
  required List<Spo2Point> spo2,
  required List<DropEvent> events,
  BreathingParams p = const BreathingParams(),
}) {
  bool inside(DateTime t) => !t.isBefore(start) && !t.isAfter(end);
  final good = [
    for (final s in spo2)
      if (inside(s.ts) &&
          s.avg >= 70 &&
          s.avg <= 100 &&
          (s.quality == null || s.quality! >= p.minQuality))
        s,
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  if (good.isEmpty || sleptHours <= 0) return null;

  // Flat low plateaus → spans to leave out.
  final sorted = [for (final g in good) g.avg]..sort();
  final base = sorted[sorted.length ~/ 2];
  final spans = <(DateTime, DateTime)>[];
  var run = <Spo2Point>[];
  void closeRun() {
    if (run.length >= p.plateauMinutes) {
      // Judge the whole span, bumps included: mostly low and flat.
      final v = [
        for (final g in good)
          if (!g.ts.isBefore(run.first.ts) && !g.ts.isAfter(run.last.ts)) g.avg,
      ];
      if (run.length < .8 * v.length) {
        run = [];
        return;
      }
      final m = v.reduce((a, b) => a + b) / v.length;
      final sd = sqrt(
        v.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / v.length,
      );
      if (sd <= p.plateauMaxSd) {
        final edge = Duration(minutes: p.plateauEdge);
        spans.add((run.first.ts.subtract(edge), run.last.ts.add(edge)));
      }
    }
    run = [];
  }

  // Low minutes up to 3 min apart form one run (a brief bump back up
  // inside a plateau doesn't end it).
  for (final g in good) {
    if (g.avg > base - p.plateauDrop) continue;
    if (run.isNotEmpty && g.ts.difference(run.last.ts).inMinutes > 3) {
      closeRun();
    }
    run.add(g);
  }
  closeRun();
  bool artifact(DateTime t) =>
      spans.any((s) => !t.isBefore(s.$1) && !t.isAfter(s.$2));

  final kept = [
    for (final g in good)
      if (!artifact(g.ts)) g.avg,
  ];
  if (kept.length < p.minMinutes) return null;
  final n = [
    for (final e in events)
      if (inside(e.ts) && e.drop >= p.minDrop && !artifact(e.ts)) e,
  ].length;
  final rate = n / sleptHours;
  final below = kept.where((v) => v < 90).length / kept.length;
  final avg = kept.reduce((a, b) => a + b) / kept.length;
  final score = (scoreForRate(rate) - 150 * below - 2 * max(0.0, 95 - avg))
      .clamp(0, 100)
      .round();
  return BreathingNight(
    minutes: kept.length,
    avgSpo2: avg,
    lowestSpo2: kept.reduce(min),
    artifactMinutes: good.length - kept.length,
    belowNinety: below,
    events: n,
    eventsPerHour: rate,
    score: score,
  );
}
