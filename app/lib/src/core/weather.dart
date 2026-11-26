import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:store/store.dart' as st;

import 'net_ledger.dart';

import 'profile.dart';

/// Weather on Today (D3, decisions.md 2026-11-24): the sky over you,
/// drawn behind Today. Off by default. When on, Tempo sends Open-Meteo only
/// a location rounded to 0.1° (about 11 km) and no more than once in 3
/// hours; no health data, no account, no id. The answer stays on the phone.

enum Sky { clear, partly, cloudy, fog, drizzle, rain, snow, storm }

/// WMO weather interpretation codes, as Open-Meteo returns them.
Sky skyFromWmo(int code) => switch (code) {
  0 => Sky.clear,
  1 || 2 => Sky.partly,
  3 => Sky.cloudy,
  45 || 48 => Sky.fog,
  >= 51 && <= 57 => Sky.drizzle,
  (>= 61 && <= 67) || (>= 80 && <= 82) => Sky.rain,
  (>= 71 && <= 77) || 85 || 86 => Sky.snow,
  >= 95 && <= 99 => Sky.storm,
  _ => Sky.cloudy,
};

String skyWord(Sky s) => switch (s) {
  Sky.clear => 'Clear',
  Sky.partly => 'Some cloud',
  Sky.cloudy => 'Cloudy',
  Sky.fog => 'Fog',
  Sky.drizzle => 'Drizzle',
  Sky.rain => 'Rain',
  Sky.snow => 'Snow',
  Sky.storm => 'Storm',
};

/// A location rounded to 0.1°: all Tempo ever sends.
double coarse(double deg) => (deg * 10).round() / 10;

Uri weatherUri(double lat, double lon) =>
    Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': coarse(lat).toStringAsFixed(1),
      'longitude': coarse(lon).toStringAsFixed(1),
      'current': 'weather_code,is_day',
    });

typedef Weather = ({Sky sky, bool day, DateTime at});

/// Reads Open-Meteo's answer; null when it isn't one.
Weather? parseWeather(String body, DateTime at) {
  try {
    final cur = (jsonDecode(body) as Map)['current'] as Map;
    return (
      sky: skyFromWmo((cur['weather_code'] as num).toInt()),
      day: (cur['is_day'] as num? ?? 1) != 0,
      at: at,
    );
  } catch (_) {
    return null;
  }
}

/// How long a lookup is used before asking again, and the oldest one shown
/// when a new one fails.
const weatherFresh = Duration(hours: 3), weatherStale = Duration(hours: 12);

Weather? _cached(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw) as Map;
    final sky = Sky.values.asNameMap()[j['sky']];
    final at = DateTime.tryParse('${j['at']}');
    if (sky == null || at == null) return null;
    return (sky: sky, day: j['day'] == true, at: at);
  } catch (_) {
    return null;
  }
}

Future<bool> weatherOn(st.TempoDb db) async =>
    await db.setting(Keys.weather) == '1';

/// Turns weather on (asking for location once) or off. Returns whether
/// it's on afterwards.
Future<bool> setWeather(st.TempoDb db, bool on) async {
  if (!on) {
    await db.putSetting(Keys.weather, '0');
    await db.deleteSetting(Keys.weatherLast);
    return false;
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  final ok =
      p == LocationPermission.whileInUse || p == LocationPermission.always;
  await db.putSetting(Keys.weather, ok ? '1' : '0');
  return ok;
}

/// The sky now: the cached lookup while fresh, else a new one. Null when
/// weather is off, or nothing could be read and nothing recent is cached.
/// [fetch] is for tests.
Future<Weather?> currentWeather(
  st.TempoDb db, {
  DateTime? now,
  Future<String?> Function(Uri uri)? fetch,
  Future<(double, double)?> Function()? locate,
}) async {
  if (!await weatherOn(db)) return null;
  final t = now ?? DateTime.now();
  final had = _cached(await db.setting(Keys.weatherLast));
  if (had != null && t.difference(had.at) < weatherFresh) return had;
  final where = await (locate ?? _locate)();
  String? body;
  if (where != null) {
    // v3 ledger: counted whether or not the lookup succeeds.
    await recordNetCall(db, 'weather', at: t);
    body = await (fetch ?? _get)(weatherUri(where.$1, where.$2));
  }
  final w = body == null ? null : parseWeather(body, t);
  if (w == null) {
    return had != null && t.difference(had.at) < weatherStale ? had : null;
  }
  await db.putSetting(
    Keys.weatherLast,
    jsonEncode({'sky': w.sky.name, 'day': w.day, 'at': t.toIso8601String()}),
  );
  return w;
}

Future<(double, double)?> _locate() async {
  try {
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
      return null;
    }
    final pos =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
    return (pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

Future<String?> _get(Uri uri) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    return await res.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}
