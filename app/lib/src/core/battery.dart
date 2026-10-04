import 'dart:convert';

import 'package:store/store.dart';

import 'profile.dart' show Keys;

/// One battery reading.
typedef BatteryPoint = (DateTime, int);

/// Adds a reading to the log kept in settings: at most one an hour, the
/// newest 120. Charging shows up as a rise and starts a new discharge run.
Future<void> recordBattery(TempoDb db, int pct, {DateTime? at}) async {
  final now = at ?? DateTime.now();
  final log = await batteryLog(db);
  if (log.isNotEmpty && now.difference(log.last.$1).inMinutes < 60) {
    log.removeLast();
  }
  log.add((now, pct));
  final keep = log.length > 120 ? log.sublist(log.length - 120) : log;
  await db.putSetting(
    Keys.batteryLog,
    jsonEncode([
      for (final (t, p) in keep) [t.millisecondsSinceEpoch ~/ 1000, p],
    ]),
  );
  await db.putSetting(Keys.battery, '$pct');
  await db.putSetting(Keys.batteryAt, now.toIso8601String());
}

Future<List<BatteryPoint>> batteryLog(TempoDb db) async {
  final raw = await db.setting(Keys.batteryLog);
  if (raw == null || raw.isEmpty) return [];
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        (
          DateTime.fromMillisecondsSinceEpoch((e[0] as int) * 1000),
          e[1] as int,
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// Days until empty from the drain since the last charge: a least-squares
/// slope over the current discharge run. Needs a day of readings and a
/// real drop; otherwise null (the UI says "learning").
double? batteryDaysLeft(List<BatteryPoint> log) {
  if (log.length < 2) return null;
  // Current run: back from the newest reading until the level rises.
  var i = log.length - 1;
  while (i > 0 && log[i - 1].$2 >= log[i].$2) {
    i--;
  }
  final run = log.sublist(i);
  if (run.length < 2) return null;
  final t0 = run.first.$1;
  final span = run.last.$1.difference(t0).inMinutes / 1440;
  if (span < 1) return null;
  final xs = [for (final p in run) p.$1.difference(t0).inMinutes / 1440];
  final ys = [for (final p in run) p.$2.toDouble()];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var num = 0.0, den = 0.0;
  for (var k = 0; k < xs.length; k++) {
    num += (xs[k] - mx) * (ys[k] - my);
    den += (xs[k] - mx) * (xs[k] - mx);
  }
  if (den == 0) return null;
  final perDay = -num / den;
  if (perDay < 0.5) return null; // flat: not enough drop to say
  return run.last.$2 / perDay;
}

/// "~9 days left" / "learning drain" for the battery tiles.
String batteryLeftLabel(double? days) => days == null
    ? 'learning drain rate'
    : days < 1
    ? 'under a day left'
    : '~${days.round()} ${days.round() == 1 ? 'day' : 'days'} left';
