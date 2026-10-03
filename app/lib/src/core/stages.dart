import 'package:band_ble/band_ble.dart';
import 'package:scoring/scoring.dart';

/// Raw band activity kind → scoring stage. Codes come from band_ble and are
/// TODO(verify) there.
Stage stageForKind(int kind) => switch (sleepKinds[kind]) {
  'light' => Stage.light,
  'deep' => Stage.deep,
  'rem' => Stage.rem,
  _ => notWornKinds.contains(kind) ? Stage.unknown : Stage.wake,
};
