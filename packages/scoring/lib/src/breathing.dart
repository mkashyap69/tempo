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
  });

  /// Minutes with lower confidence are left out (band quality 0–64).
  final int minQuality;

  /// Minutes of good SpO₂ a night needs before it gets a score.
  final int minMinutes;

  /// Drops smaller than this (SpO₂ points) don't count as events.
  final int minDrop;
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
  });

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

  String get label => score >= 85
      ? 'Good'
      : score >= 70
      ? 'Fair'
      : 'Disturbed';
}

/// Events/hour → 0–100, anchored on the usual ODI bands: under 5 normal
/// (100–90), 5–15 mild (90–70), 15–30 moderate (70–50), above 30 severe.
double scoreForRate(double perHour) {
  final r = max(0.0, perHour);
  if (r <= 5) return 100 - 2 * r;
  if (r <= 15) return 90 - 2 * (r - 5);
  if (r <= 30) return 70 - (r - 15) * 4 / 3;
  return max(0, 50 - (r - 30));
}

/// Scores the sleep from [start] to [end] ([sleptHours] asleep). Null
/// when there are fewer than [BreathingParams.minMinutes] good minutes.
/// Score = rate score − 1.5 per % of time below 90 %, clamped 0–100.
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
        s.avg,
  ];
  if (good.length < p.minMinutes || sleptHours <= 0) return null;
  final n = [
    for (final e in events)
      if (inside(e.ts) && e.drop >= p.minDrop) e,
  ].length;
  final rate = n / sleptHours;
  final below = good.where((v) => v < 90).length / good.length;
  final score = (scoreForRate(rate) - 150 * below).clamp(0, 100).round();
  return BreathingNight(
    minutes: good.length,
    avgSpo2: good.reduce((a, b) => a + b) / good.length,
    lowestSpo2: good.reduce(min),
    belowNinety: below,
    events: n,
    eventsPerHour: rate,
    score: score,
  );
}
