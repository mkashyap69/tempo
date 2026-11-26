import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

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
}

String _title(String json) =>
    sc.Session.fromJson(jsonDecode(json) as Map<String, dynamic>).title;

/// The changes in [rows], newest day first. A row counts when its session
/// differs from its first version or it was skipped.
List<PlanChangeRow> planChanges(List<st.PlanDay> rows) {
  final out = <PlanChangeRow>[];
  for (final r in rows) {
    final skipped = r.status == sc.Intent.skipped.name;
    final changed = r.original != null && r.original != r.session;
    if (!changed && !skipped) continue;
    final reason = (r.reason ?? '').replaceFirst(RegExp(r'^·\s*'), '').trim();
    // Moves say "by you"; swaps, skips and later-today record the user (or
    // a notification button) as the status source. The morning adaptation
    // leaves the source alone, so anything else is the coach.
    final byYou =
        reason.contains('by you') ||
        r.statusSource == 'user' ||
        r.statusSource == 'notification';
    final atTs = changed ? r.adaptedAt : r.statusAt;
    out.add(
      PlanChangeRow(
        day: DateTime.parse(r.date),
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
      ),
    );
  }
  out.sort((a, b) => b.day.compareTo(a.day));
  return out;
}
