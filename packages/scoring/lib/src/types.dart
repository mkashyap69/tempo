/// Bump whenever any formula or constant changes. Stored on every score.
/// 2: activity kind 0xf0 counts as sleep (V1.0.6.20 capture).
const algoVersion = 2;

enum Stage { wake, light, deep, rem, unknown }

extension StageX on Stage {
  bool get asleep =>
      this == Stage.light || this == Stage.deep || this == Stage.rem;
}

/// One minute of band data, already decoded from raw codes.
final class Minute {
  const Minute(this.ts, {this.hr, this.steps = 0, this.stage = Stage.unknown});

  /// Start of the minute.
  final DateTime ts;

  /// BPM, or null when the band had no reading.
  final int? hr;
  final int steps;
  final Stage stage;
}
