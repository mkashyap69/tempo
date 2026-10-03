import 'package:drift/drift.dart';

// All timestamps are Unix seconds, UTC. Dates are local `YYYY-MM-DD`.

/// Raw per-minute activity from the band. Append-only.
class MinuteSamples extends Table {
  IntColumn get ts => integer()(); // start of minute
  IntColumn get steps => integer()();
  IntColumn get intensity => integer()();
  IntColumn get kind => integer()(); // raw band activity-kind code
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
  @override
  Set<Column> get primaryKey => {ts};
}

/// Derived from minute kinds. Replaced on recompute.
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
  IntColumn get sleepStart => integer().nullable()();
  IntColumn get sleepEnd => integer().nullable()();
  RealColumn get recovery => real().nullable()();
  RealColumn get rhr => real().nullable()();
  RealColumn get hrvProxy => real().nullable()();
  BoolColumn get calibrating => boolean()();
  IntColumn get algoVersion => integer()();
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
