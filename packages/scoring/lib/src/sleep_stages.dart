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
  });

  /// Share of asleep minutes that need an HR reading; below it (HR only
  /// every 10–30 min) the night is left unstaged.
  final double minHrCoverage;
  final int wakeMotion, stillMotion;
  final double wakeHrAbove;

  /// Smoothed HR at or below this quantile of the night can be deep.
  final double deepQuantile;
  final int remDelayMinutes, minRunMinutes, smoothWindow, varWindow;
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
  final lo = quantile(asleepSmooth, p.deepQuantile)!;
  final med = quantile(asleepSmooth, .5)!;
  final sdLo = quantile(asleepVary, .5)!;
  final sdHi = quantile(asleepVary, .5)!;

  final onset = sleep[idx.first].ts;
  final stages = [for (final m in sleep) m.stage];
  for (final i in idx) {
    final m = sleep[i];
    final sinceOnset = m.ts.difference(onset).inMinutes;
    final still = m.motion <= p.stillMotion && m.steps == 0;
    if (m.motion >= p.wakeMotion ||
        m.steps > 0 ||
        smooth[i] > med + p.wakeHrAbove) {
      stages[i] = Stage.wake;
    } else if (still && smooth[i] <= lo && vary[i] <= sdLo) {
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
        (s == Stage.wake && len < 2 && sleep[i].stage.asleep)) {
      for (var k = i; k < j; k++) {
        if (sleep[k].stage.asleep) stages[k] = Stage.light;
      }
    }
    i = j;
  }
  return StagedSleep([
    for (var k = 0; k < n; k++) sleep[k].withStage(stages[k]),
  ], staged: true);
}
