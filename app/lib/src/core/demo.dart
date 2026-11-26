import 'dart:io';

import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'data_source.dart';
import 'health_reader.dart';
import 'profile.dart';

/// Demo mode (P7, docs/research/Pulse comparison.md §7): a build made with
/// `--dart-define=TEMPO_DEMO=true` opens its own database (`tempo_demo`),
/// reads made-up Health data ([demoRecords]) instead of Apple Health or
/// Health Connect, and starts already set up. For store screenshots,
/// design review and testing on a phone without a watch. A normal build
/// can never enter it, and it never touches the real database.
const demoMode = bool.fromEnvironment('TEMPO_DEMO');

/// The reader every Health read goes through: the plugin, or the demo.
HealthReader healthReader() =>
    demoMode ? DemoHealthReader() : PluginHealthReader();

/// Health records from [demoRecords], as if from a watch that wrote them
/// to Health. Always allowed; the anchor is now, so each day of using the
/// demo adds a day.
class DemoHealthReader implements HealthReader {
  DemoHealthReader({DateTime Function()? clock, bool? apple})
    : _now = clock ?? DateTime.now,
      apple = apple ?? Platform.isIOS;

  final DateTime Function() _now;
  final bool apple;

  @override
  Set<HealthKind> get kinds => demoKinds(apple: apple);

  @override
  Future<HealthConnectResult> connect() async => HealthConnectResult.ok;

  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<bool> canReadInBackground() async => true;

  @override
  Future<HealthPermissions> permissions() async => HealthPermissions(
    kinds: {for (final k in kinds) k: true},
    history: apple ? null : true,
    background: apple ? null : true,
  );

  @override
  Future<List<HealthRecord>> read(
    HealthKind kind,
    DateTime from,
    DateTime to,
  ) async => demoRecords(kind, from, to, anchor: _now(), apple: apple);
}

/// Sets up a fresh demo database: the Health source, the demo person's
/// profile and 90 days of journal check-ins (a drink every 6th evening, as
/// in the Health data; now and then a late meal or a sauna). The data
/// itself arrives with the first sync. Does nothing once set up.
Future<void> seedDemo(st.TempoDb db, {DateTime? now}) async {
  if (await db.setting(Keys.onboarded) == '1') return;
  final today = now ?? DateTime.now();
  await saveDataSource(db, DataSource.platformHealth);
  await saveAppProfile(
    db,
    const Profile(age: 34, heightCm: 178, weightKg: 77, male: true),
  );
  for (var i = 1; i <= 90; i++) {
    final d = DateTime(today.year, today.month, today.day - i);
    if (demoIll(d, today)) continue; // too ill to check in
    final drink = demoAlcohol(d, today);
    await db.setJournal(d, 'alcohol', drink);
    if (drink) await db.setJournal(d, 'drinks', true, amount: 2);
    await db.setJournal(d, 'late_meal', i % 9 == 4);
    await db.setJournal(d, 'sauna', i % 11 == 7);
    await db.setJournal(d, 'meditation', i % 3 == 0);
    await db.setJournal(d, sc.checkinTag, true);
  }
  await db.putSetting(Keys.onboarded, '1');
}
