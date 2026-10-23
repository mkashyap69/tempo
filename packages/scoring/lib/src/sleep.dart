import 'dart:math';

import 'types.dart';

final class SleepSession {
  SleepSession(this.minutes);

  /// Every minute from first asleep to last asleep, wake gaps included.
  final List<Minute> minutes;

  DateTime get start => minutes.first.ts;
  DateTime get end => minutes.last.ts.add(const Duration(minutes: 1));
  Duration get inBed => end.difference(start);

  int _count(bool Function(Stage) f) => minutes.where((m) => f(m.stage)).length;
  Duration get asleep => Duration(minutes: _count((s) => s.asleep));
  Duration stage(Stage s) => Duration(minutes: _count((x) => x == s));
  double get efficiency =>
      inBed.inMinutes == 0 ? 0 : asleep.inMinutes / inBed.inMinutes;
}

final class SleepParams {
  const SleepParams({
    this.baseNeedHours = 7.5,
    this.debtFactor = 0.5,
    this.strainFactor = 0.01,
    this.debtCapHours = 2,
    this.debtHalfLifeNights = 4,
    this.repayRate = 0.5,
    this.debtNights = 14,
    this.maxWakeGapMinutes = 30,
    this.maxQuietGapMinutes = 90,
    this.quietGapMaxSteps = 30,
    this.minSessionMinutes = 60,
    this.minNapMinutes = 20,
    this.learnNights = 14,
    this.minNeedHours = 7,
    this.maxNeedHours = 9,
  });
  final double baseNeedHours;
  final double debtFactor;

  /// Hours of extra need per point of yesterday's strain. Hard exercise
  /// adds only ~10 min of sleep in meta-analyses (Kredlow 2015), so a
  /// strain-21 day adds ~13 min (algo 10; was 0.03 → 38 min).
  final double strainFactor;
  final double debtCapHours;

  /// Debt fades by half over this many nights (Kitamura 2016: ~4 days of
  /// extra sleep to repay an hour), so a short week stops counting after
  /// two or three.
  final double debtHalfLifeNights;

  /// Share of a night's surplus over the base need that pays debt back
  /// (repayment is partial: Kitamura 2016, Belenky 2003).
  final double repayRate;

  /// Nights of history the debt looks back over.
  final int debtNights;
  final int maxWakeGapMinutes;

  /// A longer wake still belongs to the same sleep when it's quiet: up to
  /// [maxQuietGapMinutes] with at most [quietGapMaxSteps] steps (lying
  /// awake). Seen 6 Oct: 31 min awake at 05:28 with 0 steps split a
  /// 7 h 22 m night into 5 h + a "nap". The band must be worn the whole
  /// gap: on 6 Oct a 34-min gap with 17 min off the wrist joined a 5-min
  /// "sleep" after putting the band back on and moved wake 38 min later.
  final int maxQuietGapMinutes, quietGapMaxSteps;
  final int minSessionMinutes;

  /// Daytime sleep at least this long counts as a nap.
  final int minNapMinutes;

  /// Nights with an autonomic recovery needed before the base need is
  /// learned.
  final int learnNights;

  /// The learned base need stays within the adult consensus of 7–9 h
  /// (Hirshkowitz 2015; Watson 2015).
  final double minNeedHours, maxNeedHours;
}

/// Splits minutes (sorted, one per minute) into sleep sessions. Runs of
/// sleep separated by wake/unknown gaps up to `maxWakeGapMinutes` merge.
List<SleepSession> detectSessions(
  List<Minute> minutes, [
  SleepParams p = const SleepParams(),
]) {
  // Runs of asleep minutes: [first, last] indices.
  final runs = <(int, int)>[];
  for (var i = 0; i < minutes.length; i++) {
    if (!minutes[i].stage.asleep) continue;
    if (runs.isNotEmpty) {
      final (a, b) = runs.last;
      if (minutes[i].ts.difference(minutes[b].ts).inMinutes <= 1) {
        runs[runs.length - 1] = (a, i);
        continue;
      }
    }
    runs.add((i, i));
  }
  // Merge across short wakes, or longer quiet ones.
  final merged = <(int, int)>[];
  for (final r in runs) {
    if (merged.isNotEmpty) {
      final (a, b) = merged.last;
      final gap = minutes[r.$1].ts.difference(minutes[b].ts).inMinutes;
      var steps = 0;
      var offWrist = false;
      for (var k = b + 1; k < r.$1; k++) {
        steps += minutes[k].steps;
        offWrist |= minutes[k].offWrist;
      }
      if (gap <= p.maxWakeGapMinutes ||
          (gap <= p.maxQuietGapMinutes &&
              steps <= p.quietGapMaxSteps &&
              !offWrist)) {
        merged[merged.length - 1] = (a, r.$2);
        continue;
      }
    }
    merged.add(r);
  }
  return [
    for (final (a, b) in merged)
      if (SleepSession(minutes.sublist(a, b + 1)).asleep.inMinutes >=
          p.minSessionMinutes)
        SleepSession(minutes.sublist(a, b + 1)),
  ];
}

/// One past night for the debt calculation: what you slept (naps
/// included) against your *base* need that night.
final class NightRecord {
  const NightRecord({required this.baseHours, required this.sleptHours});
  final double baseHours;
  final double sleptHours;
}

/// Sleep debt in hours, from up to [SleepParams.debtNights] nights,
/// **newest first**. A running balance against the base need: each night
/// the balance fades by [SleepParams.debtHalfLifeNights], a shortfall adds
/// to it and a surplus pays [SleepParams.repayRate] of itself back. Capped
/// at [SleepParams.debtCapHours].
///
/// Algo 10: debt was a 7-night sum against each night's stored need, which
/// already held debt, so once at the cap a normal night kept it there
/// (docs/research/Algorithm review.md, loop L1).
double sleepDebtHours(
  List<NightRecord> nights, [
  SleepParams p = const SleepParams(),
]) {
  final fade = pow(.5, 1 / p.debtHalfLifeNights).toDouble();
  var debt = 0.0;
  for (final n in nights.take(p.debtNights).toList().reversed) {
    final short = n.baseHours - n.sleptHours;
    debt = debt * fade + (short > 0 ? short : p.repayRate * short);
    debt = debt.clamp(0, p.debtCapHours).toDouble();
  }
  return debt;
}

/// One night for learning the base need: hours slept, and the next
/// morning's autonomic recovery (HRV and resting HR only, never sleep
/// length; see [autonomicScores]).
final class NeedSample {
  const NeedSample({required this.sleptHours, required this.autonomic});
  final double sleptHours;
  final double autonomic;
}

/// Your base need: the median sleep on the third of nights after which
/// HRV and resting HR were best, clamped to
/// [SleepParams.minNeedHours]–[SleepParams.maxNeedHours]. Falls back to
/// [SleepParams.baseNeedHours] with fewer than [SleepParams.learnNights]
/// nights.
///
/// Algo 10: ranked by autonomic recovery instead of Recovery, which holds
/// sleep performance and so picked the longest nights (loop L2).
double learnedBaseNeed(
  List<NeedSample> nights, [
  SleepParams p = const SleepParams(),
]) {
  if (nights.length < p.learnNights) {
    return p.baseNeedHours.clamp(p.minNeedHours, p.maxNeedHours).toDouble();
  }
  final ranked = [...nights]
    ..sort((a, b) => b.autonomic.compareTo(a.autonomic));
  final top = [
    for (final n in ranked.take((nights.length / 3).ceil())) n.sleptHours,
  ]..sort();
  final mid = top.length ~/ 2;
  final median = top.length.isOdd ? top[mid] : (top[mid - 1] + top[mid]) / 2;
  return median.clamp(p.minNeedHours, p.maxNeedHours).toDouble();
}

double sleepNeedHours({
  required double debtHours,
  required double strainYesterday,
  SleepParams p = const SleepParams(),
  double? baseHours,
}) =>
    (baseHours ?? p.baseNeedHours) +
    p.debtFactor * debtHours +
    p.strainFactor * strainYesterday;

/// 0–100, capped: share of tonight's need (debt and strain included).
/// Shown as "% of need"; the score and Recovery use [sleepSufficiency].
double sleepPerformance(double sleptHours, double needHours) =>
    needHours <= 0 ? 100 : (100 * sleptHours / needHours).clamp(0, 100);

/// Sleep against your base need, 0–[cap] (algo 10). Uncapped above 100 up
/// to [cap] so a long night after a short one still reads as more, and
/// free of debt so a short week doesn't lower every later night (L1, L3).
double sleepSufficiency(
  double sleptHours,
  double baseHours, {
  double cap = 120,
}) => baseHours <= 0 ? 100 : (100 * sleptHours / baseHours).clamp(0, cap);

// ---- Sleep score v3 -----------------------------------------------------------

/// The parts of the sleep score, each 0–100 (null when not measurable).
final class SleepScore {
  const SleepScore({
    required this.score,
    required this.sufficiency,
    this.regularity,
    this.efficiency,
    this.continuity,
    this.latency,
  });
  final double score, sufficiency;
  final double? regularity, efficiency, continuity, latency;
}

/// Weights of the parts; missing parts drop out and the rest renormalise.
/// Duration against base need half, as Apple (50/30/20) and Fitbit do.
const sleepScoreWeights = (
  sufficiency: .50,
  regularity: .20,
  continuity: .15,
  efficiency: .10,
  latency: .05,
);

/// [v] mapped linearly from [poor] (0) to [good] (100), clamped; works in
/// either direction.
double band(double v, double good, double poor) =>
    ((v - poor) / (good - poor) * 100).clamp(0, 100).toDouble();

/// Wake bouts of [minMinutes]+ inside a night.
int wakeBouts(SleepSession s, {int minMinutes = 5}) {
  var n = 0, run = 0;
  for (final m in s.minutes) {
    if (m.stage == Stage.wake) {
      run++;
      if (run == minMinutes) n++;
    } else {
      run = 0;
    }
  }
  return n;
}

/// Minutes awake inside a night after first falling asleep (WASO).
int wasoMinutes(SleepSession s) =>
    s.minutes.where((m) => m.stage == Stage.wake).length;

/// Sleep score v3 (algo 10): sleep against your base need 50 %, bedtime
/// against your usual 20 %, continuity 15 %, efficiency 10 % and time to
/// fall asleep 5 %. Thresholds are the National Sleep Foundation's
/// sleep-quality consensus (Ohayon 2017): efficiency ≥ 85 % good, ≤ 74 %
/// poor; WASO ≤ 20 min good, ≥ 51 min poor; awakenings over 5 min 0–1
/// good, ≥ 4 poor; latency ≤ 30 min good, ≥ 46 min poor. Bedtime loses
/// its points over 3 h (Apple's curve is about this gentle; v2's 90 min
/// cost 15 points for an ordinary late Friday).
///
/// [efficiency] and [latencyMinutes] need the source's time in bed (see
/// [bedSpan]); without it they drop out rather than read a flat 99 %.
/// Wrist stages and the heart-rate dip stay out.
SleepScore sleepScoreV3({
  required double sufficiency,
  int? bedDeviationMinutes,
  double? efficiency,
  int? wasoMin,
  int? wakeBoutCount,
  int? latencyMinutes,
}) {
  final reg = bedDeviationMinutes == null
      ? null
      : band(bedDeviationMinutes.abs().toDouble(), 0, 180);
  final eff = efficiency == null ? null : band(efficiency, .85, .74);
  double? cont;
  if (wasoMin != null || wakeBoutCount != null) {
    final parts = [
      if (wasoMin != null) band(wasoMin.toDouble(), 20, 51),
      if (wakeBoutCount != null) band(wakeBoutCount.toDouble(), 1, 4),
    ];
    cont = parts.reduce((a, b) => a + b) / parts.length;
  }
  final lat = latencyMinutes == null
      ? null
      : band(latencyMinutes.toDouble(), 30, 46);
  final suff = min(100.0, sufficiency);
  const w = sleepScoreWeights;
  var acc = w.sufficiency * suff, ws = w.sufficiency;
  for (final (v, wt) in [
    (reg, w.regularity),
    (cont, w.continuity),
    (eff, w.efficiency),
    (lat, w.latency),
  ]) {
    if (v == null) continue;
    acc += wt * v;
    ws += wt;
  }
  return SleepScore(
    score: acc / ws,
    sufficiency: suff,
    regularity: reg,
    efficiency: eff,
    continuity: cont,
    latency: lat,
  );
}

/// The source's time in bed around [night]: the run of in-bed minutes
/// ([Minute.inBed]) touching it, extended back from its first asleep
/// minute and on from its last. Null when the source gave no in-bed time
/// beyond the asleep span (the band; a watch that only writes sleep), as
/// efficiency and latency then can't be told. TODO(verify) on phones which
/// apps write in-bed time before falling asleep.
({DateTime start, DateTime end})? bedSpan(
  SleepSession night,
  List<Minute> minutes,
) {
  final i0 = minutes.indexWhere((m) => !m.ts.isBefore(night.start));
  if (i0 < 0) return null;
  var a = i0;
  while (a > 0 &&
      minutes[a - 1].inBed &&
      minutes[a].ts.difference(minutes[a - 1].ts).inMinutes <= 1) {
    a--;
  }
  final lastIdx = minutes.lastIndexWhere((m) => m.ts.isBefore(night.end));
  var b = lastIdx;
  while (b >= 0 &&
      b + 1 < minutes.length &&
      minutes[b + 1].inBed &&
      minutes[b + 1].ts.difference(minutes[b].ts).inMinutes <= 1) {
    b++;
  }
  final start = minutes[a].ts;
  final end = minutes[b].ts.add(const Duration(minutes: 1));
  if (!start.isBefore(night.start) && !end.isAfter(night.end)) return null;
  return (start: start, end: end);
}
