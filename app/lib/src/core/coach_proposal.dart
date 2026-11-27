import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'profile.dart' show Keys;

/// v3 interactive coach 2 (0.9.0): the morning adaptation asks first. What
/// it would change is kept as a proposal; Today shows it with Accept and
/// Keep my plan, and it applies itself at its deadline if unanswered.
const proposalKey = 'coach_proposal';

/// The latest a proposal waits before applying itself (minute of the day).
const proposalLatest = 17 * 60;

final class ProposalChange {
  const ProposalChange({
    required this.date,
    required this.from,
    required this.to,
    required this.reason,
  });
  final String date;

  /// Session JSON now and as proposed.
  final String from, to;
  final String reason;

  String get fromTitle => _title(from);
  String get toTitle => _title(to);

  Map<String, Object?> toJson() => {
    'date': date,
    'from': from,
    'to': to,
    'reason': reason,
  };
}

final class Proposal {
  const Proposal({
    required this.day,
    required this.deadline,
    required this.changes,
    this.carried = '',
  });

  /// The day it was made for (yyyy-mm-dd) and its deadline (minute).
  final String day;
  final int deadline;
  final List<ProposalChange> changes;

  /// The hard session the coach holds for a better morning, if accepted.
  final String carried;

  String get why {
    final r = changes.first.reason;
    return r.replaceFirst(RegExp(r'^[·▲■▼\s]+'), '').trim();
  }

  String toJson() => jsonEncode({
    'day': day,
    'deadline': deadline,
    'carried': carried,
    'changes': [for (final c in changes) c.toJson()],
  });

  static Proposal? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return Proposal(
        day: j['day'] as String,
        deadline: j['deadline'] as int,
        carried: j['carried'] as String? ?? '',
        changes: [
          for (final c in (j['changes'] as List).cast<Map<String, dynamic>>())
            ProposalChange(
              date: c['date'] as String,
              from: c['from'] as String,
              to: c['to'] as String,
              reason: c['reason'] as String,
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

String _title(String json) =>
    sc.Session.fromJson(jsonDecode(json) as Map<String, dynamic>).title;

/// When a proposal made at [nowMinute] applies itself: 30 minutes before
/// today's planned session, 17:00 at the latest, never within the hour.
int proposalDeadline({required int nowMinute, int? plannedMinute}) {
  var d = proposalLatest;
  if (plannedMinute != null && plannedMinute - 30 < d) d = plannedMinute - 30;
  return d < nowMinute + 60 ? nowMinute + 60 : d;
}

Future<Proposal?> loadProposal(st.TempoDb db) async =>
    Proposal.parse(await db.setting(proposalKey));

/// Writes [p]'s changes as the morning adaptation always has (each day
/// keeps its first version, one stamp for the lot so Undo restores them
/// together) and clears it. Returns the stamp.
Future<int> acceptProposal(st.TempoDb db, Proposal p, {DateTime? at}) async {
  final now = st.toTs(at ?? DateTime.now());
  for (final ch in p.changes) {
    final row = await db.planDay(DateTime.parse(ch.date));
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: ch.date,
        session: ch.to,
        original: Value(row?.original ?? row?.session ?? ch.from),
        reason: Value(ch.reason),
        adaptedAt: Value(now),
        general: row?.general ?? false,
        algoVersion: const Value(sc.coachDayAlgo),
      ),
    );
  }
  await db.putSetting(Keys.carried, p.carried);
  await db.deleteSetting(proposalKey);
  return now;
}

/// Keep my plan: nothing changes and nothing is held back.
Future<void> declineProposal(st.TempoDb db) async {
  await db.putSetting(Keys.carried, '');
  await db.deleteSetting(proposalKey);
}

/// Applies a proposal whose deadline has passed (or whose day is over).
/// Returns whether it applied one.
Future<bool> resolveProposal(st.TempoDb db, DateTime now) async {
  final p = await loadProposal(db);
  if (p == null) return false;
  final today = st.dateKey(DateTime(now.year, now.month, now.day));
  final late =
      p.day.compareTo(today) < 0 || now.hour * 60 + now.minute >= p.deadline;
  if (!late) return false;
  await acceptProposal(db, p, at: now);
  return true;
}
