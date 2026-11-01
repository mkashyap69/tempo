/// Activities added by hand (U4): a session the watch didn't record. Its
/// load is Foster's session RPE (RPE × minutes, [trimpFromRpe]), the same
/// estimate Tempo already uses for lifting, minus any heart rate the watch
/// did catch in that window. Pure Dart.
library;

import 'dart:math';

import 'strain.dart';

/// The heart-rate zone an effort of [rpe] (0–10, Borg CR10) sits in, as
/// the coach expects it ([expectedRpe]: easy 3, moderate 5, hard 7):
/// 1–2 Z1, 3–4 Z2, 5–6 Z3, 7–8 Z4, 9–10 Z5.
int zoneForRpe(int rpe) => (((rpe.clamp(1, 10) + 1) ~/ 2)).clamp(1, 5);

/// Minutes per zone (Z1…Z5) for a hand-added session: all of it in the
/// RPE's zone. An estimate, so screens label it.
List<int> manualZones(int minutes, int rpe) => [
  for (var z = 1; z <= 5; z++) z == zoneForRpe(rpe) ? max(0, minutes) : 0,
];

/// TRIMP to add to the day for a hand-added session: its sRPE load less
/// the heart-rate load already measured in its window ([hrTrimp]).
double manualExtraTrimp({
  required int rpe,
  required int minutes,
  double hrTrimp = 0,
  StrainParams p = const StrainParams(),
}) => max(0, trimpFromRpe(rpe, minutes, p) - hrTrimp);
