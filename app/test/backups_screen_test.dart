import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/backup.dart';
import 'package:tempo/src/core/notifications.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/screens/backups.dart';
import 'package:tempo/src/state/providers.dart';

import 'support/fake_sink.dart';
import 'support/harness.dart';
import 'support/seed.dart';

class _NoKeychain extends BackupFolderStore {
  @override
  Future<PickedFolderLocation?> load() async => null;
}

void main() {
  testWidgets('finds a backup in the default folder and restores it', (
    t,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('tempo-panel-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final folder = DirectoryLocation(
      Directory('${tmp.path}/Backups'),
      label: 'On My iPhone › Tempo › Backups',
    );
    final fresh = TempoDb(NativeDatabase.memory());
    await t.runAsync(() async {
      final old = await seededDb(days: 2);
      await BackupService(
        old,
        folders: _NoKeychain(),
        defaultFolder: folder,
      ).backupNow(now: DateTime(2026, 10, 6, 19, 44));
      await old.close();
    });
    var restored = false;
    notificationSink = FakeNotificationSink();
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(fresh),
          backupServiceProvider.overrideWithValue(
            BackupService(fresh, folders: _NoKeychain(), defaultFolder: folder),
          ),
        ],
        child: MaterialApp(
          theme: tempoTheme(Brightness.dark),
          home: Scaffold(
            body: RestorePanel(
              onboarding: true,
              onRestored: () => restored = true,
            ),
          ),
        ),
      ),
    );
    await settle(t);
    expect(find.text('Tue 6 Oct, 7:44 PM'), findsOneWidget);
    expect(
      find.textContaining('On My iPhone › Tempo › Backups'),
      findsOneWidget,
    );
    await t.tap(find.text('Tue 6 Oct, 7:44 PM'));
    await settle(t);
    await t.tap(find.text('Restore').last);
    await settle(t, frames: 60);
    expect(restored, isTrue);
    final n = await t.runAsync(
      () => fresh
          .customSelect('SELECT COUNT(*) AS n FROM minute_samples')
          .getSingle(),
    );
    expect(n!.read<int>('n'), greaterThan(0));
    await teardown(t, fresh);
  });
}
