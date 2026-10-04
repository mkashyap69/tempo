import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'band_link.dart';
import 'db.dart';
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
      await SyncService(db).run(wait: const Duration(seconds: 2));
      await afterSync(db);
      return true;
    } on BandBusyException {
      return true; // a foreground sync holds the band; do not stack retries
    } catch (e) {
      debugPrint('background sync failed: $e');
      return false; // WorkManager retries with backoff
    } finally {
      await db.close();
    }
  });
}

/// Registers the periodic sync. Android: WorkManager every 3 hours.
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
