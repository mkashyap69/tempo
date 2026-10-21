import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
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
    // A kind this install hasn't read before (one added by an update) is
    // read from [firstWindow] back, and in the foreground its permission
    // is asked once; the rest keep the normal window.
    final known = (await db.setting(Keys.healthKinds) ?? '')
        .split(',')
        .where((k) => k.isNotEmpty)
        .toSet();
    final newKinds = firstImport
        ? const <HealthKind>{}
        : {
            for (final k in kinds)
              if (!known.contains(k.name)) k,
          };
    if (newKinds.isNotEmpty && !background) {
      try {
        await reader.connect();
      } catch (e) {
        debugPrint('health connect for new kinds: $e');
      }
    }
    final readFrom = newKinds.isEmpty ? from : t0.subtract(firstWindow);

    final counts = <HealthKind, int>{};
    final names = <String, String>{};
    final failed = <HealthKind>{};
    final errors = <String>{};
    // Kept only for a re-read, to compare against what is stored.
    final fresh = <HealthRecord>[];
    final chunks = <(DateTime, DateTime)>[];
    for (var a = readFrom; a.isBefore(to); a = a.add(chunk)) {
      final b = a.add(chunk);
      chunks.add((a, b.isAfter(to) ? to : b));
    }
    final steps = chunks.length * kinds.length;
    var done = 0;
    for (final (a, b) in chunks) {
      for (final kind in kinds) {
        if (!b.isAfter(from) && !newKinds.contains(kind)) {
          done++;
          continue; // before the normal window: only new kinds go back
        }
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
            if (usable(r)) r,
        ];
        await db.appendHealthRecords([for (final r in keep) _row(r, t0)]);
        for (final r in keep) {
          if (r.sourceName.isNotEmpty) names[r.sourceApp] = r.sourceName;
        }
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
    if (newKinds.difference(failed).isNotEmpty || firstImport) {
      await db.putSetting(
        Keys.healthKinds,
        [
          for (final k in kinds)
            if (!failed.contains(k) || known.contains(k.name)) k.name,
        ].join(','),
      );
    }
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
    await rememberSourceNames(db, names);

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

  /// Whether a read keeps [r]: not Tempo's own, and a sane span and value.
  static bool usable(HealthRecord r) =>
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
  final params = GridParams(
    sleepSource: await metricSource(db, SourceMetric.sleep),
    hrSource: await metricSource(db, SourceMetric.heartRate),
    stepsSource: await metricSource(db, SourceMetric.steps),
  );
  for (var a = a0; a.isBefore(end); a = a.add(HealthSyncService.chunk)) {
    final next = a.add(HealthSyncService.chunk);
    final b = next.isAfter(end) ? end : next;
    final grid = HealthGrid(params)
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

/// Adds [found] (source app id → display name) to the stored names.
Future<void> rememberSourceNames(TempoDb db, Map<String, String> found) async {
  if (found.isEmpty) return;
  final names = await sourceNames(db);
  final before = names.length;
  var changed = false;
  for (final e in found.entries) {
    if (names[e.key] != e.value) {
      names[e.key] = e.value;
      changed = true;
    }
  }
  if (changed || names.length != before) {
    await db.putSetting(Keys.healthSourceNames, jsonEncode(names));
  }
}

/// Source app id → display name, as Health last reported it.
Future<Map<String, String>> sourceNames(TempoDb db) async {
  try {
    final m = jsonDecode(await db.setting(Keys.healthSourceNames) ?? '{}');
    return {
      for (final e in (m as Map).entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  } catch (_) {
    return {};
  }
}

/// A readable name for a source app: what Health called it, else the
/// last part of its id ("com.example.sleepring" → "Sleepring").
String sourceLabel(String id, Map<String, String> names) {
  final n = names[id];
  if (n != null && n.isNotEmpty) return n;
  final parts = id.split('.').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return id;
  final last = parts.last;
  return last[0].toUpperCase() + last.substring(1);
}

/// An app that wrote sleep to Health recently.
final class SleepSourceInfo {
  const SleepSourceInfo(this.id, this.label, this.nights, this.last);
  final String id, label;

  /// Nights (local dates a sleep record ended on) in the window.
  final int nights;
  final DateTime last;
}

/// A measure whose source app can be chosen (Profile → Data sources).
enum SourceMetric {
  sleep(Keys.healthSleepSource),
  heartRate(Keys.healthHrSource),
  steps(Keys.healthStepsSource),
  hrv(Keys.healthHrvSource);

  const SourceMetric(this.key);
  final String key;

  List<HealthKind> get kinds => switch (this) {
    SourceMetric.sleep => [
      for (final k in HealthKind.values)
        if (k.isSleep) k,
    ],
    SourceMetric.heartRate => const [HealthKind.heartRate],
    SourceMetric.steps => const [HealthKind.steps],
    SourceMetric.hrv => const [HealthKind.hrvSdnn, HealthKind.hrvRmssd],
  };
}

/// The chosen app for [m], or null for every app.
Future<String?> metricSource(TempoDb db, SourceMetric m) async {
  final v = await db.setting(m.key);
  return v == null || v.isEmpty ? null : v;
}

/// Apps that wrote sleep in the last [days] days, most nights first.
Future<List<SleepSourceInfo>> sleepSources(
  TempoDb db, {
  int days = 30,
  DateTime? now,
}) => metricSources(db, SourceMetric.sleep, days: days, now: now);

/// Apps that wrote [m] in the last [days] days, most days first.
Future<List<SleepSourceInfo>> metricSources(
  TempoDb db,
  SourceMetric m, {
  int days = 30,
  DateTime? now,
}) async {
  final since = (now ?? DateTime.now()).subtract(Duration(days: days));
  final kinds = [for (final k in m.kinds) "'${k.name}'"].join(', ');
  final rows = await db
      .customSelect(
        'SELECT source_app, end_ms FROM health_records '
        'WHERE kind IN ($kinds) AND end_ms >= ?',
        variables: [Variable.withInt(since.millisecondsSinceEpoch)],
      )
      .get();
  final nights = <String, Set<String>>{};
  final last = <String, int>{};
  for (final r in rows) {
    final id = r.read<String>('source_app');
    if (id == tempoAppId) continue;
    final end = r.read<int>('end_ms');
    final d = DateTime.fromMillisecondsSinceEpoch(end);
    nights.putIfAbsent(id, () => {}).add('${d.year}-${d.month}-${d.day}');
    if (end > (last[id] ?? 0)) last[id] = end;
  }
  final names = await sourceNames(db);
  return [
    for (final id in nights.keys)
      SleepSourceInfo(
        id,
        sourceLabel(id, names),
        nights[id]!.length,
        DateTime.fromMillisecondsSinceEpoch(last[id]!),
      ),
  ]..sort((a, b) => b.nights.compareTo(a.nights));
}

/// Uses only [id]'s sleep (null: every app, merged), then rebuilds the
/// stored Health minutes and rescores everything they cover.
Future<void> setSleepSource(TempoDb db, String? id) =>
    setMetricSource(db, SourceMetric.sleep, id);

/// Chooses the app [m] comes from (null = every app), then rebuilds the
/// Health minutes and rescores every Health day.
Future<void> setMetricSource(TempoDb db, SourceMetric m, String? id) async {
  if (id == null) {
    await db.deleteSetting(m.key);
  } else {
    await db.putSetting(m.key, id);
  }
  final first = await db
      .customSelect('SELECT MIN(start_ms) AS a FROM health_records')
      .getSingleOrNull();
  final a = first?.read<int?>('a');
  if (a == null) return;
  final from = DateTime.fromMillisecondsSinceEpoch(a);
  await rebuildHealthMinutes(db, from, DateTime.now());
  await ScoreService(db).recomputeFrom(from);
}
