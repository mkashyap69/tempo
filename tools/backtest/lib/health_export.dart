/// Streaming reader for Apple Health `export.xml`. Records are one per line
/// in practice, so a line regex avoids loading a multi-GB DOM.
library;

import 'dart:convert';
import 'dart:io';

import 'package:scoring/scoring.dart';

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

Stage? sleepStage(String value) => switch (value) {
  'HKCategoryValueSleepAnalysisAsleep' ||
  'HKCategoryValueSleepAnalysisAsleepUnspecified' ||
  'HKCategoryValueSleepAnalysisAsleepCore' => Stage.light,
  'HKCategoryValueSleepAnalysisAsleepDeep' => Stage.deep,
  'HKCategoryValueSleepAnalysisAsleepREM' => Stage.rem,
  'HKCategoryValueSleepAnalysisAwake' => Stage.wake,
  _ => null, // InBed carries no stage
};

/// Per-minute accumulator keyed by minutes since epoch (local time).
class MinuteGrid {
  final hrSum = <int, int>{};
  final hrN = <int, int>{};
  final stage = <int, Stage>{};

  static int key(DateTime t) => t.toLocal().millisecondsSinceEpoch ~/ 60000;

  void addHr(DateTime t, int bpm) {
    final k = key(t);
    hrSum[k] = (hrSum[k] ?? 0) + bpm;
    hrN[k] = (hrN[k] ?? 0) + 1;
  }

  void addStage(DateTime start, DateTime end, Stage s) {
    for (var k = key(start); k < key(end); k++) {
      // A real sleep stage beats "awake" when sources overlap.
      if (stage[k] == null || stage[k] == Stage.wake) stage[k] = s;
    }
  }

  /// Minutes in [from, to). Gaps in HR up to [fillMinutes] are forward-filled
  /// because Mi Fit wrote HR to Health only every few minutes.
  List<Minute> range(DateTime from, DateTime to, {int fillMinutes = 0}) {
    final out = <Minute>[];
    int? last;
    var lastAt = -1 << 40;
    for (var k = key(from); k < key(to); k++) {
      final n = hrN[k];
      int? hr;
      if (n != null) {
        hr = (hrSum[k]! / n).round();
        last = hr;
        lastAt = k;
      } else if (last != null && k - lastAt <= fillMinutes) {
        hr = last;
      }
      out.add(
        Minute(
          DateTime.fromMillisecondsSinceEpoch(k * 60000),
          hr: hr,
          stage: stage[k] ?? Stage.unknown,
        ),
      );
    }
    return out;
  }

  DateTime? get first => hrN.isEmpty
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          hrN.keys.reduce((a, b) => a < b ? a : b) * 60000,
        );
  DateTime? get last => hrN.isEmpty
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          hrN.keys.reduce((a, b) => a > b ? a : b) * 60000,
        );
}

/// Reads HR and sleep records whose sourceName matches [source].
Future<MinuteGrid> readExport(Stream<String> lines, RegExp source) async {
  final grid = MinuteGrid();
  await for (final line in lines) {
    if (!line.contains('<Record ')) continue;
    final isHr = line.contains('"HKQuantityTypeIdentifierHeartRate"');
    final isSleep = line.contains('"HKCategoryTypeIdentifierSleepAnalysis"');
    if (!isHr && !isSleep) continue;
    final a = {
      for (final m in _attr.allMatches(line)) m.group(1)!: m.group(2)!,
    };
    if (!source.hasMatch(a['sourceName'] ?? '')) continue;
    final start = parseHealthDate(a['startDate']!);
    if (isHr) {
      final v = double.tryParse(a['value'] ?? '');
      if (v != null) grid.addHr(start, v.round());
    } else {
      final s = sleepStage(a['value'] ?? '');
      if (s != null) grid.addStage(start, parseHealthDate(a['endDate']!), s);
    }
  }
  return grid;
}

Stream<String> fileLines(String path) =>
    File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
