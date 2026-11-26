import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'profile.dart' show Keys;

/// Who changed a planned day.
enum ChangeBy { coach, you }

/// One day whose plan differs from what was first planned, or that was
/// skipped (v3 Plan changes, docs/research/v3 UI.md). Derived from the
/// plan_days row: its first version, its current one and the last reason.
final class PlanChangeRow {
  const PlanChangeRow({
    required this.day,
    required this.from,
    required this.to,
    required this.why,
    required this.by,
    this.at,
    this.skipped = false,
    this.stamp,
    this.together = const [],
    this.canUndo = false,
  });

  final DateTime day;

  /// First planned and current session titles; [from] is null for a skip
  /// with no swap.
  final String? from;
  final String to;
  final String why;
  final ChangeBy by;
  final DateTime? at;
  final bool skipped;

  /// The change's `adaptedAt`: every day one change touched shares it (the
  /// morning adaptation, a move, a sore-day ease each write one stamp).
  /// Null for a skip.
  final int? stamp;

  /// The other days changed with this one.
  final List<DateTime> together;

  /// Every day of the change is today or later, so it can be undone.
  final bool canUndo;
}

String _title(String json) =>
    sc.Session.fromJson(jsonDecode(json) as Map<String, dynamic>).title;

bool _changed(st.PlanDay r) => r.original != null && r.original != r.session;

/// The changes in [rows], newest day first. A row counts when its session
/// differs from its first version or it was skipped. [today] decides what
/// can still be undone: a change whose days are all today or later.
List<PlanChangeRow> planChanges(List<st.PlanDay> rows, {DateTime? today}) {
  final groups = <int, List<DateTime>>{};
  for (final r in rows) {
    if (_changed(r) && r.adaptedAt != null) {
      (groups[r.adaptedAt!] ??= []).add(DateTime.parse(r.date));
    }
  }
  bool upcoming(DateTime d) => today != null && !d.isBefore(today);

  final out = <PlanChangeRow>[];
  for (final r in rows) {
    final skipped = r.status == sc.Intent.skipped.name;
    final changed = _changed(r);
    if (!changed && !skipped) continue;
    final day = DateTime.parse(r.date);
    final reason = (r.reason ?? '').replaceFirst(RegExp(r'^·\s*'), '').trim();
    // Moves say "by you"; swaps, skips and later-today record the user (or
    // a notification button) as the status source. The morning adaptation
    // leaves the source alone, so anything else is the coach.
    final byYou =
        reason.contains('by you') ||
        r.statusSource == 'user' ||
        r.statusSource == 'notification';
    final atTs = changed ? r.adaptedAt : r.statusAt;
    final group = changed && r.adaptedAt != null
        ? groups[r.adaptedAt!]!
        : <DateTime>[day];
    out.add(
      PlanChangeRow(
        day: day,
        from: changed ? _title(r.original!) : null,
        to: _title(r.session),
        why: reason.isNotEmpty
            ? reason
            : skipped
            ? 'Skipped.'
            : 'Changed to fit the week.',
        by: byYou ? ChangeBy.you : ChangeBy.coach,
        at: atTs == null ? null : st.fromTs(atTs),
        skipped: skipped,
        stamp: changed ? r.adaptedAt : null,
        together: [
          for (final d in group)
            if (d != day) d,
        ],
        canUndo: group.every(upcoming),
      ),
    );
  }
  out.sort((a, b) => b.day.compareTo(a.day));
  return out;
}

/// Puts every day of the change [stamp] back to its first plan and clears
/// its reason; those days are planned again. A hard session the morning
/// adaptation was holding back for a better day is dropped when the undo
/// puts it back in the week, so it can't come back twice. Returns the days
/// restored.
Future<List<DateTime>> undoPlanChange(st.TempoDb db, int stamp) async {
  final rows = await db.planBetween(DateTime(2000), DateTime(2100));
  final restored = <DateTime>[];
  final keys = <String>{};
  for (final r in rows) {
    if (r.adaptedAt != stamp || r.original == null) continue;
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: r.date,
        session: r.original!,
        original: const Value(null),
        reason: const Value(null),
        adaptedAt: const Value(null),
        general: r.general,
        algoVersion: Value(r.algoVersion),
      ),
    );
    final day = DateTime.parse(r.date);
    await db.setPlanIntent(day, sc.Intent.planned.name, source: 'user');
    restored.add(day);
    keys.add(
      sc.Session.fromJson(jsonDecode(r.original!) as Map<String, dynamic>).key,
    );
  }
  final carried = await db.setting(Keys.carried);
  if (carried != null && carried.isNotEmpty) {
    final k = sc.Session.fromJson(jsonDecode(carried) as Map<String, dynamic>)
        .key;
    if (keys.contains(k)) await db.putSetting(Keys.carried, '');
  }
  return restored;
}

/// Plans a skipped [day] again.
Future<void> undoSkip(st.TempoDb db, DateTime day) =>
    db.setPlanIntent(day, sc.Intent.planned.name, source: 'user');
