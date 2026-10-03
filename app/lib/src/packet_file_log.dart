import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:path_provider/path_provider.dart';

/// Writes each BLE packet as one JSON line to
/// `<app documents>/packets/<session>.jsonl`. Pull them into the repo's
/// docs/packets/ with tools/pull_packets.sh.
class PacketFileLog implements PacketLog {
  PacketFileLog._(this.file, this._sink);

  final File file;
  final IOSink _sink;

  static Future<PacketFileLog> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/packets');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/${Platform.operatingSystem}-$stamp.jsonl');
    return PacketFileLog._(file, file.openWrite(mode: FileMode.append));
  }

  @override
  void record(PacketEvent e) => _sink.writeln(e.toJsonLine());

  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}
