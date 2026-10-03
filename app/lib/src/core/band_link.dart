import 'package:band_ble/band_ble.dart';
import 'package:store/store.dart';

import 'key_store.dart';
import 'packet_file_log.dart';

const deviceIdKey = 'device_id';
const deviceNameKey = 'device_name';

class NotPairedException implements Exception {
  @override
  String toString() => 'No band paired yet.';
}

/// A connected, authenticated band plus its packet log for this session.
class BandLink {
  BandLink._(this.band, this.log);

  final MiBand band;
  final PacketFileLog log;

  /// Connects to the paired band and authenticates.
  static Future<BandLink> open(TempoDb db, {KeyStore? keys}) async {
    final id = await db.setting(deviceIdKey);
    final key = await (keys ?? KeyStore()).load();
    if (id == null || key == null) throw NotPairedException();
    final log = await PacketFileLog.open();
    final band = MiBand.fromId(id, log: log);
    try {
      await band.connect();
      await band.readFirmware(); // logged on every connect (PLAN.md → Risks)
      await band.authenticate(key);
      return BandLink._(band, log);
    } catch (_) {
      try {
        await band.disconnect();
      } catch (_) {}
      await log.close();
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await band.disconnect();
    } finally {
      await log.close();
    }
  }
}
