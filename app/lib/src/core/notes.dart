import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'profile.dart';

/// Workout notes and reflections (D3, decisions.md 2026-11-24). User
/// input kept in one setting, so backups and export carry it.
///
/// - A routine note belongs to a saved routine and shows each time you
///   start it.
/// - A session note belongs to one day's strength session only.
/// - An exercise note is pinned to the exercise and shows wherever it
///   appears.
/// - A reflection belongs to one workout (any kind): tags and words.
enum NoteScope { routine, exercise, session }

Future<Map<String, dynamic>> _all(st.TempoDb db) async {
  final raw = await db.setting(Keys.workoutNotes);
  if (raw == null || raw.isEmpty) return {};
  try {
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}

Future<void> _save(st.TempoDb db, Map<String, dynamic> all) =>
    db.putSetting(Keys.workoutNotes, jsonEncode(all));

/// The note for [scope] and [ref] (routine name, exercise id, or a day's
/// date key), or null.
Future<String?> loadNote(st.TempoDb db, NoteScope scope, String ref) async {
  final m = (await _all(db))[scope.name];
  final v = m is Map ? m[ref] : null;
  return v is String && v.trim().isNotEmpty ? v : null;
}

/// Saves the note; an empty one removes it.
Future<void> saveNote(
  st.TempoDb db,
  NoteScope scope,
  String ref,
  String text,
) async {
  final all = await _all(db);
  final m = ((all[scope.name] as Map?) ?? {}).cast<String, dynamic>();
  if (text.trim().isEmpty) {
    m.remove(ref);
  } else {
    m[ref] = text.trim();
  }
  all[scope.name] = m;
  await _save(db, all);
}

String sessionRef(DateTime day) => st.dateKey(day);

/// Every reflection, oldest first.
Future<List<sc.Reflection>> loadReflections(st.TempoDb db) async {
  final m = (await _all(db))['reflect'];
  if (m is! Map) return const [];
  final out = <sc.Reflection>[];
  for (final e in m.entries) {
    final ms = int.tryParse('${e.key}');
    final v = e.value;
    if (ms == null || v is! Map) continue;
    out.add(
      sc.Reflection(
        at: DateTime.fromMillisecondsSinceEpoch(ms),
        title: (v['title'] as String?) ?? '',
        text: (v['t'] as String?) ?? '',
        tags: {
          for (final t in (v['tags'] as List? ?? const []))
            ?sc.ReflectTag.values.asNameMap()[t],
        },
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

Future<sc.Reflection?> loadReflection(st.TempoDb db, DateTime start) async {
  final ms = start.millisecondsSinceEpoch;
  for (final r in await loadReflections(db)) {
    if (r.at.millisecondsSinceEpoch == ms) return r;
  }
  return null;
}

/// Saves [r] for its workout; an empty one removes it.
Future<void> saveReflection(st.TempoDb db, sc.Reflection r) async {
  final all = await _all(db);
  final m = ((all['reflect'] as Map?) ?? {}).cast<String, dynamic>();
  final k = '${r.at.millisecondsSinceEpoch}';
  if (r.isEmpty) {
    m.remove(k);
  } else {
    m[k] = {
      'title': r.title,
      't': r.text.trim(),
      'tags': [for (final t in r.tags) t.name],
    };
  }
  all['reflect'] = m;
  await _save(db, all);
}

/// Workout start times whose sore or pain reflection was already answered.
Future<Set<DateTime>> loadHandled(st.TempoDb db) async => {
  for (final x in ((await _all(db))['handled'] as List? ?? const []))
    if (x is int) DateTime.fromMillisecondsSinceEpoch(x),
};

Future<void> markHandled(st.TempoDb db, DateTime start) async {
  final all = await _all(db);
  final h = [
    ...((all['handled'] as List?) ?? const []),
    start.millisecondsSinceEpoch,
  ];
  all['handled'] = h.length > 50 ? h.sublist(h.length - 50) : h;
  await _save(db, all);
}

/// What Today offers after a sore or pain reflection, or null.
Future<sc.ReflectCall?> loadReflectCall(st.TempoDb db, {DateTime? now}) async =>
    sc.reflectCall(
      await loadReflections(db),
      now ?? DateTime.now(),
      handled: await loadHandled(db),
    );
