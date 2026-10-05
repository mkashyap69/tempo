import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart';

const _tables = [
  'minute_samples',
  'hr_live',
  'stress_samples',
  'spo2_samples',
  'band_workouts',
  'sleep_sessions',
  'daily_scores',
  'baselines',
  'journal',
  'sync_state',
  'workouts',
  'plan_days',
  'sync_log',
];

String _csv(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp('[,"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Writes one CSV per table into `<documents>/export-<timestamp>/`.
/// Settings are left out. The auth key is never in the DB.
Future<Directory> exportAll(TempoDb db) async {
  final docs = await getApplicationDocumentsDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final dir = await Directory('${docs.path}/export-$stamp')
      .create(recursive: true);
  for (final t in _tables) {
    final rows = await db.customSelect('SELECT * FROM $t').get();
    final sink = File('${dir.path}/$t.csv').openWrite();
    if (rows.isNotEmpty) {
      final cols = rows.first.data.keys.toList();
      sink.writeln(cols.join(','));
      for (final r in rows) {
        sink.writeln(cols.map((c) => _csv(r.data[c])).join(','));
      }
    }
    await sink.close();
  }
  return dir;
}

/// Deletes the database files. The app must restart afterwards.
Future<void> deleteDatabaseFiles() async {
  final docs = await getApplicationDocumentsDirectory();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('${docs.path}/tempo.sqlite$suffix');
    if (await f.exists()) await f.delete();
  }
}

/// One JSON file with every table except settings, for `Export → JSON`.
Future<File> exportAllJson(TempoDb db) async {
  final docs = await getApplicationDocumentsDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final out = <String, Object?>{
    'exported_at': DateTime.now().toIso8601String(),
  };
  for (final t in _tables) {
    out[t] = [
      for (final r in await db.customSelect('SELECT * FROM $t').get()) r.data,
    ];
  }
  final f = File('${docs.path}/tempo-export-$stamp.json');
  await f.writeAsString(jsonEncode(out));
  return f;
}

/// Restores a file written by [exportAllJson]. Rows already on this phone
/// win for raw samples; scores are recomputed from the restored minutes
/// afterwards. Throws [FormatException] for anything that isn't a Tempo
/// export. Returns rows written per table.
Future<Map<String, int>> restoreJson(TempoDb db, String json) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not a JSON file');
  }
  if (decoded is! Map<String, dynamic> || decoded['exported_at'] == null) {
    throw const FormatException('Not a Tempo export');
  }
  final data = <String, List<Map<String, Object?>>>{
    for (final t in TempoDb.restorable)
      if (decoded[t] is List)
        t: [
          for (final r in decoded[t] as List)
            if (r is Map) r.cast<String, Object?>(),
        ],
  };
  return db.restoreRows(data);
}
