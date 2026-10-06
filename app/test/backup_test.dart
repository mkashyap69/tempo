import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/backup.dart';
import 'package:tempo/src/core/band_link.dart' show deviceIdKey;
import 'package:tempo/src/core/profile.dart' show Keys;

import 'support/seed.dart';

/// The keychain, in memory.
class _Folders extends BackupFolderStore {
  PickedFolderLocation? held;
  @override
  Future<PickedFolderLocation?> load() async => held;
  @override
  Future<void> save(PickedFolderLocation f) async => held = f;
  @override
  Future<void> clear() async => held = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tempo-backup-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  DirectoryLocation folder(String name) =>
      DirectoryLocation(Directory('${tmp.path}/$name'), label: name);

  Future<int> count(TempoDb db, String t) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle())
          .read<int>('n');

  test('backs up, prunes to the newest 7, and throttles to 12 h', () async {
    final db = await seededDb(days: 3);
    final s = BackupService(
      db,
      folders: _Folders(),
      defaultFolder: folder('default'),
    );
    final t0 = DateTime(2026, 10, 6, 8);
    for (var i = 0; i < 9; i++) {
      await s.backupNow(now: t0.add(Duration(hours: i)));
    }
    final names = [for (final e in await folder('default').list()) e.name]
      ..sort();
    expect(names.length, keepBackups);
    expect(names.first, 'tempo-backup-2026-10-06T10-00-00.json.gz');
    expect(names.last, 'tempo-backup-2026-10-06T16-00-00.json.gz');
    expect(
      (await db.setting(Keys.lastBackup))!.split('|').first,
      t0.add(const Duration(hours: 8)).toIso8601String(),
    );
    // Within 12 h of the last one: nothing new.
    await s.maybeBackup(now: t0.add(const Duration(hours: 19)));
    expect((await folder('default').list()).length, keepBackups);
    await s.maybeBackup(now: t0.add(const Duration(hours: 21)));
    expect(
      (await folder('default').list()).map((e) => e.name),
      contains('tempo-backup-2026-10-07T05-00-00.json.gz'),
    );
    await db.close();
  });

  test(
    'a fresh install gets data and settings back, not device state',
    () async {
      final db = await seededDb(days: 3);
      await db.putSetting(Keys.onboarded, '1');
      await db.putSetting(Keys.theme, 'light');
      await db.putSetting(deviceIdKey, 'AA:BB');
      await db.putSetting(Keys.lastSync, '2026-10-06T19:00:00');
      final bytes = await buildBackup(db);
      expect(bytes.take(2), [0x1f, 0x8b]); // gzip

      final fresh = TempoDb(NativeDatabase.memory());
      await fresh.putSetting(Keys.theme, 'dark'); // already set here: kept
      final r = await restoreBackup(fresh, bytes);
      expect(
        await count(fresh, 'minute_samples'),
        await count(db, 'minute_samples'),
      );
      expect(r.minutes, await count(db, 'minute_samples'));
      expect(await fresh.setting(Keys.onboarded), '1');
      expect(await fresh.setting(Keys.profile), await db.setting(Keys.profile));
      expect(await fresh.setting(Keys.theme), 'dark');
      expect(await fresh.setting(deviceIdKey), isNull);
      expect(await fresh.setting(Keys.lastSync), isNull);
      // Scores were recomputed from the restored minutes.
      expect(await count(fresh, 'daily_scores'), greaterThan(0));
      await db.close();
      await fresh.close();
    },
  );

  test('a plain JSON export still restores; junk is refused', () async {
    final db = await seededDb(days: 2);
    // Profile → Export → JSON: the same tables, no settings, not zipped.
    final plain =
        jsonDecode(utf8.decode(gzip.decode(await buildBackup(db))))
              as Map<String, dynamic>
          ..remove('settings')
          ..remove('format');
    final json = utf8.encode(jsonEncode(plain));
    final fresh = TempoDb(NativeDatabase.memory());
    final r = await restoreBackup(fresh, json);
    expect(r.minutes, greaterThan(0));
    expect(r.settings, 0);
    expect(
      () => restoreBackup(fresh, utf8.encode('hello')),
      throwsFormatException,
    );
    expect(
      () => restoreBackup(fresh, [0x1f, 0x8b, 1, 2, 3]),
      throwsFormatException,
    );
    await db.close();
    await fresh.close();
  });

  test('a picked folder: written through the channel, found again', () async {
    // The native side of tempo/backup_folder, over a temp directory.
    final store = folder('icloud');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PickedFolderLocation.channel, (call) async {
          final a = (call.arguments as Map).cast<String, Object?>();
          expect(a['token'], 'bookmark');
          switch (call.method) {
            case 'list':
              return [
                for (final e in await store.list())
                  {
                    'name': e.name,
                    'size': e.size,
                    'modified': e.modified!.millisecondsSinceEpoch,
                  },
              ];
            case 'write':
              await store.write(a['name']! as String, a['bytes']! as Uint8List);
              return null;
            case 'read':
              return Uint8List.fromList(await store.read(a['name']! as String));
            case 'delete':
              await store.delete(a['name']! as String);
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PickedFolderLocation.channel, null),
    );
    final folders = _Folders()
      ..held = PickedFolderLocation('bookmark', 'iCloud Drive › Tempo');
    final db = await seededDb(days: 2);
    final s = BackupService(
      db,
      folders: folders,
      defaultFolder: folder('default'),
    );
    expect((await s.current()).label, 'iCloud Drive › Tempo');
    await s.backupNow(now: DateTime(2026, 10, 6, 20));

    // Reinstall: Tempo's own folder is gone, the keychain still has the
    // bookmark.
    final again = BackupService(
      TempoDb(NativeDatabase.memory()),
      folders: folders,
      defaultFolder: folder('default-after-reinstall'),
    );
    final found = await again.discover();
    expect(found.single.location.label, 'iCloud Drive › Tempo');
    expect(found.single.entry.madeAt, DateTime(2026, 10, 6, 20));
    final r = await restoreBackup(
      again.db,
      await found.single.location.read(found.single.entry.name),
    );
    expect(r.minutes, greaterThan(0));
    await db.close();
    await again.db.close();
  });

  test('backup names carry their time; other files are ignored', () {
    const e = BackupEntry('tempo-backup-2026-10-06T19-44-05.json.gz');
    expect(e.madeAt, DateTime(2026, 10, 6, 19, 44, 5));
    expect(e.isBackup, isTrue);
    expect(const BackupEntry('notes.txt').isBackup, isFalse);
    expect(const BackupEntry('.tempo-backup-x.json.gz.part').isBackup, isFalse);
  });
}
