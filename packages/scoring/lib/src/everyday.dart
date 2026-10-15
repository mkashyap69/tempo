/// Everyday metrics: sleep regularity, social jetlag, body signals, brisk
/// minutes, the longest stretch without moving, and how fast heart rate
/// falls after a workout. Every constant is a starting value to calibrate.
library;

import 'dart:math';

import 'types.dart';

// ---- Sleep regularity -----------------------------------------------------

/// Sleep Regularity Index (Phillips 2017): the chance that you are in the
/// same state (asleep or awake) at any two moments 24 h apart, scaled to
/// −100…100. 100 = same pattern every day. In UK Biobank (Windred 2024,
/// ~60,000 people) the most regular fifth (SRI ≈ 80+) had markedly lower
/// mortality than the least regular, more strongly than sleep length.
///
/// Only minute pairs where both minutes are known count: a minute is
/// known when it was asleep, or awake with the band or watch worn (not
/// [Stage.unknown], not [Minute.offWrist]). Null with fewer than
/// [minPairDays] days' worth of pairs (at 70 % coverage).
double? sleepRegularity(List<Minute> minutes, {int minPairDays = 5}) {
  final state = <int, bool>{};
  for (final m in minutes) {
    if (m.offWrist || m.stage == Stage.unknown) continue;
    state[m.ts.millisecondsSinceEpoch ~/ 60000] = m.stage.asleep;
  }
  var pairs = 0, same = 0;
  for (final e in state.entries) {
    final next = state[e.key + 1440];
    if (next == null) continue;
    pairs++;
    if (next == e.value) same++;
  }
  if (pairs < minPairDays * 1440 * .7) return null;
  return 200 * same / pairs - 100;
}

enum Regularity { regular, fair, irregular }

/// Bands for [sleepRegularity]: ≥ 80 regular (the most regular fifth in
/// Windred 2024), 65–80 fair, under 65 irregular.
Regularity regularityBand(double sri) => sri >= 80
    ? Regularity.regular
    : sri >= 65
    ? Regularity.fair
    : Regularity.irregular;

// ---- Social jetlag --------------------------------------------------------

/// One main sleep, as `daily_scores` has it.
typedef NightSpan = ({DateTime start, DateTime end});

final class SocialJetlag {
  const SocialJetlag({
    required this.minutes,
    required this.freeMid,
    required this.workMid,
    required this.freeNights,
    required this.workNights,
  });

  /// Mid-sleep on free days minus on work days, in minutes. Positive =
  /// later at weekends (the usual direction).
  final int minutes;

  /// Median mid-sleep, minutes after midnight (may exceed 1440 or be
  /// negative when it falls the evening before; normalised for display).
  final int freeMid, workMid;
  final int freeNights, workNights;
}

/// Social jetlag (Wittmann 2006): how far mid-sleep shifts between free
/// days and work days. Free nights end on Saturday or Sunday morning.
/// Needs at least [minFree] free and [minWork] work nights.
SocialJetlag? socialJetlag(
  List<NightSpan> nights, {
  int minFree = 2,
  int minWork = 3,
}) {
  final free = <int>[], work = <int>[];
  for (final n in nights) {
    if (!n.end.isAfter(n.start)) continue;
    final mid = n.start.add(n.end.difference(n.start) ~/ 2);
    // Minutes after midnight, with evening times negative so 23:30 and
    // 00:30 sit an hour apart, not 23 hours.
    var m = mid.hour * 60 + mid.minute;
    if (m >= 18 * 60) m -= 1440;
    final weekend =
        n.end.weekday == DateTime.saturday || n.end.weekday == DateTime.sunday;
    (weekend ? free : work).add(m);
  }
  if (free.length < minFree || work.length < minWork) return null;
  int median(List<int> xs) {
    final s = [...xs]..sort();
    final k = s.length ~/ 2;
    return s.length.isOdd ? s[k] : ((s[k - 1] + s[k]) / 2).round();
  }

  final f = median(free), w = median(work);
  return SocialJetlag(
    minutes: f - w,
    freeMid: f,
    workMid: w,
    freeNights: free.length,
    workNights: work.length,
  );
}

/// Over an hour of social jetlag is linked with worse metabolic health and
/// mood (Roenneberg 2012); under 30 minutes is negligible.
enum JetlagBand { small, moderate, large }

JetlagBand jetlagBand(int minutes) => minutes.abs() < 30
    ? JetlagBand.small
    : minutes.abs() <= 60
    ? JetlagBand.moderate
    : JetlagBand.large;

// ---- Body signals ---------------------------------------------------------

/// One overnight signal against your own recent nights.
final class SignalInput {
  const SignalInput({
    required this.key,
    required this.value,
    required this.history,
    required this.higherIsWorse,
    required this.minDelta,
  });

  /// `rhr`, `hrv` (ln ms), `stress`, `resp`, `spo2`.
  final String key;
  final double? value;

  /// Earlier nights (any order), same source and measure.
  final List<double> history;
  final bool higherIsWorse;

  /// The smallest change that counts as off, whatever the spread: a very
  /// steady baseline must not turn 1 bpm into an alarm.
  final double minDelta;
}

enum SignalState { learning, missing, normal, off }

final class SignalReading {
  const SignalReading(this.key, this.state, {this.value, this.mean, this.z});
  final String key;
  final SignalState state;
  final double? value, mean;

  /// Signed so that positive is worse.
  final double? z;

  double? get delta => value == null || mean == null ? null : value! - mean!;
}

enum BodyLevel { learning, normal, watch, rest }

final class BodySignals {
  const BodySignals(this.readings, this.level);
  final List<SignalReading> readings;

  /// [BodyLevel.watch] with one signal off, [BodyLevel.rest] with two or
  /// more: several vitals moving the wrong way together is what precedes
  /// illness in wearable studies (Mishra 2020, Radin 2020); one alone is
  /// often just a late meal or a drink.
  final BodyLevel level;

  List<SignalReading> get off => [
    for (final r in readings)
      if (r.state == SignalState.off) r,
  ];
}

/// Nights of history a signal needs before it is judged.
const signalMinNights = 14;

/// Standard deviations the wrong way that make a signal off.
const signalOffZ = 2.0;

/// Compares each signal with its own history: off when it sits at least
/// [signalOffZ] SDs and [SignalInput.minDelta] the wrong way. The SD is
/// floored at half of minDelta so a flat history can't make noise look
/// huge. Better-than-usual values are normal.
BodySignals bodySignals(List<SignalInput> inputs) {
  final out = <SignalReading>[];
  for (final i in inputs) {
    if (i.history.length < signalMinNights) {
      out.add(SignalReading(i.key, SignalState.learning, value: i.value));
      continue;
    }
    final mean = i.history.reduce((a, b) => a + b) / i.history.length;
    if (i.value == null) {
      out.add(SignalReading(i.key, SignalState.missing, mean: mean));
      continue;
    }
    final v = i.value!;
    final variance =
        i.history.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        (i.history.length - 1);
    final sd = max(sqrt(variance), i.minDelta / 2);
    final worse = i.higherIsWorse ? v - mean : mean - v;
    final z = worse / sd;
    final off = z >= signalOffZ && worse >= i.minDelta;
    out.add(
      SignalReading(
        i.key,
        off ? SignalState.off : SignalState.normal,
        value: v,
        mean: mean,
        z: z,
      ),
    );
  }
  final judged = out.where(
    (r) => r.state == SignalState.normal || r.state == SignalState.off,
  );
  final offN = out.where((r) => r.state == SignalState.off).length;
  final level = judged.isEmpty
      ? BodyLevel.learning
      : offN >= 2
      ? BodyLevel.rest
      : offN == 1
      ? BodyLevel.watch
      : BodyLevel.normal;
  return BodySignals(out, level);
}

// ---- Brisk minutes --------------------------------------------------------

/// Steps per minute that count as brisk walking (Tudor-Locke 2018: 100
/// steps/min ≈ moderate intensity for adults).
const briskCadence = 100;

/// Daily brisk minutes worth aiming for: 30 a day is ~150 a week of
/// moderate activity (WHO 2020), and time at 100+ steps/min tracked lower
/// mortality independent of total steps (Del Pozo-Cruz 2022).
const briskTarget = 30;

/// Minutes in [minutes] at [briskCadence] steps or more.
int briskMinutes(Iterable<Minute> minutes) =>
    minutes.where((m) => m.steps >= briskCadence).length;

// ---- Longest stretch without moving -----------------------------------------

/// Steps in a minute that break a still stretch (getting up and walking
/// a few metres).
const moveBreakSteps = 20;

final class StillStretch {
  const StillStretch(this.start, this.minutes);
  final DateTime start;
  final int minutes;
  DateTime get end => start.add(Duration(minutes: minutes));
}

/// The longest run of awake, worn, still minutes in [minutes] (sorted, one
/// per minute). A minute is still when it has fewer than [moveBreakSteps]
/// steps and a heart rate under [hrRest] + 30 (cycling has no steps but a
/// high heart rate). Sleep, unworn minutes, gaps, minutes inside [busy]
/// spans (workouts) and moving minutes end a stretch.
///
/// Null when under half of the minutes were worn with heart rate: a phone
/// without a watch only sees steps while it's carried, so "no steps"
/// can't be told from "phone on the desk".
StillStretch? longestStill(
  List<Minute> minutes, {
  required double hrRest,
  List<(DateTime, DateTime)> busy = const [],
}) {
  if (minutes.isEmpty) return null;
  final worn = minutes.where((m) => m.hr != null).length;
  if (worn * 2 < minutes.length) return null;
  bool isBusy(DateTime t) =>
      busy.any((b) => !t.isBefore(b.$1) && t.isBefore(b.$2));
  StillStretch? best;
  DateTime? runStart;
  var run = 0;
  DateTime? prev;
  void close() {
    if (runStart != null && run > 0 && (best == null || run > best!.minutes)) {
      best = StillStretch(runStart!, run);
    }
    runStart = null;
    run = 0;
  }

  for (final m in minutes) {
    if (prev != null && m.ts.difference(prev).inMinutes > 1) close();
    prev = m.ts;
    final still =
        !m.stage.asleep &&
        !m.offWrist &&
        m.hr != null &&
        m.hr! < hrRest + 30 &&
        m.steps < moveBreakSteps &&
        !isBusy(m.ts);
    if (!still) {
      close();
      continue;
    }
    runStart ??= m.ts;
    run++;
  }
  close();
  return best;
}

// ---- Heart-rate recovery after a workout ---------------------------------

/// How hard a workout's last minutes must be for recovery to mean
/// something: peak at least this share of max HR.
const recoveryMinPeak = .7;

/// A 2-minute drop of 22 bpm or less after exercise tracked higher
/// mortality in clinical exercise tests (Shetler 2001). Tempo's minutes
/// are averages and nobody stops dead after a run, so it is shown as a
/// personal trend, with this as the line between "typical" and "slow".
const recoveryTypicalDrop = 22;

/// Heart rate drop in the 2 minutes after a workout ended: the highest
/// measured minute in its last 3 minutes minus the minute 2 minutes after
/// [end]. [minutes] must hold measured heart rate only (no filled gaps).
/// Null when the peak is under [recoveryMinPeak] of [hrMax] or either side
/// has no reading.
int? recoveryDrop(List<Minute> minutes, DateTime end, {required int hrMax}) {
  final endKey = end.millisecondsSinceEpoch ~/ 60000;
  int? peak, after;
  for (final m in minutes) {
    final k = m.ts.millisecondsSinceEpoch ~/ 60000;
    final hr = m.hr;
    if (hr == null) continue;
    if (k >= endKey - 3 && k < endKey) peak = max(peak ?? 0, hr);
    if (k == endKey + 2) after = hr;
  }
  if (peak == null || after == null) return null;
  if (peak < hrMax * recoveryMinPeak) return null;
  return peak - after;
}
