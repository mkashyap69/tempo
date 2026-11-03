import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'block_service.dart' show weekCredits;
import 'coach_service.dart' show dayOf, mondayOf;
import 'profile.dart' show Keys;

/// Why a session is moved or skipped, picked in the Move or skip sheet.
/// The reason changes what the sheet suggests and what the coach says.
enum SkipReason { tired, sore, busy, ill, travel, notToday }

/// Stored reasons are kept this many days.
const _keepDays = 21;

String skipReasonLabel(SkipReason r) => switch (r) {
  SkipReason.tired => 'Tired',
  SkipReason.sore => 'Sore',
  SkipReason.busy => 'Busy',
  SkipReason.ill => 'Ill',
  SkipReason.travel => 'Travelling',
  SkipReason.notToday => 'Not feeling it',
};

/// The coach's note in the sheet, for [r] (null: nothing picked yet).
String skipReasonNote(SkipReason? r) => switch (r) {
  null =>
    'Missing one is fine. Moving keeps the week’s work; skipping lets it '
        'go, and nothing is owed.',
  SkipReason.tired =>
    'Tired is worth listening to. Move it to a fresher day, or skip it: '
        'an easy walk today still counts.',
  SkipReason.sore =>
    'Soreness is the body still adapting. Skip it and Tempo can ease the '
        'hard sessions left this week, so it can catch up.',
  SkipReason.busy =>
    'Busy days happen. Move it to a day with room; Tempo keeps hard days '
        'apart.',
  SkipReason.ill =>
    'Rest is the training today. Pausing the plan keeps your baselines '
        'clean and nothing counts as missed.',
  SkipReason.travel =>
    'Travel throws off sleep and heart rate. Pause the plan while you’re '
        'away, or move the session to a day you’re home.',
  SkipReason.notToday =>
    'Some days aren’t the day. Skip it; one session doesn’t change the '
        'week.',
};

/// The short line under a skipped session.
String skippedLine(SkipReason? r) => switch (r) {
  null => 'Skipped. Nothing to make up.',
  SkipReason.sore => 'Skipped · sore. Recover; nothing to make up.',
  SkipReason.tired => 'Skipped · tired. Sleep is the session today.',
  _ => 'Skipped · ${skipReasonLabel(r).toLowerCase()}. Nothing to make up.',
};

Future<Map<String, String>> _all(st.TempoDb db) async {
  final raw = await db.setting(Keys.skipReasons);
  if (raw == null || raw.isEmpty) return {};
  try {
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  } on Object {
    return {};
  }
}

/// The reason given for [day], if any.
Future<SkipReason?> loadSkipReason(st.TempoDb db, DateTime day) async =>
    SkipReason.values.asNameMap()[(await _all(db))[st.dateKey(day)]];

/// Stores [r] for [day] (null clears it); old entries are dropped.
Future<void> saveSkipReason(st.TempoDb db, DateTime day, SkipReason? r) async {
  final all = await _all(db);
  final key = st.dateKey(day);
  if (r == null) {
    all.remove(key);
  } else {
    all[key] = r.name;
  }
  final cut = st.dateKey(
    dayOf(DateTime.now()).subtract(const Duration(days: _keepDays)),
  );
  all.removeWhere((k, _) => k.compareTo(cut) < 0);
  await db.putSetting(Keys.skipReasons, jsonEncode(all));
}

/// Eases the rest of [day]'s week after it (hard sessions become their
/// easier version, long ones lose a quarter). Returns the days changed,
/// as weekday indexes (0 = Monday); empty when nothing was hard.
Future<List<int>> easeRestOfWeek(st.TempoDb db, DateTime day) async {
  final days = await weekCredits(db, mondayOf(day));
  if (days.length != 7) return const [];
  final r = sc.easeRest([for (final d in days) d.session], day.weekday);
  if (r.changed.isEmpty) return const [];
  final rows = await db.planBetween(days.first.date, days.last.date);
  final stamp = st.toTs(DateTime.now());
  for (final i in r.changed) {
    final row = rows.where((x) => x.date == st.dateKey(days[i].date)).first;
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: row.date,
        session: jsonEncode(r.week[i].toJson()),
        original: Value(row.original ?? row.session),
        reason: Value('■ Easier: you were sore on ${_day(day)}.'),
        adaptedAt: Value(stamp),
        general: row.general,
        algoVersion: const Value(sc.blockAlgo),
      ),
    );
  }
  return r.changed;
}

String _day(DateTime d) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][d.weekday - 1];
