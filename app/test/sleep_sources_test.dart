import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/data_source.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/minutes.dart';
import 'package:tempo/src/core/profile.dart' show Keys;
import 'package:tempo/src/screens/sleep.dart';

import 'support/health_fake.dart';

void main() {
  late TempoDb db;
  setUp(() async {
    db = TempoDb(NativeDatabase.memory());
    await saveDataSource(db, DataSource.appleHealth);
  });
  tearDown(() => db.close());

  final today = DateTime.now();
  final bed = DateTime(today.year, today.month, today.day - 2, 23);
  final up = bed.add(const Duration(hours: 8));

  /// A phone that wrote only in-bed, plus [extra].
  Future<void> read(List<HealthRecord> extra) => HealthSyncService(
    db,
    reader: FakeReader([
      rec(HealthKind.sleepSession, bed, 480, b: up, src: 'phone'),
      ...extra,
    ]),
    useLock: false,
  ).run();

  Night night(List<NightSleepApp> apps, {bool own = false}) => Night(
    morning: up,
    minutes: const [],
    latency: 0,
    spo2: const [],
    typical: const {},
    bedtimes: const [],
    hrBand: null,
    staged: false,
    source: DataSource.appleHealth,
    sleepApps: apps,
    tempoWrote: own,
  );

  test('Tempo\'s own staged night is skipped and named as such', () async {
    await read([rec(HealthKind.sleepDeep, bed, 0, b: up, src: tempoAppId)]);
    final m = await loadMinutes(db, bed, up);
    expect(m.unstaged, isTrue);
    var x = await nightSleepApps(db, bed, up);
    expect(x.tempoWrote, isFalse); // never stored, so not seen here
    await db.putSetting(Keys.healthExportedTo, bed.toIso8601String());
    x = await nightSleepApps(db, bed, up);
    expect(x.tempoWrote, isTrue);
    expect(x.apps.single.label, 'Phone');
    expect(x.apps.single.staged, isFalse);
    final note = unstagedNote(night(x.apps, own: x.tempoWrote));
    expect(
      note,
      contains('Phone wrote only time asleep or in bed to Apple Health'),
    );
    expect(note, contains('Tempo has written nights to Apple Health itself'));
    expect(note, isNot(contains('band')));
  });

  test('a staged app left out by the sleep choice is suggested', () async {
    await read([
      rec(HealthKind.sleepDeep, bed, 0, b: up, src: 'com.example.ring'),
    ]);
    await setSleepSource(db, 'phone');
    expect((await loadMinutes(db, bed, up)).unstaged, isTrue);
    final x = await nightSleepApps(db, bed, up);
    expect(x.apps.first.label, 'Ring');
    expect(x.apps.first.staged, isTrue);
    expect(x.apps.first.used, isFalse);
    final note = unstagedNote(night(x.apps));
    expect(
      note,
      contains(
        'Ring wrote stages: choose it in Profile → Data sources → Sleep',
      ),
    );

    // Every app merged: the ring's stages win over the phone's in-bed.
    await setSleepSource(db, null);
    expect((await loadMinutes(db, bed, up)).unstaged, isFalse);
  });

  test('the band keeps its own note', () {
    final n = Night(
      morning: up,
      minutes: const [],
      latency: 0,
      spo2: const [],
      typical: const {},
      bedtimes: const [],
      hrBand: null,
      staged: false,
    );
    expect(unstagedNote(n), contains('the band measured heart rate'));
  });
}
