import 'dart:math';

import 'record.dart';

/// Which HRV measure a reading is. Apple Watch writes SDNN, Health Connect
/// RMSSD; they sit on different scales, so they never share a baseline.
enum HrvKind { sdnn, rmssd }

final class NightHrv {
  const NightHrv(this.ms, this.kind, this.n);

  /// Geometric mean of the readings, ms (HRV is log-normal).
  final double ms;
  final HrvKind kind;
  final int n;
}

/// HRV over one night: readings from 30 min before [start] to 30 min after
/// [end]. RMSSD is preferred when both kinds exist (two apps writing). Null
/// with no plausible reading (5–300 ms).
NightHrv? nightHrv(
  Iterable<HealthRecord> records,
  DateTime start,
  DateTime end, {
  Duration slack = const Duration(minutes: 30),
}) {
  final a = start.subtract(slack), b = end.add(slack);
  final logs = {HrvKind.sdnn: <double>[], HrvKind.rmssd: <double>[]};
  for (final r in records) {
    final kind = switch (r.kind) {
      HealthKind.hrvSdnn => HrvKind.sdnn,
      HealthKind.hrvRmssd => HrvKind.rmssd,
      _ => null,
    };
    if (kind == null || r.fromTempo) continue;
    if (r.start.isBefore(a) || !r.start.isBefore(b)) continue;
    if (r.value.isNaN || r.value < 5 || r.value > 300) continue;
    logs[kind]!.add(log(r.value));
  }
  for (final k in [HrvKind.rmssd, HrvKind.sdnn]) {
    final xs = logs[k]!;
    if (xs.isEmpty) continue;
    return NightHrv(exp(xs.reduce((x, y) => x + y) / xs.length), k, xs.length);
  }
  return null;
}

/// The source's own resting heart rate for the day that starts on [day]
/// (local midnight): the mean of its readings that day, 30–120 bpm. Only a
/// fallback; Tempo derives resting HR from the night itself when the night
/// has heart rate.
double? sourceRestingHr(Iterable<HealthRecord> records, DateTime day) {
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(day.year, day.month, day.day + 1);
  final xs = [
    for (final r in records)
      if (r.kind == HealthKind.restingHr &&
          !r.fromTempo &&
          !r.start.isBefore(a) &&
          r.start.isBefore(b) &&
          r.value >= 30 &&
          r.value <= 120)
        r.value,
  ];
  if (xs.isEmpty) return null;
  return xs.reduce((x, y) => x + y) / xs.length;
}
