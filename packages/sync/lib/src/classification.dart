/// How each table travels (Backend plan → What syncs).
enum SyncClass {
  /// Raw samples, append-only: insert-or-ignore on the table's key.
  appendOnly,

  /// What the user entered: last writer wins per row, by `updated_at`.
  userEntered,

  /// Rebuilt on the phone after a restore; never uploaded.
  derived,

  /// Belongs to this device only; never uploaded.
  deviceLocal,
}

/// Every table in `packages/store`, by SQL name. The app's test fails when a
/// table is added without a line here.
const syncTables = <String, SyncClass>{
  'health_records': SyncClass.appendOnly,
  'health_deletions': SyncClass.appendOnly,
  'minute_samples': SyncClass.appendOnly,
  'stress_samples': SyncClass.appendOnly,
  'spo2_samples': SyncClass.appendOnly,
  'od_events': SyncClass.appendOnly,
  'hr_live': SyncClass.appendOnly,
  'band_workouts': SyncClass.appendOnly,
  'nudge_log': SyncClass.appendOnly,
  'journal': SyncClass.userEntered,
  'morning_feel': SyncClass.userEntered,
  'workouts': SyncClass.userEntered,
  'strength_sets': SyncClass.userEntered,
  'plan_days': SyncClass.userEntered,
  'longevity': SyncClass.userEntered,
  // Only the keys in the app's synced-settings list; see SettingsSync.
  'settings': SyncClass.userEntered,
  'daily_scores': SyncClass.derived,
  'baselines': SyncClass.derived,
  'sleep_sessions': SyncClass.derived,
  'health_minutes': SyncClass.derived,
  'sync_state': SyncClass.deviceLocal,
  'sync_log': SyncClass.deviceLocal,
};

bool uploads(String table) => switch (syncTables[table]) {
  SyncClass.appendOnly || SyncClass.userEntered => true,
  SyncClass.derived || SyncClass.deviceLocal => false,
  null => throw StateError('table $table has no sync class'),
};
