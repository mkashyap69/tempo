import 'package:scoring/scoring.dart' as sc;

/// What a body signal is and when it matters, in plain words (v3 "any
/// number, explained"). Patterns, never diagnoses: every doctor line says
/// when it's worth asking, not what it means.
final class MetricInfo {
  const MetricInfo({
    required this.what,
    required this.moves,
    required this.doctor,
    required this.higherIsBetter,
  });

  /// What it is.
  final String what;

  /// What usually moves it for a night.
  final String moves;

  /// When it's worth a doctor's view.
  final String doctor;
  final bool higherIsBetter;
}

/// Keys as in [sc.SignalInput.key].
MetricInfo? metricInfo(String key) => switch (key) {
  'rhr' => const MetricInfo(
    what: 'Your lowest steady heart rate while asleep. It falls as fitness improves and rises when your body is busy recovering, fighting something off or short of sleep.',
    moves: 'Alcohol, a late or heavy meal, a hard session the day before, a hot room, dehydration and the start of a cold all push it up for a night.',
    doctor: 'A night or two above your normal means little. If it stays well above your normal for a week or more and you feel unwell, or it is often very low and you feel dizzy or faint, mention it to a doctor.',
    higherIsBetter: false,
  ),
  'hrv' => const MetricInfo(
    what: 'The tiny changes in time between heartbeats while you sleep. More variation usually means your body is in rest-and-repair mode. It is very personal: compare yourself with yourself, not with others.',
    moves: 'Alcohol, late meals, stress, illness and hard training lower it for a night or two; good sleep, rest days and a calm evening raise it.',
    doctor: 'One low night means little. If it stays well under your normal for a week or more together with a higher resting heart rate, and you feel unwell, mention it to a doctor.',
    higherIsBetter: true,
  ),
  'stress' => const MetricInfo(
    what: 'Your band’s overnight stress index, worked out from your heart rhythm. Lower means your body was calmer while you slept.',
    moves: 'Alcohol, late meals, a stressful day, illness and a hard session late in the day raise it.',
    doctor: 'If it stays high for weeks and you also sleep badly or feel on edge, it is worth talking to a doctor about stress and sleep.',
    higherIsBetter: false,
  ),
  'resp' => const MetricInfo(
    what: 'Breaths per minute while asleep. It is one of the steadiest numbers your watch measures, so a change stands out.',
    moves: 'A cold or other infection, alcohol, a hot room and a hard session the day before can raise it for a night.',
    doctor: 'If it stays above your normal for several nights together with a higher heart rate or temperature, or you are short of breath, see a doctor.',
    higherIsBetter: false,
  ),
  'spo2' => const MetricInfo(
    what: 'How much oxygen your blood carried while you slept, as a percentage. Most healthy people sit in the mid to high 90s at night. Wrist readings are rough: trust the trend over a single night.',
    moves: 'Altitude, a cold, sleeping position and a loose watch strap can all lower a night’s reading.',
    doctor: 'If it is often low, or you snore loudly, wake gasping or feel very tired in the day, ask a doctor about your sleep and breathing. A wrist reading is not a medical test.',
    higherIsBetter: true,
  ),
  'temp' => const MetricInfo(
    what: 'Your skin temperature overnight compared with your usual. It is a change from your normal, not a fever reading.',
    moves: 'A warm room, heavy bedding, alcohol, the menstrual cycle and the start of an illness all move it.',
    doctor: 'If it stays raised for several nights and you feel unwell, check your temperature with a thermometer and see a doctor if you have a fever.',
    higherIsBetter: false,
  ),
  _ => null,
};

/// The word for where last night sits.
String placeWord(sc.NormalPlace p) => switch (p) {
  sc.NormalPlace.learning => 'Learning your normal',
  sc.NormalPlace.missing => 'No reading last night',
  sc.NormalPlace.inNormal => 'In your normal',
  sc.NormalPlace.better => 'Better than usual',
  sc.NormalPlace.outside => 'Outside your normal',
};

/// What to do about last night, by where it sits.
String placeAdvice(sc.NormalPlace p) => switch (p) {
  sc.NormalPlace.learning => 'Tempo needs about two weeks of nights before it can say what your normal is.',
  sc.NormalPlace.missing => 'Wear your watch to bed, snug enough that it doesn’t slide, for a reading tonight.',
  sc.NormalPlace.inNormal => 'Nothing to do. This is you on a usual night.',
  sc.NormalPlace.better =>
    'Nothing to fix. A good sign that you recovered well; use it.',
  sc.NormalPlace.outside => 'Go easier today and get to bed early. One night out of range is usually a drink, a late meal or a hard day; Tempo watches whether it lasts.',
};

/// One line for the Body check summary.
String bodySummary(sc.BodySignals b) {
  final judged = [
    for (final r in b.readings)
      if (r.state == sc.SignalState.normal || r.state == sc.SignalState.off) r,
  ];
  if (judged.isEmpty) {
    return 'Tempo is still learning your normal. Each signal is judged after about two weeks of nights.';
  }
  final off = b.off.length;
  if (off == 0) {
    return '${judged.length} of ${judged.length} body signals sit in or above your normal. Nothing to act on.';
  }
  if (off == 1) {
    return 'One signal is outside your normal. Alone it’s often a late meal, a drink or a hot room.';
  }
  return '$off signals are outside your normal together. Go easy and sleep early; Tempo will tell you if it lasts.';
}
