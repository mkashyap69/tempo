import 'record.dart';

/// A stored record, as far as reconciling needs it.
typedef StoredKey = ({String key, HealthKind kind, DateTime start});

/// Result of [reconcile]: keys whose records are gone from Health (deleted,
/// or replaced by an edit), and kinds left alone because the read looked
/// incomplete.
typedef Reconciled = ({List<String> gone, List<HealthKind> doubtful});

/// Which stored records in a re-read window no longer exist in Health.
///
/// Health has no reliable delete feed through the plugin on iOS, and an
/// edited Health Connect record keeps its id but changes its samples, so
/// each sync re-reads a recent window and compares. A stored record of a
/// kind that was [read] with a start in [from, to) that is not in [fresh]
/// is gone. Rows are never deleted: the caller writes a tombstone.
///
/// A read can come back empty without failing: Health Connect returns an
/// empty list on any error, and iOS hides a revoked read permission as "no
/// data". So a kind is only reconciled when the fresh read has at least
/// one record of it and at least half as many as were stored; otherwise it
/// is reported as doubtful and nothing of it is tombstoned.
Reconciled reconcile({
  required Iterable<StoredKey> stored,
  required Iterable<HealthRecord> fresh,
  required Set<HealthKind> read,
  required DateTime from,
  required DateTime to,
}) {
  final freshKeys = <HealthKind, Set<String>>{};
  for (final r in fresh) {
    freshKeys.putIfAbsent(r.kind, () => {}).add(r.key);
  }
  final inWindow = <HealthKind, List<String>>{};
  for (final s in stored) {
    if (!read.contains(s.kind)) continue;
    if (s.start.isBefore(from) || !s.start.isBefore(to)) continue;
    inWindow.putIfAbsent(s.kind, () => []).add(s.key);
  }
  final gone = <String>[];
  final doubtful = <HealthKind>[];
  for (final MapEntry(key: kind, value: keys) in inWindow.entries) {
    final f = freshKeys[kind] ?? const <String>{};
    if (f.isEmpty || f.length * 2 < keys.length) {
      doubtful.add(kind);
      continue;
    }
    for (final k in keys) {
      if (!f.contains(k)) gone.add(k);
    }
  }
  return (gone: gone, doubtful: doubtful);
}
