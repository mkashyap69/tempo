import 'package:drift_flutter/drift_flutter.dart';
import 'package:store/store.dart';

import 'demo.dart';

/// Opens the on-device database. Shared across isolates so the background
/// sync and the UI can both use it.
TempoDb openDb() => TempoDb(
  driftDatabase(
    // Demo builds keep their made-up data in a database of their own.
    name: demoMode ? 'tempo_demo' : 'tempo',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  ),
);
