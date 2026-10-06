import 'dart:math';

import 'baseline.dart';
import 'types.dart';

/// The Mi Band 6 (V1.0.6.20) marks minutes as asleep but sends no stages,
/// so Tempo estimates them from heart rate and movement:
///
/// * **Wake**: movement, steps, or HR well above the night's median.
/// * **Deep**: the night's lowest, steadiest heart rate, perfectly still.
/// * **REM**: still, but HR at or above the night's median and more
///   variable, and not in the first hour after falling asleep.
/// * **Light**: everything else.
///
/// Short runs are smoothed away. It is an estimate (consumer wrist staging
/// agrees with lab sleep studies only roughly) and is shown as one.
final class StageParams {
  const StageParams({
    this.minHrCoverage = .6,
    this.wakeMotion = 25,
    this.stillMotion = 10,
    this.wakeHrAbove = 12,
    this.deepQuantile = .35,
    this.remDelayMinutes = 60,
    this.minRunMinutes = 5,
    this.smoothWindow = 5,
    this.varWindow = 9,
    this.detrend = true,
    this.quietAwakeSleeps = true,
  });

  /// Share of asleep minutes that need an HR reading; below it (HR only
  /// every 10–30 min) the night is left unstaged.
  final double minHrCoverage;
  final int wakeMotion, stillMotion;
  final double wakeHrAbove;

  /// Smoothed HR at or below this quantile of the night can be deep.
  final double deepQuantile;
  final int remDelayMinutes, minRunMinutes, smoothWindow, varWindow;

  /// Sleeping HR drifts down through the night (6 Oct: ~54 → 48 bpm), so
  /// "lowest HR of the night" lands late. With [detrend], deep is judged
  /// against a straight line fitted through the night's asleep HR (a
  /// rolling median would swallow long deep blocks).
  final bool detrend;

  /// Minutes inside the night the band flags awake but that are quiet (no
  /// steps, movement under [wakeMotion], HR not raised) are staged like
  /// any other minute. 6 Oct: Mi Fitness counted 1 wake-up of 1 min where
  /// the band's flag had 30 min awake at 05:28, nearly all still.
  final bool quietAwakeSleeps;
}

/// Result of [stageSleep]: the same minutes with stages, and whether there
/// was enough heart rate to stage at all.
final class StagedSleep {
  const StagedSleep(this.minutes, {required this.staged});
  final List<Minute> minutes;
  final bool staged;
}

/// Stages the asleep minutes of one sleep (from first to last asleep
/// minute; awake minutes inside are kept and may be re-labelled).
StagedSleep stageSleep(
  List<Minute> sleep, [
  StageParams p = const StageParams(),
]) {
  final idx = [
    for (var i = 0; i < sleep.length; i++)
      if (sleep[i].stage.asleep) i,
  ];
  if (idx.isEmpty) return StagedSleep(sleep, staged: false);
  final withHr = idx.where((i) => sleep[i].hr != null).length;
  if (withHr / idx.length < p.minHrCoverage) {
    return StagedSleep(sleep, staged: false);
  }

  // Heart rate filled forward then back, so every minute has a value.
  final n = sleep.length;
  final hr = List<double?>.generate(n, (i) => sleep[i].hr?.toDouble());
  double? last;
  for (var i = 0; i < n; i++) {
    hr[i] ??= last;
    last = hr[i];
  }
  last = null;
  for (var i = n - 1; i >= 0; i--) {
    hr[i] ??= last;
    last = hr[i];
  }
  final h = [for (final x in hr) x ?? 0.0];

  List<double> window(int w, double Function(List<double>) f) => [
    for (var i = 0; i < n; i++)
      f(h.sublist(max(0, i - w ~/ 2), min(n, i + w ~/ 2 + 1))),
  ];
  double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  double sd(List<double> xs) {
    final m = mean(xs);
    return sqrt(
      xs.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / xs.length,
    );
  }

  final smooth = window(p.smoothWindow, mean);
  final vary = window(p.varWindow, sd);
  final asleepSmooth = [for (final i in idx) smooth[i]];
  final asleepVary = [for (final i in idx) vary[i]];
  // Deep: low HR relative to the night's downward drift.
  var slope = 0.0, icept = 0.0;
  if (p.detrend && idx.length > 1) {
    final mx = idx.fold<double>(0, (a, i) => a + i) / idx.length;
    final my = mean(asleepSmooth);
    var num = 0.0, den = 0.0;
    for (final i in idx) {
      num += (i - mx) * (smooth[i] - my);
      den += (i - mx) * (i - mx);
    }
    slope = den == 0 ? 0 : num / den;
    icept = my - slope * mx;
  }
  final rel = [
    for (var i = 0; i < n; i++)
      p.detrend ? smooth[i] - (icept + slope * i) : smooth[i],
  ];
  final relLo = quantile([for (final i in idx) rel[i]], p.deepQuantile)!;
  final med = quantile(asleepSmooth, .5)!;
  final sdLo = quantile(asleepVary, .5)!;
  final sdHi = quantile(asleepVary, .5)!;

  // Only between the first and last ≥ 10-minute runs of flagged sleep,
  // so a stray flagged minute can't pull onset or wake-up outward.
  int? coreFrom, coreTo;
  var runStart = idx.first;
  for (var k = 1; k <= idx.length; k++) {
    final end = k == idx.length || idx[k] != idx[k - 1] + 1;
    if (!end) continue;
    final a = runStart, b = idx[k - 1];
    if (b - a + 1 >= 10) {
      coreFrom ??= a;
      coreTo = b;
    }
    if (k < idx.length) runStart = idx[k];
  }
  final quiet = [
    if (p.quietAwakeSleeps && coreFrom != null)
      for (var i = coreFrom; i <= coreTo!; i++)
        if (sleep[i].stage == Stage.wake &&
            sleep[i].steps == 0 &&
            sleep[i].motion < p.wakeMotion &&
            smooth[i] <= med + p.wakeHrAbove)
          i,
  ];
  final judged = [...idx, ...quiet]..sort();
  final judgedSet = judged.toSet();

  final onset = sleep[idx.first].ts;
  final stages = [for (final m in sleep) m.stage];
  for (final i in judged) {
    final m = sleep[i];
    final sinceOnset = m.ts.difference(onset).inMinutes;
    final still = m.motion <= p.stillMotion && m.steps == 0;
    if (m.motion >= p.wakeMotion ||
        m.steps > 0 ||
        smooth[i] > med + p.wakeHrAbove) {
      stages[i] = Stage.wake;
    } else if (still && rel[i] <= relLo && vary[i] <= sdLo) {
      stages[i] = Stage.deep;
    } else if (still &&
        sinceOnset >= p.remDelayMinutes &&
        smooth[i] >= med &&
        vary[i] >= sdHi) {
      stages[i] = Stage.rem;
    } else {
      stages[i] = Stage.light;
    }
  }

  // Smooth: deep/REM runs shorter than minRun and single wake minutes
  // become light.
  var i = 0;
  while (i < n) {
    var j = i;
    while (j < n && stages[j] == stages[i]) {
      j++;
    }
    final len = j - i;
    final s = stages[i];
    if (((s == Stage.deep || s == Stage.rem) && len < p.minRunMinutes) ||
        (s == Stage.wake && len < 2 && judgedSet.contains(i))) {
      for (var k = i; k < j; k++) {
        if (judgedSet.contains(k)) stages[k] = Stage.light;
      }
    }
    i = j;
  }
  return StagedSleep([
    for (var k = 0; k < n; k++) sleep[k].withStage(stages[k]),
  ], staged: true);
}
