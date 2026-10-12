import 'package:drift/drift.dart';

// All timestamps are Unix seconds, UTC. Dates are local `YYYY-MM-DD`.

/// Raw per-minute activity from the band. Append-only.
class MinuteSamples extends Table {
  IntColumn get ts => integer()(); // start of minute
  IntColumn get steps => integer()();
  IntColumn get intensity => integer()();
  IntColumn get kind => integer()(); // raw band activity-kind code
  // Record bytes 4–7 (u32 LE), kept raw; meaning TODO(verify). Null for
  // rows synced before schema 5.
  IntColumn get aux => integer().nullable()();
  IntColumn get hr => integer().nullable()();
  @override
  Set<Column> get primaryKey => {ts};
}

/// Live HR during workouts. Append-only.
class HrLive extends Table {
  IntColumn get ts => integer()();
  IntColumn get bpm => integer()();
  TextColumn get source => text().withDefault(const Constant('band'))();
  @override
  Set<Column> get primaryKey => {ts};
}

class StressSamples extends Table {
  IntColumn get ts => integer()();
  IntColumn get value => integer()();
  @override
  Set<Column> get primaryKey => {ts};
}

class Spo2Samples extends Table {
  IntColumn get ts => integer()();
  IntColumn get value => integer()();
  // 0–64 band confidence for per-minute SpO₂ (type 0x26); null for older
  // rows and spot checks.
  IntColumn get quality => integer().nullable()();
  @override
  Set<Column> get primaryKey => {ts};
}

/// Oxygen-desaturation events from the band (type 0x27). Append-only.
@DataClassName('OdEventRow')
class OdEvents extends Table {
  IntColumn get ts => integer()();
  IntColumn get drop => integer()(); // SpO₂ points
  TextColumn get spo2 => text()(); // 240 × 1 s, hex
  TextColumn get hr => text()(); // 240 × 1 s, hex
  @override
  Set<Column> get primaryKey => {ts};
}

/// Derived from minute kinds. Replaced on recompute.
/// Workout summaries recorded by the band's own Workout app, as fetched.
/// Append-only; `workouts` rows with source 'band' are derived from these.
@DataClassName('BandWorkoutRow')
class BandWorkouts extends Table {
  IntColumn get start => integer()();
  IntColumn get end => integer()();
  IntColumn get kind => integer()(); // band sport code, TODO(verify)
  TextColumn get raw => text()(); // summary bytes, hex
  IntColumn get fetchedAt => integer()();
  @override
  Set<Column> get primaryKey => {start};
}

class SleepSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get start => integer()();
  IntColumn get end => integer()();
  TextColumn get stages =>
      text()(); // JSON: {"light":m,"deep":m,"rem":m,"wake":m}
  IntColumn get algoVersion => integer()();
}

class DailyScores extends Table {
  TextColumn get date => text()();
  RealColumn get strain => real()();
  RealColumn get trimp => real()();
  IntColumn get hrMax => integer()();
  RealColumn get sleepPerf => real().nullable()();
  RealColumn get sleptHours => real().nullable()();
  RealColumn get needHours => real().nullable()();
  RealColumn get napHours => real().withDefault(const Constant(0.0))();
  RealColumn get baseNeed => real().nullable()();
  IntColumn get sleepStart => integer().nullable()();
  IntColumn get sleepEnd => integer().nullable()();
  RealColumn get recovery => real().nullable()();
  RealColumn get rhr => real().nullable()();
  RealColumn get hrvProxy => real().nullable()();
  BoolColumn get calibrating => boolean()();
  IntColumn get algoVersion => integer()();
  // v10: band | apple_health | health_connect; real HRV from Health (ms).
  TextColumn get source => text().withDefault(const Constant('band'))();
  RealColumn get hrv => real().nullable()();
  TextColumn get hrvKind => text().nullable()(); // sdnn | rmssd
  @override
  Set<Column> get primaryKey => {date};
}

class Baselines extends Table {
  TextColumn get metric => text()();
  IntColumn get window => integer()(); // days
  RealColumn get mean => real()();
  RealColumn get sd => real()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {metric, window};
}

class Journal extends Table {
  TextColumn get date => text()();
  TextColumn get tag => text()();
  BoolColumn get value => boolean()();
  @override
  Set<Column> get primaryKey => {date, tag};
}

/// How you felt on waking, 1–5, asked before the day's call. User input:
/// re-rating the same morning replaces it.
class MorningFeel extends Table {
  TextColumn get date => text()();
  IntColumn get feel => integer()();
  IntColumn get ts => integer()(); // when it was answered
  @override
  Set<Column> get primaryKey => {date};
}

class SyncState extends Table {
  TextColumn get device => text()();
  TextColumn get dataType => text()();
  IntColumn get lastTs => integer()();
  @override
  Set<Column> get primaryKey => {device, dataType};
}

/// Small app settings (paired device id, HR max override…). Never secrets.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

/// Workouts: sessions recorded live in the app, and activities auto-detected
/// from minute samples. Derived or user-entered, never raw.
class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get start => integer()();
  IntColumn get end => integer()();
  TextColumn get sport =>
      text().nullable()(); // scoring Sport name; null = unknown
  TextColumn get title => text()();
  TextColumn get source => text()(); // 'live' | 'auto' | 'band' | 'health'
  BoolColumn get confirmed => boolean().withDefault(const Constant(false))();
  RealColumn get strain => real()(); // day strain added by this session
  RealColumn get trimp => real()();
  IntColumn get avgHr => integer().nullable()();
  IntColumn get maxHr => integer().nullable()();
  TextColumn get zones => text()(); // JSON minutes per zone [z1..z5]
  IntColumn get rpe => integer().nullable()();
  TextColumn get plan => text().nullable()(); // JSON scoring Session if guided
}

/// The coach's plan, one row per day. Rewritten by the morning adaptation.
class PlanDays extends Table {
  TextColumn get date => text()();
  TextColumn get session => text()(); // JSON scoring Session
  TextColumn get original => text().nullable()(); // JSON before adaptation
  TextColumn get reason => text().nullable()();
  IntColumn get adaptedAt => integer().nullable()();
  BoolColumn get general => boolean()();

  /// Tempo Coach intent (v8). What the user or coach decided; whether it
  /// was done is derived from workouts, never stored.
  TextColumn get slot => text().nullable()(); // am | pm | null = any
  IntColumn get plannedMinute => integer().nullable()(); // minute of day
  TextColumn get status => text().withDefault(
    const Constant('planned'),
  )(); // planned|skipped|moved|done
  TextColumn get statusSource => text().nullable()(); // user|notification|coach
  IntColumn get statusAt => integer().nullable()();
  TextColumn get algoVersion => text().nullable()();
  @override
  Set<Column> get primaryKey => {date};
}

/// Every coach notification decision and response (v8), append-only so
/// timing and backoff can be audited and tuned.
class NudgeLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ts => integer()();
  TextColumn get day => text()(); // yyyy-mm-dd the nudge belongs to
  TextColumn get kind => text()();
  IntColumn get notifId => integer()();
  IntColumn get fireAt => integer().nullable()();
  TextColumn get event => text()(); // scheduled|cancelled|posted|tapped|action
  TextColumn get action => text().nullable()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  TextColumn get algoVersion => text()();
}

/// One line per sync attempt, for Data health.
class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ts => integer()();
  TextColumn get summary => text()();
  TextColumn get result => text()(); // ok | retried | failed | gap
  IntColumn get durationMs => integer().nullable()();
}

/// Tempo Age snapshots, derived from the 30 days before [date]. Replaced
/// when recomputed.
@DataClassName('LongevitySnapshot')
class Longevity extends Table {
  TextColumn get date => text()();
  RealColumn get tempoAge => real()();
  RealColumn get realAge => real()();
  BoolColumn get calibrating => boolean()();
  TextColumn get contributors => text()(); // JSON
  IntColumn get algoVersion => integer()();
  @override
  Set<Column> get primaryKey => {date};
}

/// Records read from Apple Health or Health Connect, as read. Append-only:
/// an edited or deleted Health record gets a [HealthDeletions] tombstone
/// instead. Keyed by health_source's `HealthRecord.key` (kind, platform
/// id, start, end), since Health Connect shares one id across the samples
/// of a record.
@DataClassName('HealthRecordRow')
class HealthRecords extends Table {
  TextColumn get key => text()();
  TextColumn get uuid => text()();
  TextColumn get kind => text()(); // health_source HealthKind name
  IntColumn get startMs => integer()(); // Unix ms
  IntColumn get endMs => integer()();
  RealColumn get value => real()();
  TextColumn get sourceApp => text()();
  TextColumn get extra => text().nullable()(); // workout type
  IntColumn get fetchedAt => integer()();
  @override
  Set<Column> get primaryKey => {key};
}

/// Health records found gone (deleted, or replaced by an edit) on a later
/// read. Append-only.
@DataClassName('HealthDeletionRow')
class HealthDeletions extends Table {
  TextColumn get key => text()();
  IntColumn get seenAt => integer()();
  @override
  Set<Column> get primaryKey => {key};
}

/// Per-minute data derived from [HealthRecords] (health_source HealthGrid).
/// Derived: rebuilt for a window after every Health read.
@DataClassName('HealthMinuteRow')
class HealthMinutes extends Table {
  IntColumn get ts => integer()(); // start of minute
  IntColumn get steps => integer()();
  IntColumn get hr => integer().nullable()(); // measured or interpolated
  BoolColumn get hrMeasured => boolean()();
  TextColumn get sleep => text().nullable()(); // health_source SleepMark name
  IntColumn get spo2 => integer().nullable()();
  @override
  Set<Column> get primaryKey => {ts};
}
