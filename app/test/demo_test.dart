import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/demo.dart';
import 'package:tempo/src/core/health_sync.dart';
import 'package:tempo/src/core/longevity_service.dart';
import 'package:tempo/src/core/profile.dart' show Keys, loadAppProfile;
import 'package:tempo/src/core/today.dart';

/// P7: a demo database fills through the real Health sync.
void main() {
  late TempoDb db;
  setUp(() => db = TempoDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds once: source, profile, journal, onboarded', () async {
    final now = DateTime.now();
    await seedDemo(db, now: now);
    expect(await db.setting(Keys.onboarded), '1');
    expect((await loadAppProfile(db))!.age, 34);
    final j = await db.journalBetween(
      now.subtract(const Duration(days: 90)),
      now,
    );
    expect(j.where((r) => r.tag == 'alcohol' && r.value), isNotEmpty);
    // A second call leaves it alone.
    await db.setJournal(now, 'alcohol', true);
    await seedDemo(db, now: now);
    expect((await db.journalFor(now)).single.tag, 'alcohol');
  });

  test('the first sync scores the last weeks', () async {
    await seedDemo(db);
    final r = await HealthSyncService(
      db,
      reader: DemoHealthReader(apple: true),
      useLock: false,
    ).run();
    expect(r.firstImport, isTrue);
    expect(r.newWorkouts, greaterThan(20));
    final t = await loadToday(db);
    expect(t.calibrating, isFalse);
    expect(t.recovery, isNotNull);
    expect(t.forecast, isNotNull);
    final week = await db.scoresBetween(
      DateTime.now().subtract(const Duration(days: 7)),
      DateTime.now(),
    );
    expect(week.where((s) => s.sleptHours != null).length, greaterThan(5));
    // P8: the demo scale's body fat gives a lean mass reading.
    final inputs = await longevityInputs(db);
    expect(inputs.ffmi, closeTo(19.8, 1.0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
