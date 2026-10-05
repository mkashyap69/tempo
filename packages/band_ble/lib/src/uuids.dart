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

  // Huami vendor service with config, fetch and user-info characteristics.
  static final huamiService0 = _sig('fee0'); // TODO(verify)
  static const config = '00000003-0000-3512-2118-0009af100700'; // TODO(verify)
  static const fetchControl =
      '00000004-0000-3512-2118-0009af100700'; // TODO(verify)
  static const activityData =
      '00000005-0000-3512-2118-0009af100700'; // TODO(verify)
  static const userSettings =
      '00000008-0000-3512-2118-0009af100700'; // TODO(verify)
  static final currentTime = _sig('2a2b'); // TODO(verify)

  // Chunked transfer. Present on the V1.0.6.20 GATT dump (2026-10-04).
  static const chunkedWrite =
      '00000016-0000-3512-2118-0009af100700'; // TODO(verify) auth bytes
  static const chunkedRead = '00000017-0000-3512-2118-0009af100700';

  // Battery: SIG Battery Level, else the Huami battery-info characteristic.
  static final batteryLevel = _sig('2a19'); // TODO(verify)
  static const huamiBattery =
      '00000006-0000-3512-2118-0009af100700'; // TODO(verify) layout

  // Today's steps, metres and kcal (read). Confirmed on V1.0.6.20 by the
  // explorer capture (docs/packets/explorer-2026-10-05T10-34-28.json).
  static const realtimeSteps = '00000007-0000-3512-2118-0009af100700';

  // SIG Alert Notification service: text alerts on the band (C6).
  static final alertNotificationService = _sig('1811'); // TODO(verify)
  static final newAlert = _sig('2a46'); // TODO(verify)

  // SIG Immediate Alert: used to buzz the band before an interval change.
  static final alertLevel = _sig('2a06'); // TODO(verify)
}

/// Advertised names we accept in the scan list. TODO(verify) against a scan.
const bandNameHints = ['Mi Smart Band 6', 'Mi Band 6'];
