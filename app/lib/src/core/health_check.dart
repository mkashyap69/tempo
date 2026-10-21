import 'dart:io';

import 'package:health_source/health_source.dart';
import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart';

import 'health_reader.dart';
import 'health_sync.dart';
import 'profile.dart' show Keys;

/// How one kind compares between Health and what Tempo stored.
enum KindVerdict {
  /// Every usable record Health has before the last read is stored.
  ok,

  /// Health has no records of this kind in the window.
  empty,

  /// Health has records Tempo didn't store (a read missed them).
  missing,

  /// Tempo stores records Health no longer has (not yet tombstoned).
  extra,

  /// Values outside what this kind can be: wrong unit or bad data.
  odd,

  /// The read threw.
  failed,
}

/// Where one record Health returned stands in Tempo.
enum RecordStatus {
  stored,

  /// Written after the last read; the next read picks it up.
  newer,

  /// Before the last read, yet not stored.
  missing,

  /// Skipped on purpose: Tempo's own, longer than a day, or no number.
  dropped,
}

/// One record as Health returned it, for the raw record viewer.
final class CheckedRecord {
  const CheckedRecord(this.record, this.status, {this.odd = false});
  final HealthRecord record;
  final RecordStatus status;

  /// Value outside [plausible].
  final bool odd;
}

/// One kind's side-by-side count.
final class KindCheck {
  const KindCheck({
    required this.kind,
    required this.verdict,
    this.inHealth = 0,
    this.dropped = 0,
    this.stored = 0,
    this.missing = 0,
    this.extra = 0,
    this.newer = 0,
    this.odd = 0,
    this.latest,
    this.min,
    this.max,
    this.sources = const {},
    this.recent = const [],
    this.error,
  });
  final HealthKind kind;
  final KindVerdict verdict;

  /// Records Health returned for the window.
  final int inHealth;

  /// Of those, ones a read skips on purpose (Tempo's own, too long, NaN).
  final int dropped;

  /// Live records Tempo holds for the compared part of the window.
  final int stored;

  /// Usable in Health, not stored / stored, not in Health.
  final int missing, extra;

  /// Written after the last read: the next read picks them up.
  final int newer;

  /// Usable records whose value is outside [plausible].
  final int odd;
  final DateTime? latest;
  final double? min, max;

  /// Source app id → records, from Health.
  final Map<String, int> sources;

  /// The newest [recentLimit] records Health returned, newest first.
  final List<CheckedRecord> recent;
  final String? error;

  static const recentLimit = 50;
}

/// Last night and today, from stored records to minutes to scores.
final class PipelineCheck {
  const PipelineCheck({
    required this.nightFrom,
    required this.nightTo,
    required this.dayFrom,
    required this.dayTo,
    required this.sleepRecordMin,
    required this.sleepMin,
    required this.stages,
    required this.hrRecords,
    required this.hrMeasuredMin,
    required this.hrMin,
    required this.stepsTempo,
    required this.stepsBySource,
    required this.chosen,
    this.today,
    this.yesterday,
  });

  /// Last night: 18:00 yesterday to noon (or now).
  final DateTime nightFrom, nightTo;

  /// Today: midnight to now.
  final DateTime dayFrom, dayTo;

  /// Minutes asleep per the stored records (union of stages; containers
  /// when a source writes no stages), and per the derived minutes.
  final int sleepRecordMin, sleepMin;

  /// Derived minutes by sleep mark (asleep, light, deep, rem, awake).
  final Map<String, int> stages;

  /// Stored heart-rate records today, and derived minutes with a measured
  /// / any (measured or interpolated) heart rate.
  final int hrRecords, hrMeasuredMin, hrMin;

  /// Steps today in Tempo's minutes, and per app in the stored records
  /// (the apps overlap: Tempo takes the busier one per minute).
  final int stepsTempo;
  final Map<String, int> stepsBySource;

  /// Profile → Data sources: chosen app per measure, null = every app.
  final Map<SourceMetric, String?> chosen;
  final DailyScore? today, yesterday;
}

final class HealthCheckReport {
  const HealthCheckReport({
    required this.from,
    required this.to,
    required this.lastRead,
    required this.access,
    required this.kinds,
    this.permissions,
    this.pipeline,
  });
  final DateTime from, to;

  /// Records starting before this are compared; later ones are [KindCheck.newer].
  final DateTime? lastRead;
  final bool access;
  final List<KindCheck> kinds;
  final HealthPermissions? permissions;
  final PipelineCheck? pipeline;

  bool get allOk => access && kinds.every((k) => k.verdict == KindVerdict.ok);

  /// Plain text, to paste into an issue or keep as evidence.
  String text(String label, Map<String, String> names) {
    String src(String id) => sourceLabel(id, names);
    String yn(bool? v) => v == null ? 'unknown' : (v ? 'yes' : 'no');
    final b = StringBuffer()
      ..writeln('Tempo · $label data check')
      ..writeln('Window ${from.toIso8601String()} – ${to.toIso8601String()}')
      ..writeln('Last read ${lastRead?.toIso8601String() ?? 'never'}')
      ..writeln('Access ${access ? 'yes' : 'no'}');
    final p = permissions;
    if (p != null) {
      b.writeln(
        'Permissions · history ${yn(p.history)} · background ${yn(p.background)} · '
        '${[for (final e in p.kinds.entries) '${e.key.name} ${yn(e.value)}'].join(', ')}',
      );
    }
    final q = pipeline;
    if (q != null) {
      b
        ..writeln(
          'Last night ${q.nightFrom.toIso8601String()} – ${q.nightTo.toIso8601String()}'
          ' · asleep in records ${q.sleepRecordMin} min · in minutes ${q.sleepMin} min'
          ' · ${[for (final e in q.stages.entries) '${e.key} ${e.value}'].join(', ')}',
        )
        ..writeln(
          'Today · HR records ${q.hrRecords} · HR minutes ${q.hrMeasuredMin} measured, '
          '${q.hrMin} with HR · steps ${q.stepsTempo}'
          '${q.stepsBySource.isEmpty ? '' : ' (records: ${[for (final e in q.stepsBySource.entries) '${src(e.key)} ${e.value}'].join(', ')})'}',
        )
        ..writeln(
          'Chosen apps · ${[for (final e in q.chosen.entries) '${e.key.name} ${e.value == null ? 'all' : src(e.value!)}'].join(', ')}',
        );
      for (final (name, s) in [
        ('today', q.today),
        ('yesterday', q.yesterday),
      ]) {
        b.writeln('Score $name · ${s == null ? 'none' : scoreLine(s)}');
      }
    }
    for (final k in kinds) {
      b.write(
        '${k.kind.name}: ${k.verdict.name} · health ${k.inHealth}'
        ' (dropped ${k.dropped}, newer ${k.newer}) · stored ${k.stored}',
      );
      if (k.missing > 0) b.write(' · missing ${k.missing}');
      if (k.extra > 0) b.write(' · extra ${k.extra}');
      if (k.odd > 0) b.write(' · odd ${k.odd}');
      if (k.min != null) b.write(' · range ${num(k.min!)}–${num(k.max!)}');
      if (k.latest != null) b.write(' · latest ${k.latest!.toIso8601String()}');
      if (k.sources.isNotEmpty) {
        b.write(
          ' · from ${[for (final e in k.sources.entries) '${src(e.key)} ${e.value}'].join(', ')}',
        );
      }
      if (k.error != null) b.write(' · error ${k.error}');
      b.writeln();
    }
    return b.toString();
  }

  static String num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// "algo 9 · apple_health · strain 8.2 · recovery 64 · sleep 89% · HRV 42 sdnn".
  static String scoreLine(DailyScore s) => [
    'algo ${s.algoVersion}',
    s.source,
    'strain ${s.strain.toStringAsFixed(1)}',
    s.calibrating
        ? 'recovery learning'
        : 'recovery ${s.recovery?.round() ?? '—'}',
    'sleep ${s.sleepPerf == null ? '—' : '${s.sleepPerf!.round()}%'}',
    'HRV ${s.hrv == null ? '—' : '${s.hrv!.round()} ${s.hrvKind ?? ''}'.trim()}',
  ].join(' · ');
}

/// Values a kind can plausibly hold, as the plugin gives them. Wide on
/// purpose: it catches a wrong unit (SpO₂ as 97 where 0.97 was expected is
/// fine either way; 9700 isn't), not a merely unusual night. Null: no check.
/// TODO(verify): units per platform, against a real phone.
(double, double)? plausible(HealthKind k) => switch (k) {
  HealthKind.heartRate => (25, 250),
  HealthKind.restingHr => (25, 130),
  HealthKind.steps => (0, 60000),
  HealthKind.hrvSdnn || HealthKind.hrvRmssd => (1, 300),
  // iOS gives a fraction, Health Connect a percent.
  HealthKind.spo2 => (0.5, 100),
  HealthKind.respiratoryRate => (3, 60),
  HealthKind.water => (0, 10),
  HealthKind.caffeine => (0, 2),
  // iOS: absolute °C; Health Connect: change from baseline.
  HealthKind.wristTemp => (-10, 45),
  _ => null,
};

/// Reads the last [window] of every kind straight from Health and compares
/// it with `health_records`, then follows last night and today through to
/// the minutes and scores. Read-only: writes nothing to the database or to
/// Health.
///
/// Records starting before the last read are compared one by one (by
/// [HealthRecord.key]); later ones are only counted, since the sync hasn't
/// had a chance to see them.
Future<HealthCheckReport> checkHealth(
  TempoDb db,
  HealthReader reader, {
  Duration window = const Duration(days: 7),
  DateTime? now,
}) async {
  final to = now ?? DateTime.now();
  final from = to.subtract(window);
  final lastRead = DateTime.tryParse(await db.setting(Keys.lastSync) ?? '');
  final access = await reader.hasAccess();
  HealthPermissions? permissions;
  try {
    permissions = await reader.permissions();
  } catch (_) {} // shown as unknown
  // Before the window or after now, a last read compares nothing.
  final cut = lastRead == null || lastRead.isBefore(from)
      ? from
      : lastRead.isAfter(to)
      ? to
      : lastRead;
  final storedByKind = <String, Set<String>>{};
  for (final r in await db.healthRecordsStarting(from, cut)) {
    storedByKind.putIfAbsent(r.kind, () => {}).add(r.key);
  }
  final kinds = reader.kinds.toList()..sort((a, b) => a.index - b.index);
  final out = <KindCheck>[];
  for (final kind in kinds) {
    List<HealthRecord> rs;
    try {
      rs = await reader.read(kind, from, to);
    } catch (e) {
      out.add(KindCheck(kind: kind, verdict: KindVerdict.failed, error: '$e'));
      continue;
    }
    final stored = storedByKind[kind.name] ?? const <String>{};
    final range = plausible(kind);
    bool isOdd(HealthRecord r) =>
        range != null && (r.value < range.$1 || r.value > range.$2);
    final checked = <CheckedRecord>[];
    final before = <String>{};
    var odd = 0;
    double? lo, hi;
    DateTime? latest;
    final sources = <String, int>{};
    for (final r in rs) {
      if (!HealthSyncService.usable(r)) {
        checked.add(CheckedRecord(r, RecordStatus.dropped));
        continue;
      }
      final early = r.start.isBefore(cut);
      if (early) before.add(r.key);
      final o = isOdd(r);
      checked.add(
        CheckedRecord(
          r,
          !early
              ? RecordStatus.newer
              : stored.contains(r.key)
              ? RecordStatus.stored
              : RecordStatus.missing,
          odd: o,
        ),
      );
      if (o) odd++;
      if (range != null) {
        lo = lo == null || r.value < lo ? r.value : lo;
        hi = hi == null || r.value > hi ? r.value : hi;
      }
      if (latest == null || r.end.isAfter(latest)) latest = r.end;
      sources[r.sourceApp] = (sources[r.sourceApp] ?? 0) + 1;
    }
    checked.sort((a, b) => b.record.start.compareTo(a.record.start));
    final usable = rs.length - checked.where(_dropped).length;
    final missing = before.difference(stored).length;
    final extra = stored.difference(before).length;
    out.add(
      KindCheck(
        kind: kind,
        verdict: rs.isEmpty && stored.isEmpty
            ? KindVerdict.empty
            : missing > 0
            ? KindVerdict.missing
            : odd > 0
            ? KindVerdict.odd
            : extra > 0
            ? KindVerdict.extra
            : KindVerdict.ok,
        inHealth: rs.length,
        dropped: rs.length - usable,
        stored: stored.length,
        missing: missing,
        extra: extra,
        newer: usable - before.length,
        odd: odd,
        latest: latest,
        min: lo,
        max: hi,
        sources: sources,
        recent: checked.take(KindCheck.recentLimit).toList(),
      ),
    );
  }
  return HealthCheckReport(
    from: from,
    to: to,
    lastRead: lastRead,
    access: access,
    kinds: out,
    permissions: permissions,
    pipeline: await checkPipeline(db, now: to),
  );
}

bool _dropped(CheckedRecord c) => c.status == RecordStatus.dropped;

/// Last night and today, from the stored records through the derived
/// minutes to the scores.
Future<PipelineCheck> checkPipeline(TempoDb db, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  final day0 = DateTime(t.year, t.month, t.day);
  final noon = day0.add(const Duration(hours: 12));
  final nightFrom = day0.subtract(const Duration(hours: 6));
  final nightTo = t.isBefore(noon) ? t : noon;

  // Asleep per the records: the union of non-awake stages, or of the
  // containers when no source wrote stages.
  final sleepRows = await db.healthRecordsBetween(
    nightFrom,
    nightTo,
    kinds: [
      for (final k in HealthKind.values)
        if (k.isSleep) k.name,
    ],
  );
  Set<int> covered(Iterable<HealthRecordRow> rows) {
    final a0 = nightFrom.millisecondsSinceEpoch ~/ 60000;
    final b0 = nightTo.millisecondsSinceEpoch ~/ 60000;
    return {
      for (final r in rows)
        for (
          var m = r.startMs ~/ 60000 < a0 ? a0 : r.startMs ~/ 60000;
          m < (r.endMs ~/ 60000 > b0 ? b0 : r.endMs ~/ 60000);
          m++
        )
          m,
    };
  }

  final stageRows = [
    for (final r in sleepRows)
      if (HealthKind.values.asNameMap()[r.kind] case final k?)
        if (k.isSleepStage && k != HealthKind.sleepAwake) r,
  ];
  final sleepRecordMin = covered(
    stageRows.isNotEmpty
        ? stageRows
        : [
            for (final r in sleepRows)
              if (HealthKind.values.asNameMap()[r.kind]?.isSleepContainer ??
                  false)
                r,
          ],
  ).length;
  final stages = <String, int>{};
  for (final m in await db.healthMinutesBetween(nightFrom, nightTo)) {
    if (m.sleep case final s?) stages[s] = (stages[s] ?? 0) + 1;
  }
  final sleepMin = stages.entries
      .where((e) => e.key != 'awake')
      .fold(0, (a, e) => a + e.value);

  final dayMins = await db.healthMinutesBetween(day0, t);
  final hrRecords = (await db.healthRecordsBetween(
    day0,
    t,
    kinds: [HealthKind.heartRate.name],
  )).where((r) => r.startMs >= day0.millisecondsSinceEpoch).length;
  final stepsBySource = <String, int>{};
  for (final r in await db.healthRecordsBetween(
    day0,
    t,
    kinds: [HealthKind.steps.name],
  )) {
    if (r.startMs < day0.millisecondsSinceEpoch) continue;
    stepsBySource[r.sourceApp] =
        (stepsBySource[r.sourceApp] ?? 0) + r.value.round();
  }

  return PipelineCheck(
    nightFrom: nightFrom,
    nightTo: nightTo,
    dayFrom: day0,
    dayTo: t,
    sleepRecordMin: sleepRecordMin,
    sleepMin: sleepMin,
    stages: stages,
    hrRecords: hrRecords,
    hrMeasuredMin: dayMins.where((m) => m.hrMeasured).length,
    hrMin: dayMins.where((m) => m.hr != null).length,
    stepsTempo: dayMins.fold(0, (a, m) => a + m.steps),
    stepsBySource: stepsBySource,
    chosen: {for (final m in SourceMetric.values) m: await metricSource(db, m)},
    today: await db.scoreFor(day0),
    yesterday: await db.scoreFor(day0.subtract(const Duration(days: 1))),
  );
}

/// Writes [text] to `health-checks/` in the app's documents folder (kept
/// on the phone; Profile → Export doesn't include it).
Future<File> saveHealthCheck(String text, {DateTime? at}) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/health-checks');
  await dir.create(recursive: true);
  final stamp = (at ?? DateTime.now())
      .toIso8601String()
      .split('.')
      .first
      .replaceAll(':', '-');
  return File('${dir.path}/health-check-$stamp.txt')..writeAsStringSync(text);
}
