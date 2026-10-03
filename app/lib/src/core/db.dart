import 'package:drift_flutter/drift_flutter.dart';
import 'package:store/store.dart';

/// Opens the on-device database. Shared across isolates so the background
/// sync and the UI can both use it.
TempoDb openDb() => TempoDb(
  driftDatabase(
    name: 'tempo',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  ),
);
