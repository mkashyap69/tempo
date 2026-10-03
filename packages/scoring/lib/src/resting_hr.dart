import 'types.dart';

/// Lowest rolling [window]-minute average HR among [minutes] (usually the
/// night's sleep). Windows need at least half their minutes with a reading.
double? restingHr(List<Minute> minutes, {int window = 5}) {
  if (minutes.length < window) return null;
  double? best;
  for (var i = 0; i + window <= minutes.length; i++) {
    var sum = 0, n = 0;
    for (var j = i; j < i + window; j++) {
      final hr = minutes[j].hr;
      if (hr != null) {
        sum += hr;
        n++;
      }
    }
    if (n * 2 < window) continue;
    final avg = sum / n;
    if (best == null || avg < best) best = avg;
  }
  return best;
}
