import 'package:drift/drift.dart' show Value;
import 'package:health_source/health_source.dart' as hs;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'data_source.dart';
import 'stages.dart';

/// Per-minute data from the active source, as scoring sees it: decoded and
/// staged band minutes, or the minutes derived from Health records. Every
/// screen and service that needs minutes reads them through here, so none
/// of them has to know where the data came from.
Future<DecodedMinutes> loadMinutes(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  if (!s.isHealth) return decodeMinutes(await db.minutesBetween(from, to));
  final x = hs.scoringMinutes([
    for (final r in await db.healthMinutesBetween(from, to)) healthMinuteOf(r),
  ]);
  return (minutes: x.minutes, unstaged: x.unstaged);
}

hs.HealthMinute healthMinuteOf(st.HealthMinuteRow r) => hs.HealthMinute(
  st.fromTs(r.ts),
  steps: r.steps,
  hr: r.hr,
  hrMeasured: r.hrMeasured,
  sleep: r.sleep == null ? null : hs.SleepMark.values.asNameMap()[r.sleep],
  spo2: r.spo2,
);

st.HealthMinutesCompanion healthMinuteRow(hs.HealthMinute m) =>
    st.HealthMinutesCompanion.insert(
      ts: Value(st.toTs(m.ts)),
      steps: m.steps,
      hr: Value(m.hr),
      hrMeasured: m.hrMeasured,
      sleep: Value(m.sleep?.name),
      spo2: Value(m.spo2),
    );

/// The band's stress readings; none for a Health source.
Future<List<st.StressSample>> loadStress(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  return s.isHealth ? const [] : db.stressBetween(from, to);
}

/// SpO₂ readings: the band's, or per-minute means from Health (no
/// quality value).
Future<List<st.Spo2Sample>> loadSpo2(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  if (!s.isHealth) return db.spo2Between(from, to);
  return [
    for (final r in await db.healthMinutesBetween(from, to))
      if (r.spo2 != null) st.Spo2Sample(ts: r.ts, value: r.spo2!),
  ];
}

/// The band's desaturation events; none for a Health source.
Future<List<st.OdEventRow>> loadOdEvents(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  return s.isHealth ? const [] : db.odEventsBetween(from, to);
}

/// Health records for [from, to) as health_source records.
Future<List<hs.HealthRecord>> loadHealthRecords(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  Iterable<hs.HealthKind>? kinds,
}) async => [
  for (final r in await db.healthRecordsBetween(
    from,
    to,
    kinds: kinds?.map((k) => k.name),
  ))
    ?healthRecordOf(r),
];

hs.HealthRecord? healthRecordOf(st.HealthRecordRow r) {
  final kind = hs.HealthKind.values.asNameMap()[r.kind];
  if (kind == null) return null;
  return hs.HealthRecord(
    uuid: r.uuid,
    kind: kind,
    start: DateTime.fromMillisecondsSinceEpoch(r.startMs),
    end: DateTime.fromMillisecondsSinceEpoch(r.endMs),
    value: r.value,
    sourceApp: r.sourceApp,
    extra: r.extra,
  );
}

/// First minute with data from the active source.
Future<DateTime?> firstDataMinute(st.TempoDb db, {DataSource? source}) async {
  final s = source ?? await loadDataSource(db);
  return db.firstMinute(health: s.isHealth);
}

/// Whether the active source has any data in [from, to).
Future<bool> hasDataBetween(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  return await db.minuteCount(from, to, health: s.isHealth) > 0;
}

/// Minutes of [sc.Minute] in [from, to) only, from a wider list.
List<sc.Minute> within(List<sc.Minute> xs, DateTime from, DateTime to) => [
  for (final m in xs)
    if (!m.ts.isBefore(from) && m.ts.isBefore(to)) m,
];

/// Rows with each minute's time, steps and heart rate, for charts that
/// need only those. With a Health source the rows are built from the
/// derived Health minutes; their `kind` means nothing, so never pass them
/// to [decodeMinutes] (use [loadMinutes] for stages).
Future<List<st.MinuteSample>> loadMinuteRows(
  st.TempoDb db,
  DateTime from,
  DateTime to, {
  DataSource? source,
}) async {
  final s = source ?? await loadDataSource(db);
  if (!s.isHealth) return db.minutesBetween(from, to);
  return [
    for (final r in await db.healthMinutesBetween(from, to))
      st.MinuteSample(
        ts: r.ts,
        steps: r.steps,
        intensity: 0,
        kind: -1,
        hr: r.hr,
      ),
  ];
}
