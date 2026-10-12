/// What a Health record measures. One kind per `health` plugin type Tempo
/// reads; names are stored, so never rename one.
enum HealthKind {
  heartRate,
  steps,

  /// iOS "in bed" (value 0): a container, no stage of its own.
  sleepInBed,

  /// Health Connect sleep session: a container around its stages.
  sleepSession,

  /// Asleep with no stage (iOS asleepUnspecified, Health Connect SLEEPING).
  sleepAsleep,
  sleepAwake,

  /// iOS asleepCore; Health Connect LIGHT.
  sleepLight,
  sleepDeep,
  sleepRem,

  /// Apple Watch HRV (SDNN, ms).
  hrvSdnn,

  /// Health Connect HRV (RMSSD, ms).
  hrvRmssd,
  restingHr,

  /// SpO₂ as stored: iOS gives a fraction (0.97), Health Connect a percent.
  spo2,
  workout,
}

extension HealthKindX on HealthKind {
  bool get isSleepContainer =>
      this == HealthKind.sleepInBed || this == HealthKind.sleepSession;

  bool get isSleepStage => switch (this) {
    HealthKind.sleepAsleep ||
    HealthKind.sleepAwake ||
    HealthKind.sleepLight ||
    HealthKind.sleepDeep ||
    HealthKind.sleepRem => true,
    _ => false,
  };

  bool get isSleep => isSleepContainer || isSleepStage;
}

/// Tempo's own bundle id / package name. Tempo writes workouts and nights
/// to Health (Profile → Health export), so its own records are dropped on
/// read: reading them back would count a night or workout twice.
const tempoAppId = 'dev.tempo.tempo';

/// One record as read from Apple Health or Health Connect. Raw: stored as
/// read, never edited (see `health_records`).
final class HealthRecord {
  const HealthRecord({
    required this.uuid,
    required this.kind,
    required this.start,
    required this.end,
    required this.value,
    this.sourceApp = '',
    this.extra,
  });

  /// The platform's id. Not unique on its own: Health Connect gives every
  /// heart-rate sample of one record, and every stage of one sleep session,
  /// the same id. Use [key].
  final String uuid;
  final HealthKind kind;
  final DateTime start, end;

  /// bpm, steps, ms, SpO₂ (see [HealthKind.spo2]); minutes for sleep.
  final double value;

  /// Bundle id (iOS) or package name (Android) of the app that wrote it.
  final String sourceApp;

  /// Workout activity type name (`RUNNING`, …) for [HealthKind.workout].
  final String? extra;

  /// Unique per sample: kind, platform id, start and end.
  String get key =>
      '${kind.name}|$uuid|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}';

  bool get fromTempo => sourceApp == tempoAppId;

  @override
  String toString() =>
      'HealthRecord(${kind.name} $start–$end $value $sourceApp)';
}
