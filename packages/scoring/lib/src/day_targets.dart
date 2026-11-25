/// Today's targets (D2): the session, steps, one habit for the goal and
/// tonight's sleep window, each ticked from data where Tempo can see it.
/// A target with no data stays open; it is never counted as missed. Pure Dart.
library;

import 'coach.dart' show Goal;
import 'coach_day.dart' show DayStatus, bedScale;

/// What a target is about; also its group label on Today.
enum TargetKind { session, steps, habit, sleep }

enum TargetState {
  /// Ticked, by data or by hand.
  done,

  /// Still to do (or not yet knowable).
  open,

  /// You chose not to (a skipped session). Left out of the count.
  skipped,
}

final class DayTarget {
  const DayTarget({
    required this.kind,
    required this.title,
    required this.sub,
    required this.state,
    required this.auto,
    this.journalKey,
  });

  final TargetKind kind;
  final String title, sub;
  final TargetState state;

  /// True when data ticks it; false when you tick it by hand.
  final bool auto;

  /// The Journal entry a hand tick writes (habits only).
  final String? journalKey;

  bool get done => state == TargetState.done;
}

/// The habit Tempo pairs with each goal: protein for the goals that need
/// muscle kept or rebuilt, morning daylight for the rest.
({String key, String title}) goalHabit(Goal g) => switch (g) {
  Goal.fatLoss ||
  Goal.performance => (key: 'high_protein', title: 'Protein with each meal'),
  Goal.fitness ||
  Goal.wellbeing => (key: 'daylight', title: 'Morning daylight'),
};

/// Protein per kg of body weight a day, (low, high), by goal. Losing fat
/// while training needs the most to keep muscle (ISSN 2017 position stand:
/// 1.4–2.0 g/kg for people who exercise; higher in a deficit).
(double, double) proteinPerKg(Goal g) => switch (g) {
  Goal.fatLoss => (1.6, 2.0),
  Goal.performance => (1.6, 2.0),
  Goal.fitness => (1.4, 1.6),
  Goal.wellbeing => (1.2, 1.6),
};

final class DayTargetsInput {
  const DayTargetsInput({
    required this.goal,
    required this.weightKg,
    required this.stepGoal,
    required this.bedMinute,
    required this.wakeMinute,
    this.sessionTitle,
    this.sessionMinutes,
    this.status,
    this.steps,
    this.habitAnswer,
    this.proteinGrams,
    this.proteinTarget,
    this.nightBedMinute,
  });

  final Goal goal;
  final double weightKg;
  final int stepGoal;

  /// Tonight's bedtime and tomorrow's wake, minutes after midnight.
  final int bedMinute, wakeMinute;

  /// Today's planned session; null on a rest day or with no plan.
  final String? sessionTitle;
  final int? sessionMinutes;
  final DayStatus? status;

  /// Steps so far today; null when the source has none.
  final int? steps;

  /// The habit's Journal answer for today, or null if not answered.
  final bool? habitAnswer;

  /// Protein logged to Health today (g), and your daily target (g), when
  /// known. Reaching the target ticks the protein habit.
  final double? proteinGrams, proteinTarget;

  /// When you actually went to bed that night (minutes after midnight),
  /// for a day whose night is over; null today.
  final int? nightBedMinute;
}

/// Minutes after the planned bedtime that still count as on time.
const bedGrace = 15;

String _hm(int m) {
  final x = ((m % 1440) + 1440) % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

String _k(int n) {
  final s = n.toString();
  return s.length <= 3
      ? s
      : '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}

/// Today's targets in order: session, steps, habit, sleep.
List<DayTarget> dayTargets(DayTargetsInput i) {
  final out = <DayTarget>[];
  if (i.sessionTitle != null && i.status != DayStatus.rest) {
    final st = switch (i.status) {
      DayStatus.done ||
      DayStatus.doneEasier ||
      DayStatus.doneHarder => TargetState.done,
      DayStatus.skipped || DayStatus.missedDay => TargetState.skipped,
      _ => TargetState.open,
    };
    out.add(
      DayTarget(
        kind: TargetKind.session,
        title: i.sessionTitle!,
        sub: st == TargetState.skipped
            ? 'Skipped today'
            : '${i.sessionMinutes ?? 0} min · checked when the workout is read',
        state: st,
        auto: true,
      ),
    );
  }

  final steps = i.steps;
  out.add(
    DayTarget(
      kind: TargetKind.steps,
      title: '${_k(i.stepGoal)} steps',
      sub: steps == null
          ? 'Checked against your steps'
          : steps >= i.stepGoal
          ? '${_k(steps)} today'
          : '${_k(steps)} so far · ${_k(i.stepGoal - steps)} to go',
      state: steps != null && steps >= i.stepGoal
          ? TargetState.done
          : TargetState.open,
      auto: true,
    ),
  );

  final h = goalHabit(i.goal);
  final protein = h.key == 'high_protein';
  final (lo, hi) = proteinPerKg(i.goal);
  final reached =
      protein &&
      i.proteinGrams != null &&
      i.proteinTarget != null &&
      i.proteinGrams! >= i.proteinTarget!;
  out.add(
    DayTarget(
      kind: TargetKind.habit,
      title: h.title,
      sub: protein
          ? (i.proteinGrams != null && i.proteinTarget != null
                ? '${i.proteinGrams!.round()} of ${i.proteinTarget!.round()} g from Health'
                : 'About ${(lo * i.weightKg).round()}–${(hi * i.weightKg).round()} g a day over 3–4 meals')
          : '10+ min outside before noon',
      state: (i.habitAnswer ?? false) || reached
          ? TargetState.done
          : TargetState.open,
      auto: reached,
      journalKey: h.key,
    ),
  );

  final hours = ((i.wakeMinute - i.bedMinute) % 1440) / 60;
  final night = i.nightBedMinute;
  out.add(
    DayTarget(
      kind: TargetKind.sleep,
      title: 'Bed by ${_hm(i.bedMinute)}',
      sub:
          'Up at ${_hm(i.wakeMinute)} (${_hours(hours)}) · checked against your sleep',
      state:
          night != null && bedScale(night) <= bedScale(i.bedMinute) + bedGrace
          ? TargetState.done
          : TargetState.open,
      auto: true,
    ),
  );
  return out;
}

String _hours(double h) {
  final m = (h * 60).round();
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60}';
}

/// "1 of 3 done" and the next thing to do.
final class TargetsSummary {
  const TargetsSummary(this.done, this.total, this.next);
  final int done, total;

  /// The first open target, or null when everything counted is done.
  final DayTarget? next;
  double get share => total == 0 ? 0 : done / total;
}

/// Skipped targets leave the count; the next one is the first still open.
/// Kinds in [notNext] are passed over for "up next" (the session, when its
/// own card is already on screen) unless nothing else is open.
TargetsSummary summarise(
  List<DayTarget> ts, {
  Set<TargetKind> notNext = const {},
}) {
  final counted = ts.where((t) => t.state != TargetState.skipped).toList();
  DayTarget? next;
  for (final t in counted) {
    if (t.state == TargetState.open && !notNext.contains(t.kind)) {
      next = t;
      break;
    }
  }
  if (next == null) {
    for (final t in counted) {
      if (t.state == TargetState.open) {
        next = t;
        break;
      }
    }
  }
  return TargetsSummary(
    counted.where((t) => t.done).length,
    counted.length,
    next,
  );
}
