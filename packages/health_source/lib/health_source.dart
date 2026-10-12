/// Apple Health and Health Connect records turned into the per-minute data
/// Tempo scores. Pure Dart: no Flutter, no plugin. The app reads records
/// with the `health` plugin; `tools/backtest` reads them from export.xml.
/// Both go through the same [HealthGrid], so they map data identically.
library;

export 'src/grid.dart';
export 'src/record.dart';
export 'src/reconcile.dart';
export 'src/vitals.dart';
export 'src/workouts.dart';
