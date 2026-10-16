import 'dart:convert';
import 'dart:math' as math;

import 'package:health_source/health_source.dart' as hs;

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

// ---- impact (J2) ------------------------------------------------------------

/// How an entry is coded for the impact engine. Times are hours (after
/// noon for evening entries, so 23:30 and 00:30 sit an hour apart).
sc.Behaviour behaviourFor(sc.JournalEntryDef d) => switch (d.kind) {
  sc.EntryKind.yesNo => sc.Behaviour(d.key),
  sc.EntryKind.amount => sc.Behaviour(
    d.key,
    binary: false,
    dose: switch (d.key) {
      'caffeine_mg' => 100,
      'water' => 500,
      _ => 1,
    },
  ),
  sc.EntryKind.time => sc.Behaviour(d.key, binary: false),
};

/// "per 100 mg", "per hour later", "" for yes/no.
String doseWords(sc.JournalEntryDef d) => switch (d.kind) {
  sc.EntryKind.yesNo => '',
  sc.EntryKind.time => ' per hour later',
  sc.EntryKind.amount =>
    ' per ${behaviourFor(d).dose.round()} ${d.unit ?? ''}'.trimRight(),
};

double? _code(sc.JournalEntryDef d, st.JournalData r) => switch (d.kind) {
  sc.EntryKind.yesNo => r.value ? 1 : 0,
  sc.EntryKind.amount => r.amount ?? (r.value ? null : 0),
  sc.EntryKind.time =>
    r.amount == null
        ? null
        : d.key == 'first_meal'
        ? r.amount! / 60
        : ((r.amount! - 12 * 60) % 1440) / 60,
};

/// Days in [from, to] with their entries (manual and automatic) and the
/// night and morning that followed.
Future<List<sc.ImpactDay>> loadImpactDays(
  st.TempoDb db,
  JournalConfig config, {
  required DateTime from,
  required DateTime to,
}) async {
  final rows = await db.journalBetween(from, to);
  final byDate = <String, List<st.JournalData>>{};
  for (final r in rows) {
    byDate.putIfAbsent(r.date, () => []).add(r);
  }
  final scores = {
    for (final s in await db.scoresBetween(
      from,
      to.add(const Duration(days: 1)),
    ))
      s.date: s,
  };
  final autoOn = config.automatic.isNotEmpty;
  final profile = await loadAppProfile(db) ?? const Profile();
  final out = <sc.ImpactDay>[];
  for (
    var d = dayOf(from);
    !d.isAfter(to);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = scores[st.dateKey(d.add(const Duration(days: 1)))];
    if (next == null) continue;
    final y = <sc.Outcome, double>{
      if (next.recovery != null && !next.calibrating)
        sc.Outcome.recovery: next.recovery!,
      if (next.sleepPerf != null) sc.Outcome.sleepPerf: next.sleepPerf!,
      if (next.hrv != null && next.hrv! > 0)
        sc.Outcome.hrv: math.log(next.hrv!),
      if (next.rhr != null) sc.Outcome.rhr: next.rhr!,
      if (next.sleptHours != null) sc.Outcome.sleptHours: next.sleptHours!,
    };
    if (y.isEmpty) continue;
    final x = <String, double>{};
    for (final r in byDate[st.dateKey(d)] ?? const <st.JournalData>[]) {
      final def = config.def(r.tag);
      if (def == null || def.automatic) continue;
      final v = _code(def, r);
      if (v != null) x[r.tag] = v;
    }
    if (autoOn) {
      final auto = sc.autoEntries(await autoFactsFor(db, d, profile: profile));
      for (final a in config.automatic) {
        if (auto[a.key] case final v?) x[a.key] = v ? 1 : 0;
      }
    }
    out.add(
      sc.ImpactDay(
        date: d,
        x: x,
        y: y,
        strain: scores[st.dateKey(d)]?.strain,
        weekend: d.add(const Duration(days: 1)).weekday >= 6,
      ),
    );
  }
  return out;
}

// ---- experiments --------------------------------------------------------------

sc.Experiment? _parseExperiment(Map<String, dynamic> j) {
  try {
    return sc.Experiment(
      key: j['key'] as String,
      doIt: j['doIt'] as bool,
      start: DateTime.parse(j['start'] as String),
      days: j['days'] as int? ?? 14,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _experimentJson(sc.Experiment e) => {
  'key': e.key,
  'doIt': e.doIt,
  'start': st.dateKey(e.start),
  'days': e.days,
};

/// The running experiment, or null.
Future<sc.Experiment?> loadExperiment(st.TempoDb db) async {
  final raw = await db.setting(Keys.experiment);
  if (raw == null || raw.isEmpty) return null;
  try {
    return _parseExperiment(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Finished or stopped experiments, newest first.
Future<List<sc.Experiment>> loadPastExperiments(st.TempoDb db) async {
  try {
    final raw = await db.setting(Keys.experimentsDone);
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        ?_parseExperiment(m),
    ]..sort((a, b) => b.start.compareTo(a.start));
  } catch (_) {
    return const [];
  }
}

/// Starts a 14-day experiment from today; one runs at a time.
Future<void> startExperiment(st.TempoDb db, String key, bool doIt) async {
  await stopExperiment(db);
  await db.putSetting(
    Keys.experiment,
    jsonEncode(
      _experimentJson(
        sc.Experiment(key: key, doIt: doIt, start: dayOf(DateTime.now())),
      ),
    ),
  );
}

/// Moves the running experiment to the past list (cut short at today
/// when stopped early, so its result only counts the days it ran).
Future<void> stopExperiment(st.TempoDb db) async {
  final e = await loadExperiment(db);
  if (e == null) return;
  final today = dayOf(DateTime.now());
  final ran = today.difference(e.start).inDays.clamp(0, e.days);
  final past = await loadPastExperiments(db);
  await db.putSetting(
    Keys.experimentsDone,
    jsonEncode([
      if (ran > 0)
        _experimentJson(
          sc.Experiment(key: e.key, doIt: e.doIt, start: e.start, days: ran),
        ),
      for (final p in past) _experimentJson(p),
    ]),
  );
  await db.deleteSetting(Keys.experiment);
}

/// Ends the running experiment once its days are up (on load).
Future<sc.Experiment?> currentExperiment(st.TempoDb db) async {
  final e = await loadExperiment(db);
  if (e != null && !dayOf(DateTime.now()).isBefore(e.end)) {
    await stopExperiment(db);
    return null;
  }
  return e;
}

/// Water and caffeine Health recorded on [day], in the journal's units
/// (ml, mg), for the check-in to suggest. Empty off Health.
Future<Map<String, double>> healthAmountsFor(
  st.TempoDb db,
  DateTime day,
) async {
  final source = await loadDataSource(db);
  if (!source.isHealth) return const {};
  final d = dayOf(day);
  final recs = await loadHealthRecords(
    db,
    d,
    d.add(const Duration(days: 1)),
    kinds: const [hs.HealthKind.water, hs.HealthKind.caffeine],
  );
  double sum(hs.HealthKind k) => recs
      .where((r) => r.kind == k && !r.start.isBefore(d))
      .fold<double>(0, (a, r) => a + r.value);
  final water = sum(hs.HealthKind.water) * 1000; // L → ml
  final caffeine = sum(hs.HealthKind.caffeine) * 1000; // g → mg
  return {
    if (water > 0) 'water': water.roundToDouble(),
    if (caffeine > 0) 'caffeine_mg': caffeine.roundToDouble(),
  };
}
