import 'dart:math';

import 'baseline.dart';
import 'daily.dart';
import 'sleep.dart';

/// Tomorrow's recovery, estimated in the evening (P4,
/// docs/research/Pulse comparison.md §7).
///
/// It runs Tempo's own recovery formula on tomorrow morning with what is
/// already known tonight: today's load, the sleep you plan (hours from
/// bedtime to wake) and the nights before it. What isn't known yet is how
/// your heart will read (HRV or the band's overnight stress, its trend,
/// resting HR); for that part it takes your own last 30 mornings, so the
/// middle is a typical heart and the band is the middle 60 % of yours.
/// An estimate, never stored, never a score.
final class RecoveryForecast {
  const RecoveryForecast({
    required this.low,
    required this.mid,
    required this.high,
    required this.sleepHours,
    required this.hourLessCost,
    required this.mornings,
  });

  /// 20th, 50th and 80th percentile of the estimate, 0–100.
  final double low, mid, high;

  /// The sleep the estimate assumes, hours.
  final double sleepHours;

  /// Points [mid] would lose with an hour less sleep (≥ 0).
  final double hourLessCost;

  /// Earlier mornings the heart part was taken from.
  final int mornings;
}

/// Keys of the recovery parts that come from the heart overnight.
const _heartKeys = {'hrv', 'stress', 'trend', 'rhr'};

/// Mornings of history the heart part needs.
const forecastMinMornings = 7;

/// The estimate for the morning after [today], or null while recovery is
/// calibrating or with fewer than [forecastMinMornings] scored mornings.
///
/// [today] is today's row (its strain so far), [history] the days before
/// it, newest first, as [recoveryBreakdown] takes them. [sleepHours] is the
/// sleep planned tonight.
RecoveryForecast? recoveryForecast({
  required DailyScore today,
  required List<DailyScore> history,
  required double sleepHours,
  ScoringParams p = const ScoringParams(),
}) {
  if (today.calibrating || today.recovery == null) return null;
  final days = [today, ...history];
  // The heart part of each recent morning: Σ weight × z, unnormalised.
  final heart = <double>[];
  double heartWeight = 0;
  for (var i = 0; i < days.length && heart.length < 30; i++) {
    final d = days[i];
    if (d.calibrating || d.recovery == null || d.source != today.source) {
      continue;
    }
    final parts = recoveryBreakdown(d, days.sublist(i + 1), p: p);
    final h = parts.where((x) => _heartKeys.contains(x.key));
    if (h.isEmpty) continue;
    heart.add(h.fold<double>(0, (a, x) => a + x.weight * x.z));
    if (i == 0) heartWeight = h.fold<double>(0, (a, x) => a + x.weight);
  }
  if (heart.length < forecastMinMornings || heartWeight == 0) return null;

  double estimate(double hours, double heartSum) {
    final tomorrow = DateTime(
      today.date.year,
      today.date.month,
      today.date.day + 1,
    );
    final base = today.baseNeedHours ?? p.sleep.baseNeedHours;
    final normal = [
      for (final d
          in days.where((d) => d.source == today.source).take(p.baselineDays))
        if (d.vitalsPenalty <= 0) d,
    ];
    final parts = recoveryInputsFor(
      stress: null,
      hrvMs: null,
      rhr: null,
      sufficiency: sleepSufficiency(hours, base),
      normal: normal,
      baseHours: today.baseNeedHours,
      day: tomorrow,
      history: [
        for (final d in days)
          if (d.source == today.source) d,
      ],
      p: p,
    );
    var acc = heartSum, w = heartWeight;
    for (final x in parts) {
      if (_heartKeys.contains(x.key)) continue;
      final z = x.input.z;
      if (z == null) continue;
      acc += x.input.weight * z.clamp(-p.recovery.zCap, p.recovery.zCap);
      w += x.input.weight;
    }
    return 100 / (1 + exp(-p.recovery.slope * acc / w));
  }

  final hours = max(0.0, sleepHours);
  final q20 = quantile(heart, .2)!,
      q50 = quantile(heart, .5)!,
      q80 = quantile(heart, .8)!;
  final mid = estimate(hours, q50);
  return RecoveryForecast(
    low: estimate(hours, q20),
    mid: mid,
    high: estimate(hours, q80),
    sleepHours: hours,
    hourLessCost: max(0, mid - estimate(max(0, hours - 1), q50)),
    mornings: heart.length,
  );
}
