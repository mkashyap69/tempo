/// Streaming reader for Apple Health `export.xml`. Records are one per line
/// in practice, so a line regex avoids loading a multi-GB DOM. Records go
/// through the same `health_source` mapping the app uses when it reads
/// Apple Health directly, so the backtest scores what the app would.
library;

import 'dart:convert';
import 'dart:io';

import 'package:health_source/health_source.dart';

final _attr = RegExp(r'(\w+)="([^"]*)"');

/// `2020-01-01 08:00:00 +0530` → UTC instant.
DateTime parseHealthDate(String s) {
  final m = RegExp(
    r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) ([+-])(\d\d)(\d\d)$',
  ).firstMatch(s.trim());
  if (m == null) throw FormatException('bad date', s);
  int g(int i) => int.parse(m.group(i)!);
  final off =
      Duration(hours: g(8), minutes: g(9)) * (m.group(7) == '-' ? -1 : 1);
  return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).subtract(off);
}

/// export.xml sleep value → kind. In bed is a container (see HealthGrid).
HealthKind? sleepKind(String value) => switch (value) {
  'HKCategoryValueSleepAnalysisInBed' => HealthKind.sleepInBed,
  'HKCategoryValueSleepAnalysisAsleep' ||
  'HKCategoryValueSleepAnalysisAsleepUnspecified' => HealthKind.sleepAsleep,
  'HKCategoryValueSleepAnalysisAsleepCore' => HealthKind.sleepLight,
  'HKCategoryValueSleepAnalysisAsleepDeep' => HealthKind.sleepDeep,
  'HKCategoryValueSleepAnalysisAsleepREM' => HealthKind.sleepRem,
  'HKCategoryValueSleepAnalysisAwake' => HealthKind.sleepAwake,
  _ => null,
};

const _quantity = {
  'HKQuantityTypeIdentifierHeartRate': HealthKind.heartRate,
  'HKQuantityTypeIdentifierStepCount': HealthKind.steps,
  'HKQuantityTypeIdentifierHeartRateVariabilitySDNN': HealthKind.hrvSdnn,
  'HKQuantityTypeIdentifierRestingHeartRate': HealthKind.restingHr,
  'HKQuantityTypeIdentifierOxygenSaturation': HealthKind.spo2,
};

/// One export.xml `<Record …/>` line as a record, or null for other types.
HealthRecord? recordFromXml(String line) {
  if (!line.contains('<Record ')) return null;
  final a = {for (final m in _attr.allMatches(line)) m.group(1)!: m.group(2)!};
  final type = a['type'];
  if (type == null) return null;
  final start = a['startDate'], end = a['endDate'];
  if (start == null || end == null) return null;
  HealthKind? kind;
  var value = 0.0;
  if (type == 'HKCategoryTypeIdentifierSleepAnalysis') {
    kind = sleepKind(a['value'] ?? '');
  } else {
    kind = _quantity[type];
    final v = double.tryParse(a['value'] ?? '');
    if (v == null) return null;
    value = v;
  }
  if (kind == null) return null;
  final from = parseHealthDate(start), to = parseHealthDate(end);
  return HealthRecord(
    uuid: '${a['sourceName']}|$start',
    kind: kind,
    start: from,
    end: to,
    value: kind.isSleep ? to.difference(from).inSeconds / 60 : value,
    sourceApp: a['sourceName'] ?? '',
  );
}

/// The per-minute grid, plus HRV and resting-HR records (few, kept whole).
final class ExportData {
  ExportData(this.grid);
  final HealthGrid grid;
  final vitals = <HealthRecord>[];
}

/// Reads records whose sourceName matches [source].
Future<ExportData> readExport(
  Stream<String> lines,
  RegExp source, {
  GridParams params = const GridParams(),
}) async {
  final out = ExportData(HealthGrid(params));
  await for (final line in lines) {
    final r = recordFromXml(line);
    if (r == null || !source.hasMatch(r.sourceApp)) continue;
    if (r.kind == HealthKind.hrvSdnn || r.kind == HealthKind.restingHr) {
      out.vitals.add(r);
    } else {
      out.grid.add(r);
    }
  }
  return out;
}

Stream<String> fileLines(String path) =>
    File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
