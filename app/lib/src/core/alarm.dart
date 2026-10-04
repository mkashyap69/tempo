import 'package:band_ble/band_ble.dart';
import 'package:store/store.dart';

import 'band_link.dart';
import 'profile.dart' show Keys;
import 'today.dart' show fmtHm, parseHm;

/// Band alarm slot Tempo owns. Other slots are left alone.
const smartAlarmSlot = 0;

/// Writes the smart alarm to the band (every day at [minute]; null = off)
/// and remembers it. The band vibrates up to 30 min early when it sees
/// light sleep. Returns the message to show.
Future<String> writeSmartAlarm(TempoDb db, int? minute) async {
  final link = await BandLink.open(db);
  try {
    final m = minute ?? parseHm(await db.setting(Keys.smartAlarm)) ?? 420;
    await link.band.setAlarm(
      BandAlarm(
        slot: smartAlarmSlot,
        hour: m ~/ 60,
        minute: m % 60,
        enabled: minute != null,
        days: 0x7f,
      ),
    );
  } finally {
    await link.close();
  }
  await db.putSetting(Keys.smartAlarm, minute == null ? 'off' : fmtHm(minute));
  return minute == null
      ? 'Smart alarm off'
      : 'Smart alarm set for ${fmtHm(minute)} on the band';
}
