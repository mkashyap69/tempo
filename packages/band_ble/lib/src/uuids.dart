/// Every UUID here is from public protocol descriptions, not yet confirmed
/// on our band. Each stays `TODO(verify)` until a log in docs/packets/
/// shows it in the discovered GATT table.
library;

String _sig(String short) => '0000$short-0000-1000-8000-00805f9b34fb';

abstract final class BandUuids {
  // Bluetooth SIG Heart Rate service.
  static final heartRateService = _sig('180d'); // TODO(verify)
  static final heartRateMeasurement = _sig('2a37'); // TODO(verify)
  static final heartRateControlPoint = _sig('2a39'); // TODO(verify)

  // Bluetooth SIG Device Information service.
  static final deviceInfoService = _sig('180a'); // TODO(verify)
  static final firmwareRevision = _sig('2a26'); // TODO(verify)
  static final softwareRevision = _sig('2a28'); // TODO(verify)

  // Huami vendor service that carries the auth characteristic.
  static final huamiService1 = _sig('fee1'); // TODO(verify)
  static const auth = '00000009-0000-3512-2118-0009af100700'; // TODO(verify)
}

/// Advertised names we accept in the scan list. TODO(verify) against a scan.
const bandNameHints = ['Mi Smart Band 6', 'Mi Band 6'];
