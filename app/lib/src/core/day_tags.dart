import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'profile.dart';
import 'sleep_coach.dart' show loadSleepPlan, tickHabit;

/// Days of quick tags kept for the timeline.
const _keepDays = 14;

Future<Map<String, List<List<Object>>>> _all(st.TempoDb db) async {
  final raw = await db.setting(Keys.dayTags);
  if (raw == null || raw.isEmpty) return {};
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in j.entries)
        e.key: [for (final x in e.value as List) (x as List).cast<Object>()],
    };
  } on Object {
    return {};
  }
}

Future<void> _save(st.TempoDb db, Map<String, List<List<Object>>> all) async {
  final cut = st.dateKey(
    dayOf(DateTime.now()).subtract(const Duration(days: _keepDays)),
  );
  all.removeWhere((k, _) => k.compareTo(cut) < 0);
  await db.putSetting(Keys.dayTags, jsonEncode(all));
}

/// The quick tags on [day], in the order they were added.
Future<List<(sc.QuickTag, int)>> loadDayTags(
  st.TempoDb db,
  DateTime day,
) async => [
  for (final x in (await _all(db))[st.dateKey(day)] ?? const <List<Object>>[])
    if (sc.QuickTag.values.asNameMap()[x[0]] case final t?) (t, x[1] as int),
];

/// Tags [tag] at [at]: writes the Journal entries it means for that day and
/// keeps it for the timeline. Daylight also ticks a running sleep plan's
/// morning-light habit. Returns an undo that puts every touched entry back.
Future<Future<void> Function()> addQuickTag(
  st.TempoDb db,
  sc.QuickTag tag,
  DateTime at, {
  required int bedtime,
}) async {
  final day = dayOf(at);
  final before = {for (final j in await db.journalFor(day)) j.tag: j};
  final entries = sc.quickTagEntries(
    tag,
    at.hour * 60 + at.minute,
    amounts: {for (final e in before.entries) e.key: e.value.amount},
    bedtime: bedtime,
  );
  for (final e in entries) {
    await db.setJournal(day, e.key, e.value, amount: e.amount);
  }
  final all = await _all(db);
  final k = st.dateKey(day);
  final mark = <Object>[tag.name, at.hour * 60 + at.minute];
  (all[k] ??= []).add(mark);
  await _save(db, all);
  final plan = tag == sc.QuickTag.daylight ? await loadSleepPlan(db) : null;
  final ticked = plan != null && plan.today.any((h) => h.habit.id == 'light');
  if (ticked) await tickHabit(db, day, 'light', true);

  return () async {
    for (final e in entries) {
      final b = before[e.key];
      if (b == null) {
        await db.clearJournal(day, e.key);
      } else {
        await db.setJournal(day, e.key, b.value, amount: b.amount);
      }
    }
    final now = await _all(db);
    final list = now[k];
    if (list != null) {
      final i = list.lastIndexWhere((x) => x[0] == mark[0] && x[1] == mark[1]);
      if (i >= 0) list.removeAt(i);
      await _save(db, now);
    }
    if (ticked) await tickHabit(db, day, 'light', false);
  };
}
