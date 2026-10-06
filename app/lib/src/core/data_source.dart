import 'dart:io' show Platform;

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'profile.dart' show Keys;

/// Where Tempo's data comes from. One per install (decisions.md,
/// 2026-10-06): the Mi Band 6 over Bluetooth, or what a watch or ring
/// writes to Apple Health / Health Connect, read-only.
enum DataSource {
  band,
  appleHealth,
  healthConnect;

  /// Stored in settings and on every daily score (`daily_scores.source`).
  String get key => switch (this) {
    DataSource.band => sc.bandSource,
    DataSource.appleHealth => 'apple_health',
    DataSource.healthConnect => 'health_connect',
  };

  bool get isHealth => this != DataSource.band;

  String get label => switch (this) {
    DataSource.band => 'Mi Band 6',
    DataSource.appleHealth => 'Apple Health',
    DataSource.healthConnect => 'Health Connect',
  };

  /// What the source can give. Screens hide what it can't rather than
  /// showing empty cards.
  Capabilities get can => isHealth
      ? const Capabilities(
          stress: false,
          liveHr: false,
          bandControls: false,
          oxygenEvents: false,
        )
      : const Capabilities();

  static DataSource? fromKey(String? k) => switch (k) {
    'band' => DataSource.band,
    'apple_health' => DataSource.appleHealth,
    'health_connect' => DataSource.healthConnect,
    _ => null,
  };

  /// The Health store this phone has.
  static DataSource get platformHealth =>
      Platform.isIOS ? DataSource.appleHealth : DataSource.healthConnect;
}

final class Capabilities {
  const Capabilities({
    this.stress = true,
    this.liveHr = true,
    this.bandControls = true,
    this.oxygenEvents = true,
  });

  /// The band's stress index (Stress screen, stress cards).
  final bool stress;

  /// Second-by-second heart rate during a live workout.
  final bool liveHr;

  /// Pairing, battery, firmware, band settings, smart alarm, buzz cues,
  /// band explorer, re-download.
  final bool bandControls;

  /// SpO₂ desaturation events with their 4-minute traces.
  final bool oxygenEvents;
}

/// The active source. Unset (every install from before Health sources)
/// means the band. A Health source restored from another platform's
/// backup (Apple Health on Android) means this phone's own Health store.
Future<DataSource> loadDataSource(st.TempoDb db) async =>
    resolveDataSource(await db.setting(Keys.dataSource));

DataSource resolveDataSource(String? stored, {DataSource? platform}) {
  final s = DataSource.fromKey(stored) ?? DataSource.band;
  if (!s.isHealth) return s;
  return platform ?? DataSource.platformHealth;
}

Future<void> saveDataSource(st.TempoDb db, DataSource s) =>
    db.putSetting(Keys.dataSource, s.key);
