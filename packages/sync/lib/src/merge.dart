import 'classification.dart';
import 'codec.dart';

typedef Row = Map<String, Object?>;

/// What merging incoming rows into a table should do.
class MergePlan {
  const MergePlan(this.insert, this.replace);

  /// Rows whose key isn't stored yet.
  final List<Row> insert;

  /// Rows that win over the stored row with the same key.
  final List<Row> replace;

  bool get isEmpty => insert.isEmpty && replace.isEmpty;
}

/// Plans a merge of [incoming] rows into a table holding [local] rows.
///
/// Merges are idempotent and order-free, so segments from several devices
/// can be applied in any order, any number of times:
/// - append-only tables insert what's missing and never change a stored row
///   (raw tables are append-only; CLAUDE.md);
/// - user-entered tables keep, per key, the row with the latest
///   [updatedAtField]; on a tie the row whose canonical form sorts last wins,
///   so every device reaches the same result.
MergePlan planMerge(
  SyncClass cls, {
  required Map<Object, Row> local,
  required Iterable<Row> incoming,
  required Object Function(Row) keyOf,
  String updatedAtField = 'updated_at',
  String Function(Row)? tieBreak,
}) {
  if (cls == SyncClass.derived || cls == SyncClass.deviceLocal) {
    throw ArgumentError('$cls tables are never merged');
  }
  final best = <Object, Row>{};
  for (final r in incoming) {
    final k = keyOf(r);
    final prev = best[k];
    best[k] = prev == null
        ? r
        : _wins(r, prev, updatedAtField, tieBreak)
        ? r
        : prev;
  }
  final insert = <Row>[], replace = <Row>[];
  for (final MapEntry(key: k, value: r) in best.entries) {
    final stored = local[k];
    if (stored == null) {
      insert.add(r);
    } else if (cls == SyncClass.userEntered &&
        _wins(r, stored, updatedAtField, tieBreak) &&
        !_same(r, stored)) {
      replace.add(r);
    }
  }
  return MergePlan(insert, replace);
}

bool _wins(Row a, Row b, String field, String Function(Row)? tie) {
  final ta = _ts(a[field]), tb = _ts(b[field]);
  if (ta != tb) return ta > tb;
  final f = tie ?? canonicalJson;
  return f(a).compareTo(f(b)) > 0;
}

int _ts(Object? v) => switch (v) {
  int() => v,
  String() => DateTime.parse(v).millisecondsSinceEpoch,
  null => 0,
  _ => throw ArgumentError('updated_at must be epoch ms or ISO-8601, got $v'),
};

bool _same(Row a, Row b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
