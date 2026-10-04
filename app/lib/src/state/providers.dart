import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import '../core/db.dart';
import '../core/home_widgets.dart';
import '../core/profile.dart';
import '../core/sync_service.dart';
import '../core/today.dart';

final dbProvider = Provider<st.TempoDb>((ref) {
  final db = openDb();
  ref.onDispose(db.close);
  return db;
});

/// Bumps on every DB write; screen models watch it and re-query.
final dbTickProvider = StreamProvider<int>((ref) {
  var n = 0;
  return ref.watch(dbProvider).tableUpdates().map((_) => ++n);
});

final settingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(dbProvider).watchSetting(key),
);

/// Paired band id, or null.
final pairedProvider = Provider<AsyncValue<String?>>((ref) {
  final v = ref.watch(settingProvider(deviceIdKey));
  return v.whenData((id) => id == null || id.isEmpty ? null : id);
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(settingProvider(Keys.theme)).value) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
});

final profileProvider = FutureProvider<Profile>((ref) async {
  ref.watch(settingProvider(Keys.profile));
  return await loadAppProfile(ref.watch(dbProvider)) ?? const Profile();
});

final todayProvider = FutureProvider<TodayData>((ref) async {
  ref.watch(dbTickProvider);
  return loadToday(ref.watch(dbProvider));
});

/// Re-query helper for screen models: `ref.watch(dbTickProvider)` first.
FutureProvider<T> dbQuery<T>(Future<T> Function(st.TempoDb db, Ref ref) q) =>
    FutureProvider<T>((ref) async {
      ref.watch(dbTickProvider);
      return q(ref.watch(dbProvider), ref);
    });

final adapterProvider = StreamProvider<BluetoothAdapterState>(
  (ref) => FlutterBluePlus.adapterState,
);

enum SyncProblem { none, disconnected, failed, busy, noPermission }

class SyncStatus {
  const SyncStatus({
    this.running = false,
    this.read = 0,
    this.total = 0,
    this.problem = SyncProblem.none,
    this.failedPct,
    this.message,
    this.connecting = false,
  });
  final bool running, connecting;
  final int read, total;
  final SyncProblem problem;
  final int? failedPct;

  /// Result line for a toast after a manual sync.
  final String? message;

  double get fraction => total == 0 ? 0 : (read / total).clamp(0, 1);
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    // Restore the last failure so banners survive a restart.
    ref.watch(dbProvider).setting(Keys.lastError).then((raw) {
      if (raw == null || state.running) return;
      final p = raw.split('|');
      state = SyncStatus(
        problem: p.first == 'failed'
            ? SyncProblem.failed
            : SyncProblem.disconnected,
        failedPct: p.first == 'failed' && p.length > 1
            ? int.tryParse(p[1])
            : null,
      );
    });
    return const SyncStatus();
  }

  Future<SyncStatus> syncNow() async {
    if (state.running) return state;
    final db = ref.read(dbProvider);
    if (await db.setting(deviceIdKey) case null || '') {
      return state = const SyncStatus();
    }
    try {
      final a = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
      );
      if (a == BluetoothAdapterState.unauthorized) {
        return state = const SyncStatus(problem: SyncProblem.noPermission);
      }
      if (a == BluetoothAdapterState.off) {
        return state = const SyncStatus(problem: SyncProblem.disconnected);
      }
    } catch (_) {}
    state = const SyncStatus(running: true, connecting: true);
    try {
      final r = await SyncService(db).run(
        onConnected: () => state = const SyncStatus(running: true),
        onProgress: (read, total) =>
            state = SyncStatus(running: true, read: read, total: total),
      );
      await afterSync(db);
      final m = r.minutes;
      final parts = [
        if (r.newWorkouts > 0)
          '${r.newWorkouts} ${r.newWorkouts == 1 ? 'workout' : 'workouts'}',
        if (m >= 180) 'last night',
        if (m > 0 && m < 180) '$m min',
      ];
      return state = SyncStatus(
        message: parts.isEmpty
            ? 'Synced · up to date'
            : 'Synced · ${parts.join(' and ')} added',
      );
    } on BandBusyException {
      return state = const SyncStatus(problem: SyncProblem.busy);
    } on NotPairedException {
      return state = const SyncStatus();
    } catch (e) {
      final raw = await db.setting(Keys.lastError) ?? '';
      if (raw.startsWith('failed')) {
        return state = SyncStatus(
          problem: SyncProblem.failed,
          failedPct: int.tryParse(raw.split('|')[1]),
        );
      }
      return state = const SyncStatus(problem: SyncProblem.disconnected);
    }
  }

  void clearMessage() =>
      state = SyncStatus(problem: state.problem, failedPct: state.failedPct);
}

/// Ticks every minute so "6 min ago" stays true.
final minuteClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});
