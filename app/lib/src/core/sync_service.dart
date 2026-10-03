import 'package:band_ble/band_ble.dart';
import 'package:drift/drift.dart';
import 'package:store/store.dart';

import 'band_link.dart';
import 'score_service.dart';

/// Types synced into the DB. PAI is trends-only and has no table yet.
const syncedTypes = [FetchType.activity, FetchType.stress, FetchType.spo2];

/// How far back the very first sync reaches.
const firstSyncWindow = Duration(days: 7);

class SyncReport {
  SyncReport(this.counts, this.earliestNew);
  final Map<String, int> counts;
  final DateTime? earliestNew;
  @override
  String toString() =>
      counts.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

/// Pulls history per data type from its cursor, appends raw rows, advances
/// the cursor, then rescoring the affected days.
class SyncService {
  SyncService(this.db);
  final TempoDb db;

  /// Connects, syncs, disconnects. Used by the background job and Sync now.
  Future<SyncReport> run() async {
    final link = await BandLink.open(db);
    try {
      return await syncWith(link.band);
    } finally {
      await link.close();
    }
  }

  Future<SyncReport> syncWith(MiBand band) async {
    final counts = <String, int>{};
    DateTime? earliest;
    for (final type in syncedTypes) {
      final since =
          await db.cursor(band.id, type.key) ??
          DateTime.now().subtract(firstSyncWindow);
      final r = await band.fetch(type, since);
      final start = r.start;
      if (start == null || r.data.isEmpty) {
        counts[type.key] = 0;
        continue;
      }
      DateTime? last;
      switch (type) {
        case FetchType.activity:
          final recs = parseActivity(r.data, start);
          await db.appendMinutes([
            for (final a in recs)
              MinuteSamplesCompanion.insert(
                ts: Value(toTs(a.ts)),
                steps: a.steps,
                intensity: a.intensity,
                kind: a.kind,
                hr: Value(a.hr),
              ),
          ]);
          counts[type.key] = recs.length;
          if (recs.isNotEmpty) last = recs.last.ts;
        case FetchType.stress:
          final recs = parseStress(r.data, start);
          await db.appendStress([
            for (final s in recs)
              StressSamplesCompanion.insert(
                ts: Value(toTs(s.ts)),
                value: s.value,
              ),
          ]);
          counts[type.key] = recs.length;
          // Stress is one byte per minute including empty ones.
          last = start.add(Duration(minutes: r.data.length - 1));
        case FetchType.spo2:
          final recs = parseSpo2(r.data);
          await db.appendSpo2([
            for (final s in recs)
              Spo2SamplesCompanion.insert(
                ts: Value(toTs(s.ts)),
                value: s.value,
              ),
          ]);
          counts[type.key] = recs.length;
          if (recs.isNotEmpty) last = recs.last.ts;
        case FetchType.pai:
          break;
      }
      if (last != null) {
        await db.setCursor(
          band.id,
          type.key,
          last.add(const Duration(minutes: 1)),
        );
        if (earliest == null || start.isBefore(earliest)) earliest = start;
      }
    }
    await db.putSetting('last_sync', DateTime.now().toIso8601String());
    final scores = ScoreService(db);
    await scores.recomputeIfStale();
    if (earliest != null) {
      await scores.recomputeFrom(earliest.subtract(const Duration(days: 1)));
    }
    return SyncReport(counts, earliest);
  }
}
