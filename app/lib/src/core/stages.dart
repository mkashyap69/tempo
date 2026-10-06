import 'package:band_ble/band_ble.dart';
import 'package:scoring/scoring.dart';
import 'package:store/store.dart' as st;

/// Raw kind → what the band itself says: asleep (as light, until staged),
/// not worn, or awake. See [kindAsleep] for the V1.0.6.20 bit field.
Stage stageForKind(int kind) => kindAsleep(kind)
    ? Stage.light
    : kindNotWorn(kind)
    ? Stage.unknown
    : Stage.wake;

Minute minuteOf(st.MinuteSample m) => Minute(
  st.fromTs(m.ts),
  hr: m.hr,
  steps: m.steps,
  motion: m.intensity,
  stage: stageForKind(m.kind),
  bandWalking: kindWalking(m.kind),
  offWrist: kindNotWorn(m.kind),
);

/// Decoded minutes, with every sleep (night or nap) in them staged from
/// heart rate and motion. [unstaged] is true when a sleep had too little
/// heart rate to stage (HR sampled every 10–30 min).
typedef DecodedMinutes = ({List<Minute> minutes, bool unstaged});

DecodedMinutes decodeMinutes(List<st.MinuteSample> rows) {
  final mins = [for (final r in rows) minuteOf(r)];
  var unstaged = false;
  final sessions = detectSessions(
    mins,
    const SleepParams(minSessionMinutes: 20),
  );
  if (sessions.isEmpty) return (minutes: mins, unstaged: false);
  final index = {for (var i = 0; i < mins.length; i++) mins[i].ts: i};
  for (final s in sessions) {
    final staged = stageSleep(s.minutes);
    if (!staged.staged) unstaged = true;
    for (final m in staged.minutes) {
      final i = index[m.ts];
      if (i != null) mins[i] = m;
    }
  }
  return (minutes: mins, unstaged: unstaged);
}
