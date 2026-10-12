import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:health_source/health_source.dart';
import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart';

import 'backup.dart' show BackupService;
import 'band_link.dart' show acquireFileLock, releaseFileLock;
import 'data_source.dart';
import 'health_reader.dart';
import 'longevity_service.dart' show updateLongevity;
import 'minutes.dart';
import 'profile.dart' show Keys;
import 'score_service.dart';

/// Another Health read holds the lock (foreground and background).
class HealthBusyException implements Exception {
  @override
  String toString() => 'Another Health read is running.';
}

/// Health access is missing (Health Connect said so).
class HealthAccessException implements Exception {
  @override
  String toString() => 'Tempo has no access to Health.';
}

/// Every read failed: on iOS, almost always because the phone is locked
/// (Health data is encrypted while it is).
class HealthUnreadableException implements Exception {
  HealthUnreadableException(this.detail);
  final String detail;
  @override
  String toString() => 'Health could not be read ($detail).';
}

final class HealthSyncReport {
  const HealthSyncReport({
    required this.from,
    required this.to,
    required this.counts,
    required this.failed,
    required this.doubtful,
    required this.gone,
    required this.firstImport,
    this.newWorkouts = 0,
    this.skipped = false,
  });
  final DateTime from, to;
  final Map<HealthKind, int> counts;
  final Set<HealthKind> failed;
  final List<HealthKind> doubtful;
  final int gone;
  final bool firstImport;
  final int newWorkouts;

  /// Nothing was read: a background run Health Connect doesn't allow.
  final bool skipped;

  int get records => counts.values.fold(0, (a, b) => a + b);
  int get sleepRecords => count([
    for (final k in HealthKind.values)
      if (k.isSleep) k,
  ]);
  int count(Iterable<HealthKind> ks) =>
      ks.fold(0, (a, k) => a + (counts[k] ?? 0));
}

/// Fraction done (0–1) of a Health read.
typedef HealthProgress = void Function(double done);

/// Reads Apple Health or Health Connect into `health_records`, tombstones
/// what was deleted there, rebuilds the derived minutes and rescores.
///
/// Windows: the first read goes back [firstWindow]. Later reads re-read
/// from [recentWindow] before the last good read, because watches sync
/// late (a watch out of range for a day writes yesterday's heart rate this
/// morning) and because edits and deletes only show on a re-read. Once a
/// day the re-read reaches back [deepWindow].
class HealthSyncService {
  HealthSyncService(
    this.db, {
    HealthReader? reader,
    DateTime Function()? clock,
    this.background = false,
    this.useLock = true,
  }) : reader = reader ?? PluginHealthReader(),
       _now = clock ?? DateTime.now;

  final TempoDb db;
  final HealthReader reader;
  final DateTime Function() _now;
  final bool background;

  /// Off in tests (no documents folder).
  final bool useLock;

  static const device = 'health';
  static const cursorType = 'records';
  static const firstWindow = Duration(days: 90);
  static const recentWindow = Duration(days: 3);
  static const deepWindow = Duration(days: 10);
  static const deepEvery = Duration(hours: 24);
  static const chunk = Duration(days: 7);

  /// Records longer than this are bad data (a whole-day step total is the
  /// longest real one); see store's maxHealthRecordMs.
  static const maxRecord = Duration(hours: 26);

  Future<HealthSyncReport> run({HealthProgress? onProgress}) async {
    final t0 = _now();
    await db.putSetting(Keys.lastAttempt, t0.toIso8601String());
    final source = await loadDataSource(db);
    if (!source.isHealth) {
      throw StateError('Health sync with ${source.label} as the source');
    }
    File? lock;
    if (useLock) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        lock = await acquireFileLock(
          File('${docs.path}/health.lock'),
          const Duration(seconds: 20),
          onBusy: HealthBusyException.new,
        );
      } on HealthBusyException {
        await db.logSync(
          '${source.label} busy · another read holds it',
          'retried',
        );
        rethrow;
      }
    }
    try {
      return await _run(source, t0, lock, onProgress);
    } on HealthAccessException {
      await db.putSetting(Keys.lastError, 'health_access|');
      await db.logSync(
        'No access to ${source.label}',
        'failed',
        took: _now().difference(t0),
      );
      rethrow;
    } on HealthUnreadableException catch (e) {
      // In the background this is iOS's locked phone, every night: logged,
      // but no banner for it; the next open reads again.
      if (!background) {
        await db.putSetting(Keys.lastError, 'health_unreadable|${e.detail}');
      }
      await db.logSync(
        '${source.label} could not be read${Platform.isIOS ? ' (phone locked?)' : ''}',
        'failed',
        took: _now().difference(t0),
      );
      rethrow;
    } catch (e) {
      await db.putSetting(Keys.lastError, 'failed||$e');
      await db.logSync(
        'Reading ${source.label} stopped ($e)',
        'failed',
        took: _now().difference(t0),
      );
      rethrow;
    } finally {
      if (lock != null) await releaseFileLock(lock);
    }
  }

  Future<HealthSyncReport> _run(
    DataSource source,
    DateTime t0,
    File? lock,
    HealthProgress? onProgress,
  ) async {
    if (background && !await reader.canReadInBackground()) {
      await db.logSync(
        '${source.label}: background reads not allowed · reads when Tempo is open',
        'retried',
      );
      return HealthSyncReport(
        from: t0,
        to: t0,
        counts: const {},
        failed: const {},
        doubtful: const [],
        gone: 0,
        firstImport: false,
        skipped: true,
      );
    }
    if (!await reader.hasAccess()) throw HealthAccessException();

    final cursor = await db.cursor(device, cursorType);
    final firstImport = cursor == null;
    final lastDeep = DateTime.tryParse(
      await db.setting(Keys.healthDeepRead) ?? '',
    );
    final deep = lastDeep == null || t0.difference(lastDeep) >= deepEvery;
    final from = firstImport
        ? t0.subtract(firstWindow)
        : cursor.subtract(deep ? deepWindow : recentWindow);
    final to = t0;
    final kinds = reader.kinds;

    final counts = <HealthKind, int>{};
    final failed = <HealthKind>{};
    final errors = <String>{};
    // Kept only for a re-read, to compare against what is stored.
    final fresh = <HealthRecord>[];
    final chunks = <(DateTime, DateTime)>[];
    for (var a = from; a.isBefore(to); a = a.add(chunk)) {
      final b = a.add(chunk);
      chunks.add((a, b.isAfter(to) ? to : b));
    }
    final steps = chunks.length * kinds.length;
    var done = 0;
    for (final (a, b) in chunks) {
      for (final kind in kinds) {
        List<HealthRecord> rs;
        try {
          rs = await reader.read(kind, a, b);
        } catch (e) {
          failed.add(kind);
          errors.add('$e');
          debugPrint('health read ${kind.name}: $e');
          continue;
        } finally {
          done++;
          onProgress?.call(done / steps);
        }
        final keep = [
          for (final r in rs)
            if (_usable(r)) r,
        ];
        await db.appendHealthRecords([for (final r in keep) _row(r, t0)]);
        if (!firstImport) fresh.addAll(keep);
        counts[kind] = (counts[kind] ?? 0) + keep.length;
      }
      try {
        await lock?.setLastModified(_now()); // still alive: not stale
      } catch (_) {}
    }
    if (failed.length == kinds.length) {
      throw HealthUnreadableException(errors.take(1).join());
    }

    // Deleted or edited in Health since the last read.
    var gone = 0;
    var doubtful = const <HealthKind>[];
    if (!firstImport) {
      final stored = [
        for (final r in await db.healthRecordsStarting(from, to))
          if (HealthKind.values.asNameMap()[r.kind] case final k?)
            (
              key: r.key,
              kind: k,
              start: DateTime.fromMillisecondsSinceEpoch(r.startMs),
            ),
      ];
      final x = reconcile(
        stored: stored,
        fresh: fresh,
        read: kinds.difference(failed),
        from: from,
        to: to,
      );
      if (x.gone.isNotEmpty) await db.addHealthDeletions(x.gone);
      gone = x.gone.length;
      doubtful = x.doubtful;
    }

    final rebuildFrom = from.subtract(const Duration(days: 1));
    await rebuildHealthMinutes(db, rebuildFrom, to);

    final before = (await db.workoutsBetween(
      DateTime(2000),
      DateTime(2100),
    )).length;
    final scores = ScoreService(db);
    await scores.recomputeIfStale();
    await scores.recomputeFrom(rebuildFrom);
    try {
      await updateLongevity(db);
    } catch (_) {} // derived; never fails the read
    await BackupService(db).maybeBackup();
    final after = (await db.workoutsBetween(
      DateTime(2000),
      DateTime(2100),
    )).length;

    // Only a complete read moves the window on; a partial one is re-read.
    if (failed.isEmpty) {
      await db.setCursor(device, cursorType, to);
      if (deep) await db.putSetting(Keys.healthDeepRead, to.toIso8601String());
      await db.deleteSetting(Keys.lastError);
    } else {
      await db.putSetting(
        Keys.lastError,
        'health_partial|${failed.map((k) => k.name).join(',')}',
      );
    }
    await db.putSetting(Keys.lastSync, _now().toIso8601String());
    await _rememberFound(counts);

    final report = HealthSyncReport(
      from: from,
      to: to,
      counts: counts,
      failed: failed,
      doubtful: doubtful,
      gone: gone,
      firstImport: firstImport,
      newWorkouts: (after - before).clamp(0, 999),
    );
    await db.logSync(
      summary(source, report),
      failed.isEmpty ? 'ok' : 'retried',
      took: _now().difference(t0),
    );
    return report;
  }

  static bool _usable(HealthRecord r) =>
      !r.fromTempo &&
      !r.end.isBefore(r.start) &&
      r.end.difference(r.start) <= maxRecord &&
      r.value.isFinite;

  static HealthRecordsCompanion _row(HealthRecord r, DateTime at) =>
      HealthRecordsCompanion.insert(
        key: r.key,
        uuid: r.uuid,
        kind: r.kind.name,
        startMs: r.start.millisecondsSinceEpoch,
        endMs: r.end.millisecondsSinceEpoch,
        value: r.value,
        sourceApp: r.sourceApp,
        extra: Value(r.extra),
        fetchedAt: toTs(at),
      );

  /// What kinds of data this source has given so far (for Profile → Data
  /// source and onboarding): kind name → true once any record was seen.
  Future<void> _rememberFound(Map<HealthKind, int> counts) async {
    Map<String, dynamic> found;
    try {
      found = jsonDecode(
        await db.setting(Keys.healthFound) ?? '{}',
      ) as Map<String, dynamic>;
    } catch (_) {
      found = {};
    }
    for (final e in counts.entries) {
      if (e.value > 0) found[e.key.name] = true;
    }
    await db.putSetting(Keys.healthFound, jsonEncode(found));
  }

  /// "Apple Health · 3 nights, 1,240 heart-rate readings, 2 workouts".
  static String summary(DataSource s, HealthSyncReport r) {
    final hr = r.count([HealthKind.heartRate]);
    final sleep = r.count([
      for (final k in HealthKind.values)
        if (k.isSleep) k,
    ]);
    final w = r.count([HealthKind.workout]);
    final parts = [
      if (hr > 0) '$hr heart-rate readings',
      if (sleep > 0) '$sleep sleep records',
      if (w > 0) '$w ${w == 1 ? 'workout' : 'workouts'}',
      if (r.gone > 0) '${r.gone} removed',
    ];
    final lead = r.firstImport ? '${s.label} imported' : s.label;
    final tail = r.failed.isEmpty
        ? ''
        : ' · not read: ${r.failed.map((k) => k.name).join(', ')}';
    return parts.isEmpty
        ? '$lead · no new data$tail'
        : '$lead · ${parts.join(', ')}$tail';
  }
}

/// Rebuilds the derived per-minute rows for [from, to) from the stored
/// records, a week at a time. Records are read a little beyond each week so
/// heart rate interpolates across the edges and a sleep record that
/// straddles one is judged whole.
Future<void> rebuildHealthMinutes(
  TempoDb db,
  DateTime from,
  DateTime to,
) async {
  const margin = Duration(hours: 27);
  final gridKinds = [
    for (final k in HealthKind.values)
      if (k == HealthKind.heartRate ||
          k == HealthKind.steps ||
          k == HealthKind.spo2 ||
          k.isSleep)
        k,
  ];
  // Whole minutes; the current one is included.
  final a0 = DateTime.fromMillisecondsSinceEpoch(
    from.millisecondsSinceEpoch ~/ 60000 * 60000,
  );
  final end = DateTime.fromMillisecondsSinceEpoch(
    (to.millisecondsSinceEpoch ~/ 60000 + 1) * 60000,
  );
  for (var a = a0; a.isBefore(end); a = a.add(HealthSyncService.chunk)) {
    final next = a.add(HealthSyncService.chunk);
    final b = next.isAfter(end) ? end : next;
    final grid = HealthGrid()
      ..addAll(
        await loadHealthRecords(
          db,
          a.subtract(margin),
          b.add(margin),
          kinds: gridKinds,
        ),
      );
    await db.replaceHealthMinutes(a, b, [
      for (final m in grid.minutes(a, b)) healthMinuteRow(m),
    ]);
  }
}
