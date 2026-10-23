/// Bump whenever any formula or constant changes. Stored on every score.
/// 2: activity kind 0xf0 counts as sleep (V1.0.6.20 capture).
/// 3: TRIMP floor at 30% of HR reserve, k 40; learned base sleep need;
///    naps count against debt; strength sessions use sRPE.
/// 4: sleep from the band's sleep flag (V1.0.6.20 bit field), stages
///    estimated from HR and motion (sleep_stages.dart).
/// 5: a quiet wake (≤ 90 min, ≤ 30 steps) stays inside the night; deep
///    judged against the night's HR drift; band walking code (0x01).
/// 6: quiet minutes the band flags awake inside the night are staged.
/// 7: a quiet wake only joins sleep while the band is worn.
/// 8: data sources (band, Apple Health, Health Connect): baselines and
///    calibration per source; real HRV (ln ms, higher is better) as the
///    recovery HRV input; the source's resting HR when the night has none.
/// 9: sleep score v2, vitals penalty, night temperature.
/// 10: algorithm review (docs/research/Algorithm review.md): debt against
///    the base need, base need learned from autonomic recovery (7–9 h),
///    sufficiency against base in Recovery, sleep score v3, in-bed time
///    for efficiency and latency, resting HR as the 10th percentile of
///    asleep HR, robust HR max, smaller strain term in need.
const algoVersion = 10;

enum Stage { wake, light, deep, rem, unknown }

extension StageX on Stage {
  bool get asleep =>
      this == Stage.light || this == Stage.deep || this == Stage.rem;
}

/// One minute of band data, already decoded from raw codes.
final class Minute {
  const Minute(
    this.ts, {
    this.hr,
    this.steps = 0,
    this.stage = Stage.unknown,
    this.motion = 0,
    this.bandWalking = false,
    this.offWrist = false,
    this.inBed = false,
  });

  /// Start of the minute.
  final DateTime ts;

  /// BPM, or null when the band had no reading.
  final int? hr;
  final int steps;
  final Stage stage;

  /// The band's per-minute movement intensity (0 = perfectly still).
  final int motion;

  /// The band's own activity code said walking this minute.
  final bool bandWalking;

  /// The band said it was not worn this minute.
  final bool offWrist;

  /// The source counted this minute as in bed (any sleep record, awake
  /// ones included). Only Health sources set it; the band never does.
  final bool inBed;

  Minute withStage(Stage s) => Minute(
    ts,
    hr: hr,
    steps: steps,
    stage: s,
    motion: motion,
    bandWalking: bandWalking,
    offWrist: offWrist,
    inBed: inBed,
  );
}
