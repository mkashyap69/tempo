import 'dart:math';

/// RMSSD (ms) of beat-to-beat intervals: the root mean square of
/// successive differences, the standard short-term HRV measure.
///
/// Artifacts are dropped first: intervals outside 300–2000 ms (200–30 bpm)
/// and any beat differing from the previous kept one by more than 20 %
/// (a missed or extra beat). Null with fewer than [minBeats] kept beats.
double? rmssd(List<num> rrMs, {int minBeats = 30}) {
  final kept = <double>[];
  for (final r in rrMs) {
    final x = r.toDouble();
    if (x < 300 || x > 2000) continue;
    if (kept.isNotEmpty && (x - kept.last).abs() > kept.last * .2) continue;
    kept.add(x);
  }
  if (kept.length < minBeats) return null;
  var sum = 0.0;
  for (var i = 1; i < kept.length; i++) {
    final d = kept[i] - kept[i - 1];
    sum += d * d;
  }
  return sqrt(sum / (kept.length - 1));
}
