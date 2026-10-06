import 'dart:io';

import 'package:band_ble/band_ble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart';

import 'key_store.dart';
import 'packet_file_log.dart';
import 'profile.dart' show Keys;

const deviceIdKey = 'device_id';
const deviceNameKey = 'device_name';

class NotPairedException implements Exception {
  @override
  String toString() => 'No band paired yet.';
}

class BandBusyException implements Exception {
  @override
  String toString() => 'The band is already in use. Wait for sync to finish.';
}

/// A connected, authenticated band plus its packet log for this session.
class BandLink {
  BandLink._(this.band, this.log, this._lock);

  final MiBand band;
  final PacketFileLog log;
  final File _lock;

  /// Connects to the paired band and authenticates.
  /// One session at a time: the UI sync and the background job share the radio.
  static Future<BandLink> open(
    TempoDb db, {
    KeyStore? keys,
    Duration wait = const Duration(seconds: 40),
  }) async {
    final id = await db.setting(deviceIdKey);
    final key = await (keys ?? KeyStore()).load();
    if (id == null || key == null) throw NotPairedException();
    final docs = await getApplicationDocumentsDirectory();
    final lock = await acquireFileLock(
      File('${docs.path}/band.lock'),
      wait,
      onBusy: BandBusyException.new,
    );
    final log = await PacketFileLog.open();
    final band = MiBand.fromId(id, log: log);
    try {
      await band.connect();
      // Logged on every connect (PLAN.md → Risks).
      final fw = await band.readFirmware();
      if (fw.isNotEmpty) await db.putSetting(Keys.firmware, fw);
      await band.authenticate(key);
      return BandLink._(band, log, lock);
    } catch (_) {
      try {
        await band.disconnect();
      } catch (_) {}
      await log.close();
      await releaseFileLock(lock);
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await band.disconnect();
    } finally {
      await log.close();
      await releaseFileLock(_lock);
    }
  }
}

/// Exclusive create. flock() did not keep the background job off the radio.
/// A lock older than 3 minutes is stale (a killed process) and taken over.
Future<File> acquireFileLock(
  File f,
  Duration wait, {
  required Exception Function() onBusy,
}) async {
  final deadline = DateTime.now().add(wait);
  while (true) {
    try {
      final created = await f.create(exclusive: true);
      await created.writeAsString(DateTime.now().toIso8601String());
      return created;
    } on FileSystemException {
      DateTime? modified;
      try {
        modified = await f.lastModified();
      } catch (_) {}
      if (modified != null &&
          DateTime.now().difference(modified) > const Duration(minutes: 3)) {
        try {
          await f.delete();
        } catch (_) {}
        continue;
      }
      if (!DateTime.now().isBefore(deadline)) throw onBusy();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
}

Future<void> releaseFileLock(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
