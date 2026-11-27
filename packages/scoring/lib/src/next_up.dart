/// v3 Today: "Next up", one card under the plan that changes with the day
/// (0.7.0). Before mid-afternoon it says how much effort today has left and
/// what would fill it; after that it says when to be in bed and what
/// tomorrow looks like if you are. Quiet when there's nothing to say.
library;

import 'dart:math';

import 'coach.dart' show Sport, StrainTarget;
import 'forecast.dart';
import 'strain.dart';

enum NextUpKind { room, tonight }

typedef NextUp = ({NextUpKind kind, String title, String body});

/// The minute from which Next up talks about tonight.
const nextUpTonightFrom = 15 * 60;

/// Effort as a share of heart-rate reserve: a brisk walk, and an easy run
/// or ride (both above the TRIMP floor, Z1–Z2).
const briskWalkReserve = .45, easyCardioReserve = .62;

/// Minutes at [reserve] of heart-rate reserve that take a day from
/// [strain] to [goal], or null when already there or over three hours.
int? minutesToStrain({
  required double strain,
  required double goal,
  required double reserve,
  required double hrRest,
  required double hrMax,
  bool female = false,
  StrainParams p = const StrainParams(),
}) {
  if (strain >= goal || goal >= 21) return null;
  double trimpAt(double s) => -p.k * log(1 - s / 21);
  final need = trimpAt(goal) - trimpAt(strain);
  final hr = (hrRest + reserve * (hrMax - hrRest)).round();
  final per = minuteTrimp(
    hr,
    hrRest: hrRest,
    hrMax: hrMax,
    floor: p.floor,
    female: female,
  );
  if (per <= 0) return null;
  final m = (need / per).ceil();
  return m > 180 ? null : max(5, ((m + 4) ~/ 5) * 5);
}

String _hm(double h) {
  final m = (h * 60).round();
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m';
}

/// What Today's Next up card says, or null for no card. [planOpen] is a
/// planned session still to do today (its own card covers the effort);
/// [likes] picks run or ride for the second option; [bedtime] is tonight's
/// lights out as shown, [bedtimeMinute] its minute of the day.
NextUp? nextUp({
  required int nowMinute,
  required int bedtimeMinute,
  required String bedtime,
  required double strain,
  required StrainTarget target,
  required bool planOpen,
  required double hrRest,
  required double hrMax,
  bool female = false,
  Sport? likes,
  double? needHours,
  RecoveryForecast? forecast,
}) {
  final bed = bedtimeMinute < 6 * 60 ? bedtimeMinute + 1440 : bedtimeMinute;
  // The evening belongs to the Tonight card.
  if (nowMinute >= bed - 120) return null;

  if (nowMinute >= nextUpTonightFrom) {
    final parts = [
      if (needHours != null) 'You need about ${_hm(needHours)} tonight.',
      if (forecast != null)
        'In bed by then and tomorrow lands around ${forecast.low.round()}–${forecast.high.round()}.',
      if (forecast != null && forecast.hourLessCost >= 1)
        'An hour less costs about ${forecast.hourLessCost.round()} points.',
    ];
    return (
      kind: NextUpKind.tonight,
      title: 'Lights out by $bedtime',
      body: parts.isEmpty
          ? 'A regular bedtime is the cheapest recovery there is.'
          : parts.join(' '),
    );
  }

  if (planOpen || target.general || target.cap) return null;
  if (strain >= target.lo) return null;
  final gap = target.lo - strain;
  final walk = minutesToStrain(
    strain: strain,
    goal: target.lo,
    reserve: briskWalkReserve,
    hrRest: hrRest,
    hrMax: hrMax,
    female: female,
  );
  final easy = minutesToStrain(
    strain: strain,
    goal: target.lo,
    reserve: easyCardioReserve,
    hrRest: hrRest,
    hrMax: hrMax,
    female: female,
  );
  final what = likes == Sport.cycling ? 'easy ride' : 'easy run';
  final options = [
    if (walk != null) 'a $walk-min brisk walk',
    if (easy != null) 'a $easy-min $what',
  ];
  return (
    kind: NextUpKind.room,
    title: '${gap.toStringAsFixed(1)} strain to go today',
    body: options.isEmpty
        ? 'A longer session than usual would take today into its ${target.lo.round()}–${target.hi.round()} range.'
        : '${options.join(' or ')[0].toUpperCase()}${options.join(' or ').substring(1)} gets you into today’s ${target.lo.round()}–${target.hi.round()} range.',
  );
}
