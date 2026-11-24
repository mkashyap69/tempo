import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/core/weather.dart';

void main() {
  test('WMO codes map to skies', () {
    expect(skyFromWmo(0), Sky.clear);
    expect(skyFromWmo(2), Sky.partly);
    expect(skyFromWmo(3), Sky.cloudy);
    expect(skyFromWmo(45), Sky.fog);
    expect(skyFromWmo(53), Sky.drizzle);
    expect(skyFromWmo(63), Sky.rain);
    expect(skyFromWmo(81), Sky.rain);
    expect(skyFromWmo(73), Sky.snow);
    expect(skyFromWmo(86), Sky.snow);
    expect(skyFromWmo(95), Sky.storm);
  });

  test('only a location rounded to 0.1° leaves the phone', () {
    final u = weatherUri(51.50735, -0.12776);
    expect(u.host, 'api.open-meteo.com');
    expect(u.queryParameters['latitude'], '51.5');
    expect(u.queryParameters['longitude'], '-0.1');
    expect(u.queryParameters.keys.toSet(), {
      'latitude',
      'longitude',
      'current',
    });
  });

  test('parses the answer; junk is null', () {
    final at = DateTime(2026, 11, 24, 9);
    final w = parseWeather(
      '{"current":{"time":"2026-11-24T09:00","weather_code":61,"is_day":1}}',
      at,
    )!;
    expect((w.sky, w.day), (Sky.rain, true));
    expect(parseWeather('not json', at), isNull);
  });

  group('lookups', () {
    late TempoDb db;
    setUp(() => db = TempoDb(NativeDatabase.memory()));
    tearDown(() => db.close());
    final t0 = DateTime(2026, 11, 24, 9);
    Future<(double, double)?> here() async => (51.5, -0.1);

    test('off: nothing is fetched', () async {
      var calls = 0;
      final w = await currentWeather(
        db,
        now: t0,
        locate: here,
        fetch: (_) async {
          calls++;
          return null;
        },
      );
      expect(w, isNull);
      expect(calls, 0);
    });

    test(
      'on: fetched once, reused for 3 hours, kept 12 when offline',
      () async {
        await db.putSetting(Keys.weather, '1');
        var calls = 0;
        Future<String?> ok(Uri _) async {
          calls++;
          return '{"current":{"weather_code":0,"is_day":1}}';
        }

        Future<String?> fail(Uri _) async {
          calls++;
          return null;
        }

        expect(
          (await currentWeather(db, now: t0, locate: here, fetch: ok))!.sky,
          Sky.clear,
        );
        await currentWeather(
          db,
          now: t0.add(const Duration(hours: 2)),
          locate: here,
          fetch: ok,
        );
        expect(calls, 1);
        final stale = await currentWeather(
          db,
          now: t0.add(const Duration(hours: 5)),
          locate: here,
          fetch: fail,
        );
        expect(stale!.sky, Sky.clear);
        expect(calls, 2);
        expect(
          await currentWeather(
            db,
            now: t0.add(const Duration(hours: 13)),
            locate: here,
            fetch: fail,
          ),
          isNull,
        );
      },
    );
  });
}
