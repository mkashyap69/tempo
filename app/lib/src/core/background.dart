import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'band_link.dart';
import 'data_source.dart';
import 'db.dart';
import 'health_sync.dart';
import 'home_widgets.dart';
import 'sync_service.dart';

const _syncTask = 'tempo.sync';

/// Entry point for WorkManager (Android) / BGTaskScheduler (iOS) runs.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = openDb();
    try {
      if ((await loadDataSource(db)).isHealth) {
        final r = await HealthSyncService(db, background: true).run();
        if (!r.skipped) await afterSync(db);
        return true;
      }
      await SyncService(db).run(wait: const Duration(seconds: 2));
      await afterSync(db);
      return true;
    } on BandBusyException {
      return true; // a foreground sync holds the band; do not stack retries
    } on HealthBusyException {
      return true;
    } on HealthAccessException {
      return true; // needs the user; retrying won't help
    } on HealthUnreadableException {
      return true; // phone locked (iOS); the next open or run reads it
    } catch (e) {
      debugPrint('background sync failed: $e');
      return false; // WorkManager retries with backoff
    } finally {
      await db.close();
    }
  });
}

/// Registers the periodic sync (band or Health, whichever is the source).
/// Android: WorkManager every 3 hours.
/// iOS: a background-refresh task; iOS decides when (if ever) it runs, so
/// the app also syncs on open.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(backgroundDispatcher);
  if (Platform.isAndroid) {
    await Workmanager().registerPeriodicTask(
      _syncTask,
      _syncTask,
      frequency: const Duration(hours: 3),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  } else if (Platform.isIOS) {
    await Workmanager().registerPeriodicTask(
      _syncTask,
      _syncTask,
      frequency: const Duration(hours: 3),
    );
  }
}
