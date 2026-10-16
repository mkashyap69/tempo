import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'data_source.dart';
import 'minutes.dart';
import 'profile.dart';

/// Journal v2 (decisions.md, 2026-10-16): which entries the user tracks,
/// their own entries, check-in state and the automatic entries.

/// The user's own entries, as {key, name}.
final class JournalConfig {
  const JournalConfig(this.enabled, this.custom);

  /// Keys switched on, in catalogue order then custom order.
  final List<String> enabled;
  final List<sc.JournalEntryDef> custom;

  sc.JournalEntryDef? def(String key) =>
      sc.journalByKey[key] ?? custom.where((c) => c.key == key).firstOrNull;

  /// Entries asked in the check-in (automatic ones are never asked).
  List<sc.JournalEntryDef> get asked => [
    for (final k in enabled)
      if (def(k) case final d? when !d.automatic) d,
  ];

  /// Automatic entries switched on.
  List<sc.JournalEntryDef> get automatic => [
    for (final k in enabled)
      if (def(k) case final d? when d.automatic) d,
  ];

  /// Every entry, catalogue first, for the Customise screen.
  List<sc.JournalEntryDef> get all => [...sc.journalCatalog, ...custom];
}

/// Automatic entries are on unless switched off.
const _defaultEnabled = [
  ...sc.defaultJournalKeys,
  'auto_steps',
  'auto_brisk',
  'auto_zone2',
  'auto_strength',
  'auto_late_workout',
  'auto_nap',
  'auto_late_bed',
  'auto_high_strain',
];

Future<JournalConfig> loadJournalConfig(st.TempoDb db) async {
  List<String> enabled = _defaultEnabled;
  final custom = <sc.JournalEntryDef>[];
  try {
    final raw = await db.setting(Keys.journalEntries);
    if (raw != null && raw.isNotEmpty) {
      enabled = (jsonDecode(raw) as List).cast<String>();
    }
  } catch (_) {}
  try {
    final raw = await db.setting(Keys.journalCustom);
    if (raw != null && raw.isNotEmpty) {
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        custom.add(sc.customEntry(m['key'] as String, m['name'] as String));
      }
    }
  } catch (_) {}
  final known = {...sc.journalByKey.keys, for (final c in custom) c.key};
  final order = [
    for (final e in sc.journalCatalog) e.key,
    for (final c in custom) c.key,
  ];
  final on = {
    for (final k in enabled)
      if (known.contains(k)) k,
  };
  return JournalConfig([
    for (final k in order)
      if (on.contains(k)) k,
  ], custom);
}

Future<void> setEntryEnabled(st.TempoDb db, String key, bool on) async {
  final c = await loadJournalConfig(db);
  final next = [
    for (final k in c.enabled)
      if (k != key) k,
    if (on) key,
  ];
  await db.putSetting(Keys.journalEntries, jsonEncode(next));
}

/// Adds a yes/no entry of the user's own and switches it on. Returns its
/// key; an existing entry with the same key is reused.
Future<String> addCustomEntry(st.TempoDb db, String name) async {
  final c = await loadJournalConfig(db);
  final key = sc.customKey(name.trim());
  if (!c.custom.any((e) => e.key == key)) {
    await db.putSetting(
      Keys.journalCustom,
      jsonEncode([
        for (final e in c.custom) {'key': e.key, 'name': e.name},
        {'key': key, 'name': name.trim()},
      ]),
    );
  }
  await setEntryEnabled(db, key, true);
  return key;
}

/// A check-in was saved for [day]. Days from before Journal v2 have no
/// marker, so any answered entry counts too.
Future<bool> journalCheckedIn(st.TempoDb db, DateTime day) async {
  final rows = await db.journalFor(day);
  return rows.any((r) => !r.tag.startsWith('auto_'));
}

/// Saves a check-in for [day]: yes/no answers, amounts and times, plus the
/// marker. Amounts and times set to null are cleared.
Future<void> saveCheckin(
  st.TempoDb db,
  DateTime day,
  JournalConfig config, {
  required Map<String, bool> answers,
  required Map<String, double?> amounts,
}) async {
  for (final e in answers.entries) {
    await db.setJournal(day, e.key, e.value);
  }
  for (final e in amounts.entries) {
    final d = config.def(e.key);
    if (e.value == null) {
      await db.clearJournal(day, e.key);
    } else {
      await db.setJournal(
        day,
        e.key,
        d?.kind == sc.EntryKind.time || e.value! > 0,
        amount: e.value,
      );
    }
  }
  await db.setJournal(day, sc.checkinTag, true);
}

/// What the data says about [day], for the automatic entries.
Future<sc.AutoFacts> autoFactsFor(
  st.TempoDb db,
  DateTime day, {
  Profile? profile,
}) async {
  final d = dayOf(day);
  final end = d.add(const Duration(days: 1));
  final p = profile ?? await loadAppProfile(db) ?? const Profile();
  final source = await loadDataSource(db);
  final mins = (await loadMinutes(db, d, end, source: source)).minutes;
  final hasSteps = mins.any((m) => m.steps > 0);
  final hasHr = mins.any((m) => m.hr != null);
  final z2 = (p.effectiveMaxHr * .6).round();
  final score = await db.scoreFor(d);
  final night = await db.scoreFor(end);
  final workouts = await db.workoutsBetween(d, end);
  final real = [
    for (final w in workouts)
      if (w.source != 'auto' || w.confirmed) w,
  ];
  final usual = <int>[
    for (final s in await db.scoresBetween(
      end.subtract(const Duration(days: 15)),
      d,
    ))
      if (s.sleepStart != null) sc.minutesAfterNoon(st.fromTs(s.sleepStart!)),
  ]..sort();
  final sleepStart = night?.sleepStart == null
      ? null
      : st.fromTs(night!.sleepStart!);
  return sc.AutoFacts(
    steps: hasSteps ? mins.fold<int>(0, (a, m) => a + m.steps) : null,
    stepTarget: p.age >= 60 ? 6000 : 8000,
    briskMinutes: hasSteps ? sc.briskMinutes(mins) : null,
    zone2Minutes: hasHr
        ? mins.where((m) => m.hr != null && m.hr! >= z2).length
        : null,
    strengthDone: real.any((w) => w.sport == sc.Sport.strength.name),
    lastWorkoutEnd: real.isEmpty
        ? null
        : real
              .map((w) => st.fromTs(w.end))
              .reduce((a, b) => a.isAfter(b) ? a : b),
    sleepStart: sleepStart,
    napMinutes: score == null ? null : (score.napHours * 60).round(),
    bedMinute: sleepStart == null ? null : sc.minutesAfterNoon(sleepStart),
    usualBedMinute: usual.length < 5 ? null : usual[usual.length ~/ 2],
    strain: score?.strain,
  );
}

/// Automatic entries for [day] that the user has switched on.
Future<Map<String, bool>> autoEntriesFor(
  st.TempoDb db,
  DateTime day,
  JournalConfig config,
) async {
  final on = {for (final d in config.automatic) d.key};
  if (on.isEmpty) return const {};
  final all = sc.autoEntries(await autoFactsFor(db, day));
  return {
    for (final e in all.entries)
      if (on.contains(e.key)) e.key: e.value,
  };
}
