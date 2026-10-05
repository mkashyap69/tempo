import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';

import 'band_link.dart';
import 'profile.dart' show Keys;

/// What the explorer needs from a band. [MiBand] provides it; tests fake it.
abstract interface class ExplorerBand {
  Future<Map<String, List<int>?>> readAllReadable();
  Future<FetchStartReply?> probeFetch(int code, DateTime since);
  Future<Stream<List<int>>> startLiveHrRaw();
  Future<void> stopLiveHr();
}

class _MiBandExplorer implements ExplorerBand {
  _MiBandExplorer(this.band);
  final MiBand band;
  @override
  Future<Map<String, List<int>?>> readAllReadable() => band.readAllReadable();
  @override
  Future<FetchStartReply?> probeFetch(int code, DateTime since) =>
      band.probeFetch(code, since);
  @override
  Future<Stream<List<int>>> startLiveHrRaw() => band.startLiveHrRaw();
  @override
  Future<void> stopLiveHr() => band.stopLiveHr();
}

enum ExplorerStage { characteristics, history, liveHr }

/// One history type the band answered for.
final class ProbeResult {
  const ProbeResult(this.code, {required this.ok, this.count = 0, this.start});
  final int code;
  final bool ok;
  final int count;
  final DateTime? start;

  /// Name if Tempo already knows this type.
  String? get known => FetchType.values
      .where((t) => t.code == code)
      .map((t) => t.key)
      .firstOrNull;

  Map<String, Object?> toJson() => {
    'code': '0x${code.toRadixString(16).padLeft(2, '0')}',
    'known': known,
    'ok': ok,
    'count': count,
    'start': start?.toIso8601String(),
  };
}

/// Everything one explorer run found. Raw bytes are also in the packet log.
final class ExplorerReport {
  ExplorerReport({
    required this.at,
    required this.firmware,
    required this.characteristics,
    required this.probes,
    required this.silent,
    required this.hrPackets,
    required this.bpm,
    required this.rrMs,
    this.packetLog,
  });
  final DateTime at;
  final String? firmware;
  final Map<String, List<int>?> characteristics;
  final List<ProbeResult> probes;
  final List<int> silent;
  final List<List<int>> hrPackets;
  final List<int> bpm;
  final List<int> rrMs;
  final String? packetLog;

  int get packetsWithRr =>
      hrPackets.where((p) => p.isNotEmpty && p[0] & 0x10 != 0).length;
  bool get hasRr => rrMs.isNotEmpty;
  double? get rmssd => sc.rmssd(rrMs);

  /// History types with data that Tempo doesn't sync yet.
  List<ProbeResult> get newWithData => [
    for (final p in probes)
      if (p.ok && p.count > 0 && p.known == null) p,
  ];

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'firmware': firmware,
    'packetLog': packetLog,
    'characteristics': {
      for (final e in characteristics.entries)
        e.key: e.value == null ? null : hex(e.value!),
    },
    'history': [for (final p in probes) p.toJson()],
    'silentCodes': [for (final c in silent) '0x${c.toRadixString(16)}'],
    'liveHr': {
      'packets': hrPackets.length,
      'packetsWithRr': packetsWithRr,
      'bpm': bpm,
      'rrMs': rrMs,
      'rmssd': rmssd,
      'raw': [for (final p in hrPackets.take(300)) hex(p)],
    },
  };
}

typedef ExplorerProgress = void Function(
  ExplorerStage stage,
  double fraction,
  String detail,
);

/// Read-only survey of what the band holds: every readable characteristic,
/// which history type codes answer (never transferred or acknowledged, so
/// nothing is deleted on the band), and raw live-HR notifications to see
/// whether beat-to-beat (RR) intervals are present.
class BandExplorer {
  BandExplorer({
    List<int>? codes,
    this.hrFor = const Duration(minutes: 2),
    this.since,
  }) : codes = codes ?? [for (var c = 0; c < 0x40; c++) c];
  final List<int> codes;
  final Duration hrFor;
  final DateTime? since;

  Future<ExplorerReport> run(
    ExplorerBand band, {
    String? firmware,
    String? packetLog,
    ExplorerProgress? onProgress,
    bool Function()? cancelled,
  }) async {
    bool stop() => cancelled?.call() ?? false;
    onProgress?.call(ExplorerStage.characteristics, 0, 'Reading…');
    final chars = await band.readAllReadable();
    onProgress?.call(
      ExplorerStage.characteristics,
      1,
      '${chars.values.whereType<List<int>>().length} of ${chars.length} read',
    );

    final from = since ?? DateTime.now().subtract(const Duration(days: 30));
    final probes = <ProbeResult>[];
    final silent = <int>[];
    for (final (i, code) in codes.indexed) {
      if (stop()) break;
      onProgress?.call(
        ExplorerStage.history,
        i / codes.length,
        'Type 0x${code.toRadixString(16).padLeft(2, '0')} · ${probes.where((p) => p.count > 0).length} with data',
      );
      final r = await band.probeFetch(code, from);
      if (r == null) {
        silent.add(code);
      } else {
        probes.add(ProbeResult(code, ok: r.ok, count: r.count, start: r.start));
      }
    }
    onProgress?.call(
      ExplorerStage.history,
      1,
      '${probes.where((p) => p.count > 0).length} types with data',
    );

    final packets = <List<int>>[];
    final bpm = <int>[];
    final rr = <int>[];
    if (!stop()) {
      final stream = await band.startLiveHrRaw();
      final sub = stream.listen((p) {
        packets.add(p);
        final m = parseHrMeasurement(p);
        if (m != null) {
          bpm.add(m.bpm);
          rr.addAll(m.rrMs);
        }
      });
      final t0 = DateTime.now();
      while (!stop()) {
        final el = DateTime.now().difference(t0);
        if (el >= hrFor) break;
        onProgress?.call(
          ExplorerStage.liveHr,
          el.inMilliseconds / hrFor.inMilliseconds,
          '${packets.length} readings${rr.isEmpty ? '' : ' · ${rr.length} beat intervals'}',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await sub.cancel();
      try {
        await band.stopLiveHr();
      } catch (_) {}
      onProgress?.call(
        ExplorerStage.liveHr,
        1,
        rr.isEmpty ? 'No beat intervals' : '${rr.length} beat intervals',
      );
    }
    return ExplorerReport(
      at: DateTime.now(),
      firmware: firmware,
      characteristics: chars,
      probes: probes,
      silent: silent,
      hrPackets: packets,
      bpm: bpm,
      rrMs: rr,
      packetLog: packetLog,
    );
  }
}

/// Runs the explorer on the paired band and saves the report next to the
/// packet logs. Returns the report and its file.
Future<(ExplorerReport, File)> exploreBand(
  TempoDb db, {
  ExplorerProgress? onProgress,
  bool Function()? cancelled,
}) async {
  final link = await BandLink.open(db);
  ExplorerReport report;
  try {
    report = await BandExplorer().run(
      _MiBandExplorer(link.band),
      firmware: await db.setting(Keys.firmware),
      packetLog: link.log.file.path,
      onProgress: onProgress,
      cancelled: cancelled,
    );
  } finally {
    await link.close();
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/packets');
  await dir.create(recursive: true);
  final stamp = report.at.toUtc().toIso8601String().replaceAll(':', '-');
  final f = File('${dir.path}/explorer-$stamp.json');
  await f.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  await db.logSync(
    'Band explorer · ${report.probes.where((p) => p.count > 0).length} history types with data · ${report.hasRr ? 'beat intervals found' : 'no beat intervals'}',
    'explore',
  );
  return (report, f);
}
