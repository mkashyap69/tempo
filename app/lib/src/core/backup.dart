import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart';

import 'band_link.dart' show deviceIdKey, deviceNameKey;
import 'export.dart' show restoreJson;
import 'health_sync.dart' show rebuildHealthMinutes;
import 'minutes.dart' show firstDataMinute;
import 'profile.dart' show Keys;
import 'score_service.dart';

/// Backups: one gzipped JSON file per backup with every restorable table
/// and the user's settings, written after a sync at most every
/// [backupEvery] into a folder. The default folder is Tempo's own
/// (Files → On My iPhone → Tempo → Backups), which survives updates but not
/// deleting the app; the user can pick any other folder (iCloud Drive, a
/// folder outside Tempo), which Tempo remembers in the keychain so a
/// reinstall can find it again.

const backupPrefix = 'tempo-backup-';
const backupExt = '.json.gz';
const backupFormat = 'tempo-backup';
const backupEvery = Duration(hours: 12);

/// Backups kept per folder; older ones are deleted after a new one.
const keepBackups = 7;

/// Settings that describe this phone or a moment, not the user: never
/// backed up. The band id is left out because its auth key may not come
/// back with it (Android); pairing again is quick.
const _notBackedUp = {
  Keys.firmware,
  Keys.battery,
  Keys.batteryAt,
  Keys.lastSync,
  Keys.lastAttempt,
  Keys.lastError,
  Keys.notifScheduled,
  Keys.bandConfigured,
  Keys.stepsNow,
  Keys.lastCharge,
  Keys.rangeHaptic,
  Keys.batteryPrompted,
  Keys.healthExportedTo,
  Keys.lastBackup,
  Keys.healthDeepRead,
  deviceIdKey,
  deviceNameKey,
};

bool backedUpSetting(String key) => !_notBackedUp.contains(key);

/// One backup file in a folder.
final class BackupEntry {
  const BackupEntry(this.name, {this.size, this.modified});
  final String name;
  final int? size;
  final DateTime? modified;

  /// When the backup was made, from its name (`tempo-backup-<ISO>.json.gz`,
  /// colons as dashes), else the file date.
  DateTime? get madeAt {
    final m = RegExp(r'(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})')
        .firstMatch(name);
    if (m == null) return modified;
    return DateTime.tryParse('${m[1]}T${m[2]}:${m[3]}:${m[4]}') ?? modified;
  }

  bool get isBackup =>
      name.startsWith(backupPrefix) && name.endsWith(backupExt);
}

/// Somewhere backups live.
abstract interface class BackupLocation {
  /// Shown to the user, e.g. "Tempo (on this iPhone)" or "iCloud Drive/…".
  String get label;

  /// Whether deleting the app deletes this folder too.
  bool get goesWithApp;

  Future<List<BackupEntry>> list();
  Future<List<int>> read(String name);
  Future<void> write(String name, List<int> bytes);
  Future<void> delete(String name);
}

/// A plain directory: the default `<Documents>/Backups`, and tests.
final class DirectoryLocation implements BackupLocation {
  DirectoryLocation(this.dir, {required this.label, this.goesWithApp = true});
  final Directory dir;
  @override
  final String label;
  @override
  final bool goesWithApp;

  static Future<DirectoryLocation> appDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    return DirectoryLocation(
      Directory('${docs.path}/Backups'),
      label: Platform.isIOS
          ? 'On My iPhone › Tempo › Backups'
          : 'Tempo’s app storage › Backups',
    );
  }

  @override
  Future<List<BackupEntry>> list() async {
    if (!await dir.exists()) return const [];
    return [
      for (final f in dir.listSync().whereType<File>())
        BackupEntry(
          f.uri.pathSegments.last,
          size: f.lengthSync(),
          modified: f.lastModifiedSync(),
        ),
    ];
  }

  @override
  Future<List<int>> read(String name) =>
      File('${dir.path}/$name').readAsBytes();

  @override
  Future<void> write(String name, List<int> bytes) async {
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/.$name.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${dir.path}/$name');
  }

  @override
  Future<void> delete(String name) async {
    final f = File('${dir.path}/$name');
    if (await f.exists()) await f.delete();
  }
}

/// A folder the user picked in the system picker. [token] is a
/// security-scoped bookmark (iOS) or a persisted tree URI (Android), kept
/// by the native side of `tempo/backup_folder`. TODO(verify) on device:
/// neither native side can be built in CI here.
final class PickedFolderLocation implements BackupLocation {
  PickedFolderLocation(this.token, this.name);
  final String token, name;
  static const channel = MethodChannel('tempo/backup_folder');

  @override
  String get label => name;
  @override
  bool get goesWithApp => false;

  /// Opens the system folder picker; null if cancelled.
  static Future<PickedFolderLocation?> pick() async {
    final r = await channel.invokeMapMethod<String, Object?>('pick');
    if (r == null) return null;
    return PickedFolderLocation(r['token']! as String, r['name']! as String);
  }

  @override
  Future<List<BackupEntry>> list() async {
    final r =
        await channel.invokeListMethod<Map<Object?, Object?>>('list', {
          'token': token,
        }) ??
        const [];
    return [
      for (final e in r)
        BackupEntry(
          e['name']! as String,
          size: e['size'] as int?,
          modified: e['modified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(e['modified']! as int),
        ),
    ];
  }

  @override
  Future<List<int>> read(String name) async => (await channel
      .invokeMethod<Uint8List>('read', {'token': token, 'name': name}))!;

  @override
  Future<void> write(String name, List<int> bytes) =>
      channel.invokeMethod<void>('write', {
        'token': token,
        'name': name,
        'bytes': Uint8List.fromList(bytes),
      });

  @override
  Future<void> delete(String name) =>
      channel.invokeMethod<void>('delete', {'token': token, 'name': name});
}

/// The picked folder survives deleting the app on iOS because its token is
/// in the keychain, not the database.
class BackupFolderStore {
  BackupFolderStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage _s;
  static const _token = 'backup_folder_token', _name = 'backup_folder_name';

  Future<PickedFolderLocation?> load() async {
    final t = await _s.read(key: _token), n = await _s.read(key: _name);
    return t == null || n == null ? null : PickedFolderLocation(t, n);
  }

  Future<void> save(PickedFolderLocation f) async {
    await _s.write(key: _token, value: f.token);
    await _s.write(key: _name, value: f.name);
  }

  Future<void> clear() async {
    await _s.delete(key: _token);
    await _s.delete(key: _name);
  }
}

/// Everything restorable, plus settings, as gzipped JSON.
Future<List<int>> buildBackup(TempoDb db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final out = <String, Object?>{
    'format': backupFormat,
    'version': 1,
    'schema': db.schemaVersion,
    'exported_at': at.toIso8601String(),
  };
  for (final t in TempoDb.restorable) {
    out[t] = [
      for (final r in await db.customSelect('SELECT * FROM $t').get()) r.data,
    ];
  }
  out['settings'] = {
    for (final r
        in await db.customSelect('SELECT key, value FROM settings').get())
      if (backedUpSetting(r.read<String>('key')))
        r.read<String>('key'): r.read<String>('value'),
  };
  return gzip.encode(utf8.encode(jsonEncode(out)));
}

/// What a restore brought in.
final class RestoreResult {
  const RestoreResult(this.rows, this.settings);
  final Map<String, int> rows;
  final int settings;
  int get minutes => rows['minute_samples'] ?? 0;
  int get workouts => rows['workouts'] ?? 0;
}

/// Restores a backup ([buildBackup]) or a plain JSON export, gzipped or
/// not. Raw rows already here are kept; settings already here win too.
/// Scores are recomputed afterwards.
Future<RestoreResult> restoreBackup(TempoDb db, List<int> bytes) async {
  List<int> raw = bytes;
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    try {
      raw = gzip.decode(bytes);
    } catch (_) {
      throw const FormatException('Damaged backup file');
    }
  }
  final String text;
  try {
    text = utf8.decode(raw);
  } catch (_) {
    throw const FormatException('Not a Tempo backup');
  }
  final rows = await restoreJson(db, text);
  var settings = 0;
  final decoded = jsonDecode(text);
  if (decoded is Map && decoded['settings'] is Map) {
    for (final e in (decoded['settings'] as Map).entries) {
      final k = e.key, v = e.value;
      if (k is! String || v is! String || !backedUpSetting(k)) continue;
      if (await db.setting(k) != null) continue;
      await db.putSetting(k, v);
      settings++;
    }
  }
  // Health minutes are derived, so they are rebuilt, not restored.
  final span = await db.healthRecordSpan();
  if (span != null) await rebuildHealthMinutes(db, span.$1, DateTime.now());
  final first = await firstDataMinute(db);
  if (first != null) await ScoreService(db).recomputeFrom(first);
  return RestoreResult(rows, settings);
}

/// A backup found somewhere, for the restore list.
final class FoundBackup {
  const FoundBackup(this.location, this.entry);
  final BackupLocation location;
  final BackupEntry entry;
}

/// Writes, prunes and finds backups.
class BackupService {
  BackupService(this.db, {BackupFolderStore? folders, this.defaultFolder})
    : folders = folders ?? BackupFolderStore();
  final TempoDb db;
  final BackupFolderStore folders;

  /// Overrides `<Documents>/Backups` (tests).
  final BackupLocation? defaultFolder;

  Future<BackupLocation> _default() async =>
      defaultFolder ?? await DirectoryLocation.appDefault();

  /// Where new backups go: the picked folder, else the default.
  Future<BackupLocation> current() async {
    PickedFolderLocation? picked;
    try {
      picked = await folders.load();
    } catch (_) {} // no keychain (tests): the default folder
    return picked ?? await _default();
  }

  /// Makes a backup now and keeps the newest [keepBackups].
  Future<BackupEntry> backupNow({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final loc = await current();
    final stamp = at.toIso8601String().split('.').first.replaceAll(':', '-');
    final name = '$backupPrefix$stamp$backupExt';
    final bytes = await buildBackup(db, now: at);
    await loc.write(name, bytes);
    final all = [
      for (final e in await loc.list())
        if (e.isBackup) e,
    ]..sort((a, b) => b.name.compareTo(a.name));
    for (final old in all.skip(keepBackups)) {
      try {
        await loc.delete(old.name);
      } catch (_) {}
    }
    await db.putSetting(
      Keys.lastBackup,
      '${at.toIso8601String()}|${loc.label}',
    );
    return BackupEntry(name, size: bytes.length, modified: at);
  }

  /// After a sync: a backup if the last one is older than [backupEvery].
  /// Never throws; a failed backup is logged and retried next sync.
  Future<void> maybeBackup({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final last = DateTime.tryParse(
      (await db.setting(Keys.lastBackup) ?? '').split('|').first,
    );
    if (last != null && at.difference(last) < backupEvery) return;
    if (await firstDataMinute(db) == null) return; // nothing worth keeping yet
    try {
      BackupEntry e;
      try {
        e = await backupNow(now: at);
      } on MissingPluginException {
        // Background engines on Android don't have the folder channel:
        // keep this one in the default folder; the next foreground sync
        // writes to the picked folder again.
        e = await BackupService(
          db,
          folders: _NoFolder(),
          defaultFolder: defaultFolder,
        ).backupNow(now: at);
      }
      await db.logSync(
        'Backup saved · ${((e.size ?? 0) / 1024).round()} KB',
        'backup',
      );
    } catch (e) {
      await db.logSync('Backup failed: $e', 'backup');
    }
  }

  /// Backups in the default and the remembered folder, newest first.
  /// Unreachable folders are skipped.
  Future<List<FoundBackup>> discover() async {
    final out = <FoundBackup>[];
    final locs = <BackupLocation>[];
    try {
      locs.add(await _default());
    } catch (_) {}
    try {
      final picked = await folders.load();
      if (picked != null) locs.add(picked);
    } catch (_) {}
    for (final loc in locs) {
      out.addAll(await findIn(loc));
    }
    out.sort(
      (a, b) => (b.entry.madeAt ?? DateTime(0)).compareTo(
        a.entry.madeAt ?? DateTime(0),
      ),
    );
    return out;
  }

  /// Backups in one folder, newest first; empty if it can't be read.
  static Future<List<FoundBackup>> findIn(BackupLocation loc) async {
    try {
      return [
        for (final e in await loc.list())
          if (e.isBackup) FoundBackup(loc, e),
      ]..sort(
        (a, b) => (b.entry.madeAt ?? DateTime(0)).compareTo(
          a.entry.madeAt ?? DateTime(0),
        ),
      );
    } catch (_) {
      return const [];
    }
  }
}

class _NoFolder extends BackupFolderStore {
  @override
  Future<PickedFolderLocation?> load() async => null;
}
