/// Bump whenever any formula or constant changes. Stored on every score.
/// 2: activity kind 0xf0 counts as sleep (V1.0.6.20 capture).
/// 3: TRIMP floor at 30% of HR reserve, k 40; learned base sleep need;
///    naps count against debt; strength sessions use sRPE.
/// 4: sleep from the band's sleep flag (V1.0.6.20 bit field), stages
///    estimated from HR and motion (sleep_stages.dart).
/// 5: a quiet wake (≤ 90 min, ≤ 30 steps) stays inside the night; deep
///    judged against the night's HR drift; band walking code (0x01).
const algoVersion = 5;

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

  Minute withStage(Stage s) => Minute(
    ts,
    hr: hr,
    steps: steps,
    stage: s,
    motion: motion,
    bandWalking: bandWalking,
  );
}
