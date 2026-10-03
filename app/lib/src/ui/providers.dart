import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import '../core/db.dart';
import '../core/sync_service.dart';

final dbProvider = Provider<st.TempoDb>((ref) {
  final db = openDb();
  ref.onDispose(db.close);
  return db;
});

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Paired band id, or null. Invalidate after pairing / forgetting.
final pairedProvider = FutureProvider<String?>(
  (ref) => ref.watch(dbProvider).setting(deviceIdKey),
);

final scoreProvider = StreamProvider.family<st.DailyScore?, DateTime>(
  (ref, day) => ref.watch(dbProvider).watchScore(day),
);

/// Scores for the last [days] days, oldest first.
final recentScoresProvider = StreamProvider.family<List<st.DailyScore>, int>(
  (ref, days) => ref
      .watch(dbProvider)
      .watchScoresSince(
        dayOf(DateTime.now()).subtract(Duration(days: days - 1)),
      ),
);

class SyncStatus {
  const SyncStatus({this.running = false, this.message});
  final bool running;
  final String? message;
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  Future<void> syncNow() async {
    if (state.running) return;
    state = const SyncStatus(running: true, message: 'Syncing…');
    try {
      final r = await SyncService(ref.read(dbProvider)).run();
      state = SyncStatus(message: 'Synced · $r');
    } on NotPairedException {
      state = const SyncStatus(message: 'No band paired.');
    } catch (e) {
      state = SyncStatus(message: 'Sync failed: $e');
    }
  }
}
