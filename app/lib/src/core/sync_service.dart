import 'package:band_ble/band_ble.dart';
import 'package:drift/drift.dart';
import 'package:store/store.dart';

import 'band_link.dart';
import 'battery.dart';
import 'longevity_service.dart' show updateLongevity;
import 'profile.dart' show Keys, loadAppProfile;
import 'score_service.dart';

/// Types synced into the DB. PAI is trends-only and has no table yet.
const syncedTypes = [
  FetchType.activity,
  FetchType.stress,
  FetchType.spo2,
  FetchType.spo2Minutes,
  FetchType.odEvents,
];

/// How far back the very first sync reaches.
const firstSyncWindow = Duration(days: 7);

/// Minutes read so far / minutes the band announced (activity only).
typedef SyncProgress = void Function(int read, int total);

class SyncReport {
  SyncReport(
    this.counts,
    this.earliestNew, {
    this.newWorkouts = 0,
    this.gapMinutes = 0,
    this.bandWorkouts = 0,
  });
  final Map<String, int> counts;
  final DateTime? earliestNew;
  final int newWorkouts;

  /// Activity minutes the band had already overwritten (memory full).
  final int gapMinutes;

  /// Workouts recorded on the band's Workout app, new this sync.
  final int bandWorkouts;

  int get minutes => counts[FetchType.activity.key] ?? 0;
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
  /// Every attempt is written to the sync log.
  Future<SyncReport> run({
    Duration wait = const Duration(seconds: 40),
    SyncProgress? onProgress,
    void Function()? onConnected,
  }) async {
    final t0 = DateTime.now();
    await db.putSetting(Keys.lastAttempt, t0.toIso8601String());
    BandLink link;
    try {
      link = await BandLink.open(db, wait: wait);
    } on BandBusyException {
      await db.logSync(
        'Band busy · another sync holds it',
        'retried',
        took: DateTime.now().difference(t0),
      );
      rethrow;
    } catch (e) {
      await db.putSetting(Keys.lastError, 'disconnected|$e');
      await db.logSync(
        'Could not connect to the band',
        'failed',
        took: DateTime.now().difference(t0),
      );
      rethrow;
    }
    onConnected?.call();
    var pct = 0;
    try {
      final r = await syncWith(
        link.band,
        onProgress: (read, total) {
          if (total > 0) pct = (100 * read / total).round();
          onProgress?.call(read, total);
        },
      );
      await db.deleteSetting(Keys.lastError);
      if (r.gapMinutes > 0) await db.logSync(gapSummary(r.gapMinutes), 'gap');
      await db.logSync(_summary(r), 'ok', took: DateTime.now().difference(t0));
      return r;
    } catch (e) {
      await db.putSetting(Keys.lastError, 'failed|$pct|$e');
      await db.logSync(
        'Stopped at $pct% ($e)',
        'failed',
        took: DateTime.now().difference(t0),
      );
      rethrow;
    } finally {
      await link.close();
    }
  }

  /// Re-downloads everything the band still holds and replaces what is
  /// stored from that point on. Fixes rows an older build saved at the
  /// wrong time (the 2026-10-04 builds read fetch times as UTC, putting
  /// minutes 5 h 30 m late in India). Fetches first, so nothing the band
  /// no longer has is ever deleted. Returns a message for the user.
  Future<String> redownload() async {
    final link = await BandLink.open(db);
    try {
      final band = link.band;
      final r = await band.fetch(
        FetchType.activity,
        DateTime.now().subtract(const Duration(days: 30)),
      );
      final start = r.start;
      if (start == null || r.data.isEmpty) {
        return 'The band has no history to re-download.';
      }
      final recs = parseActivity(r.data, start);
      final removed = await db.clearRawHistoryFrom(start);
      await db.appendMinutes([
        for (final a in recs)
          MinuteSamplesCompanion.insert(
            ts: Value(toTs(a.ts)),
            steps: a.steps,
            intensity: a.intensity,
            kind: a.kind,
            hr: Value(a.hr),
            aux: Value(a.aux),
          ),
      ]);
      if (recs.isNotEmpty) {
        await db.setCursor(
          band.id,
          FetchType.activity.key,
          recs.last.ts.add(const Duration(minutes: 1)),
        );
      }
      await syncWith(band); // stress, SpO₂, workouts; rescoring
      await ScoreService(db)
          .recomputeFrom(start.subtract(const Duration(days: 1)));
      final h = recs.length ~/ 60;
      await db.logSync(
        'Re-downloaded ${h}h ${recs.length % 60}m from the band (replaced $removed min)',
        'repair',
      );
      return 'Re-downloaded $h hours of history from ${start.day}/${start.month}. Scores updated.';
    } finally {
      await link.close();
    }
  }

  /// Writes HR interval, sleep assist, stress and wrist (plus time and
  /// profile) whenever they differ from what this band last confirmed.
  /// Without it a band paired elsewhere keeps HR every 30 min and
  /// motion-only sleep detection: late sleep onsets and no stages
  /// (capture android-2026-10-04T12-33-07 has no settings write at all).
  Future<void> ensureConfigured(MiBand band) async {
    final profile = await loadAppProfile(db);
    if (profile == null) return;
    final every = int.tryParse(await db.setting(hrIntervalKey) ?? '') ?? 1;
    final sleepAssist = await db.setting(Keys.sleepAssist) != '0';
    final stress = await db.setting(Keys.stressMonitor) != '0';
    final want = [
      band.id,
      every,
      sleepAssist,
      stress,
      profile.wornLeft,
      profile.age,
      profile.heightCm,
      profile.weightKg,
      profile.male,
    ].join('|');
    if (await db.setting(Keys.bandConfigured) == want) return;
    try {
      final failed = await band.configure(
        profile.band,
        hrEveryMinutes: every,
        sleepAssist: sleepAssist,
        stress: stress,
        wornLeft: profile.wornLeft,
      );
      if (failed.isEmpty) {
        await db.putSetting(Keys.bandConfigured, want);
        await db.logSync(
          'Band settings written · HR every ${every == 1 ? 'minute' : '$every min'}${sleepAssist ? ' · sleep assist' : ''}${stress ? ' · stress' : ''}',
          'settings',
        );
      } else {
        await db.logSync(
          'Band settings not confirmed: ${failed.join(', ')}',
          'settings',
        );
      }
    } catch (_) {
      // Retried on the next sync.
    }
  }

  /// "Band memory was full · 3h 20m not recovered".
  static String gapSummary(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final d = h == 0 ? '$m min' : '${h}h ${m.toString().padLeft(2, '0')}m';
    return 'Band memory was full · $d not recovered';
  }

  static String _summary(SyncReport r) {
    final m = r.minutes;
    final h = m ~/ 60, mm = m % 60;
    final dur = m == 0
        ? 'No new data'
        : h == 0
        ? '$mm min of data'
        : '${h}h ${mm.toString().padLeft(2, '0')}m of data';
    return r.newWorkouts > 0
        ? '$dur · ${r.newWorkouts} ${r.newWorkouts == 1 ? 'activity' : 'activities'}'
        : dur;
  }

  Future<SyncReport> syncWith(MiBand band, {SyncProgress? onProgress}) async {
    try {
      final pct = await band.readBattery();
      if (pct != null) await recordBattery(db, pct);
      final info = await band.readBatteryInfo();
      if (info?.lastChargeAt != null) {
        await db.putSetting(
          Keys.lastCharge,
          '${info!.lastChargeAt!.toIso8601String()}|${info.lastChargeLevel ?? ''}',
        );
      }
      final steps = await band.readRealtimeSteps();
      if (steps != null) {
        await db.putSetting(
          Keys.stepsNow,
          '${DateTime.now().toIso8601String()}|${steps.steps}',
        );
      }
    } catch (_) {}
    await ensureConfigured(band);
    final counts = <String, int>{};
    DateTime? earliest;
    var gap = 0;
    for (final type in syncedTypes) {
      final cursor = await db.cursor(band.id, type.key);
      final since = cursor ?? DateTime.now().subtract(firstSyncWindow);
      final r = await band.fetch(
        type,
        since,
        onProgress: type == FetchType.activity && onProgress != null
            ? (bytes, records) =>
                  onProgress(bytes ~/ activityRecordSize, records)
            : null,
      );
      final start = r.start;
      if (start == null || r.data.isEmpty) {
        counts[type.key] = 0;
        continue;
      }
      // The band starts from the oldest record it still has. Later than
      // our cursor means it overwrote minutes we never fetched.
      if (type == FetchType.activity) gap = activityGapMinutes(cursor, start);
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
                aux: Value(a.aux),
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
        case FetchType.spo2Minutes:
          final recs = parseSpo2Minutes(r.data);
          await db.appendSpo2([
            for (final s in recs)
              if (s.avg > 0)
                Spo2SamplesCompanion.insert(
                  ts: Value(toTs(s.ts)),
                  value: s.avg,
                  quality: Value(s.quality),
                ),
          ]);
          counts[type.key] = recs.length;
          if (recs.isNotEmpty) last = recs.last.ts;
        case FetchType.odEvents:
          final recs = parseOdEvents(r.data);
          await db.appendOdEvents([
            for (final e in recs)
              OdEventsCompanion.insert(
                ts: Value(toTs(e.ts)),
                drop: e.drop,
                spo2: hex(e.spo2),
                hr: hex(e.hr),
              ),
          ]);
          counts[type.key] = recs.length;
          if (recs.isNotEmpty) last = recs.last.ts;
        case FetchType.pai || FetchType.workouts:
          break; // workouts: fetched one summary at a time below
      }
      if (last != null) {
        // Per-minute types resume at the next minute; event types (SpO₂,
        // desaturations: seconds apart) right after the last record.
        final perMinute =
            type == FetchType.activity || type == FetchType.stress;
        await db.setCursor(
          band.id,
          type.key,
          last.add(Duration(seconds: perMinute ? 60 : 1)),
        );
        if (earliest == null || start.isBefore(earliest)) earliest = start;
      }
    }
    // Workouts recorded with the band's Workout app. The summary format is
    // still TODO(verify), so a failure here never fails the sync.
    var bandNew = 0;
    try {
      final cursor = await db.cursor(band.id, FetchType.workouts.key);
      final ws = await band.fetchWorkouts(
        cursor ?? DateTime.now().subtract(firstSyncWindow),
      );
      if (ws.isNotEmpty) {
        await db.appendBandWorkouts([
          for (final w in ws)
            BandWorkoutsCompanion.insert(
              start: Value(toTs(w.start)),
              end: toTs(w.end),
              kind: w.kind,
              raw: hex(w.raw),
              fetchedAt: toTs(DateTime.now()),
            ),
        ]);
        await db.setCursor(
          band.id,
          FetchType.workouts.key,
          ws.last.start.add(const Duration(seconds: 1)),
        );
        bandNew = ws.length;
        final first = ws.first.start;
        if (earliest == null || first.isBefore(earliest)) earliest = first;
      }
    } catch (_) {}
    await db.putSetting(Keys.lastSync, DateTime.now().toIso8601String());
    final before = (await db.workoutsBetween(
      DateTime(2000),
      DateTime(2100),
    )).length;
    final scores = ScoreService(db);
    await scores.recomputeIfStale();
    if (earliest != null) {
      await scores.recomputeFrom(earliest.subtract(const Duration(days: 1)));
    }
    try {
      await updateLongevity(db);
    } catch (_) {} // Tempo Age is derived; a failure never fails the sync.
    final after = (await db.workoutsBetween(
      DateTime(2000),
      DateTime(2100),
    )).length;
    return SyncReport(
      counts,
      earliest,
      newWorkouts: (after - before).clamp(0, 999),
      gapMinutes: gap,
      bandWorkouts: bandNew,
    );
  }
}

/// Minutes lost between [cursor] and the first record the band sent; a
/// couple of minutes of slack for clock rounding. 0 on the first sync.
int activityGapMinutes(DateTime? cursor, DateTime start) {
  if (cursor == null) return 0;
  final d = start.difference(cursor).inMinutes;
  return d > 2 ? d : 0;
}
