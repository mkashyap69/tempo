/// Coach moments (N2, decisions.md 2026-11-03): the notifications that
/// bring people back to Tempo for a reason and push them toward their goal,
/// decided in pure Dart from numbers the app already has.
///
/// - A **win**: a real achievement today, celebrated once, then pointed at
///   the next step.
/// - The **week goal** check-in: sessions done against the week's plan,
///   and the next one that gets there.
/// - **Come back**: after days away, one message with something real from
///   those days; again after a week; then silence.
library;

/// What a win is about, so one kind isn't repeated too often.
enum WinKind {
  recoveryBest,
  bedtimeStreak,
  weekDone,
  stepStreak,
  calibrated,
  longest,

  /// Halfway through a goal's block (appended: stored names hold).
  halfway,
}

final class Win {
  const Win(this.kind, this.title, this.body, {this.weight = 1});
  final WinKind kind;
  final String title, body;

  /// Higher wins first.
  final int weight;
}

/// Everything the win picker reads.
final class WinInput {
  const WinInput({
    this.recovery,
    this.recoveryLast30 = const [],
    this.bedtimeKeptNights = 0,
    this.sessionsDone = 0,
    this.sessionsPlanned = 0,
    this.weekJustDone = false,
    this.stepGoalDays = 0,
    this.stepGoal = 8000,
    this.calibratedToday = false,
    this.longestKmToday,
    this.longestKmBefore,
    this.bedtime = '22:45',
    this.recentWins = const {},
    this.blockWeek,
    this.blockWeeks,
    this.goal,
  });

  /// Today's recovery (null while learning).
  final double? recovery;

  /// Recoveries of the 30 days before today.
  final List<double> recoveryLast30;

  /// Nights in a row in bed by the bedtime Tempo asked for.
  final int bedtimeKeptNights;

  /// This week's planned sessions done, and planned.
  final int sessionsDone, sessionsPlanned;

  /// The session that completed the week's plan was today.
  final bool weekJustDone;

  /// Days in a row the step goal was reached, today included.
  final int stepGoalDays;
  final int stepGoal;

  /// The 14th night came in today: baselines are ready.
  final bool calibratedToday;

  /// Today's longest walk or run, and the longest in the 90 days before.
  final double? longestKmToday, longestKmBefore;

  /// "22:45", tonight's bedtime, for the next-step line.
  final String bedtime;

  /// Kinds already celebrated in the last 7 days.
  final Set<WinKind> recentWins;

  /// This week of a dated goal's block (0-based) and its length in weeks;
  /// null without one. [goal] names it ("10K", "Half marathon").
  final int? blockWeek, blockWeeks;
  final String? goal;
}

/// The block week that counts as halfway, or null for blocks too short
/// to have a middle worth marking (under 4 weeks).
int? halfwayWeek(int weeks) => weeks >= 4 ? weeks ~/ 2 : null;

/// Streak lengths worth a word: a run of these is noise.
const streakMarks = {3, 7, 14, 21, 30, 50, 100};

/// Today's best win, or null. Each kind at most once a week.
Win? pickWin(WinInput i) {
  final out = <Win>[];
  final r = i.recovery;
  if (i.calibratedToday) {
    out.add(
      const Win(
        WinKind.calibrated,
        'Tempo knows your normal now',
        '14 nights in. Recovery and strain targets are personal from today.',
        weight: 5,
      ),
    );
  }
  if (r != null && i.recoveryLast30.length >= 14) {
    final best = i.recoveryLast30.reduce((a, b) => a > b ? a : b);
    if (r > best && r >= 67) {
      out.add(
        Win(
          WinKind.recoveryBest,
          'Recovery ${r.round()}% · your best in 30 days',
          'Whatever you did yesterday worked. A good day to push today’s session.',
          weight: 4,
        ),
      );
    }
  }
  if (i.weekJustDone && i.sessionsPlanned >= 2) {
    out.add(
      Win(
        WinKind.weekDone,
        'Week done: ${i.sessionsDone} of ${i.sessionsPlanned} sessions',
        'That’s the week your goal asked for. Anything more today is a bonus; easy is fine.',
        weight: 4,
      ),
    );
  }
  final today = i.longestKmToday, before = i.longestKmBefore;
  if (today != null && before != null && today >= 3 && today > before * 1.05) {
    out.add(
      Win(
        WinKind.longest,
        'Longest in 90 days: ${today.toStringAsFixed(1)} km',
        'Previous best ${before.toStringAsFixed(1)} km. Sleep well tonight so it lands.',
        weight: 3,
      ),
    );
  }
  final bw = i.blockWeek, bn = i.blockWeeks;
  if (bw != null && bn != null && bw == halfwayWeek(bn)) {
    out.add(
      Win(
        WinKind.halfway,
        'Halfway to ${i.goal ?? 'your goal'}',
        'Week ${bw + 1} of $bn. The base is in; from here the plan builds '
            'toward the day itself.',
        weight: 3,
      ),
    );
  }
  if (streakMarks.contains(i.bedtimeKeptNights)) {
    out.add(
      Win(
        WinKind.bedtimeStreak,
        '${i.bedtimeKeptNights} nights in a row in bed on time',
        'Regular nights are the cheapest recovery there is. In by ${i.bedtime} keeps it going.',
        weight: 2,
      ),
    );
  }
  if (streakMarks.contains(i.stepGoalDays)) {
    out.add(
      Win(
        WinKind.stepStreak,
        '${i.stepGoalDays} days in a row at ${_k(i.stepGoal)} steps',
        'Daily movement is one of the strongest levers on Tempo Age.',
        weight: 1,
      ),
    );
  }
  out.removeWhere((w) => i.recentWins.contains(w.kind));
  if (out.isEmpty) return null;
  out.sort((a, b) => b.weight - a.weight);
  return out.first;
}

String _k(int n) => n >= 1000 && n % 1000 == 0 ? '${n ~/ 1000}k' : '$n';

/// The week-goal check-in, mid-week: progress and the next session that
/// counts. Null when there's nothing useful to say (week done, nothing
/// planned, or no session left to do).
(String, String)? weekGoalCopy({
  required int done,
  required int planned,
  String? goal,
  String? nextTitle,
  String? nextDay,
}) {
  if (planned < 2 || done >= planned || nextTitle == null) return null;
  final left = planned - done;
  final aim = goal == null ? 'this week' : 'for $goal';
  return (
    '$done of $planned sessions $aim',
    left == 1
        ? '${nextDay ?? 'Next'}: $nextTitle finishes the week.'
        : '${nextDay ?? 'Next'}: $nextTitle. $left to go, and the plan has room for them.',
  );
}

/// The come-back message after [daysAway] days without opening Tempo:
/// once at 3 days, once at 7, then nothing until the user returns.
/// [nights] scored while away; [avgSleepH] their mean; [recovery] today's.
(String, String)? comebackCopy({
  required int daysAway,
  required int nights,
  double? avgSleepH,
  double? recovery,
  double? recoveryBest14,
}) {
  if (daysAway != 3 && daysAway != 7) return null;
  final r = recovery;
  if (r != null && recoveryBest14 != null && r >= recoveryBest14 && r >= 60) {
    return (
      'Recovery ${r.round()}% today, your best in 2 weeks',
      'Tempo kept scoring while you were away. See what changed.',
    );
  }
  if (nights > 0 && avgSleepH != null) {
    final h = avgSleepH.floor(), m = ((avgSleepH - h) * 60).round();
    return (
      '$nights ${nights == 1 ? 'night' : 'nights'} scored while you were away',
      'Average sleep ${h}h ${m.toString().padLeft(2, '0')}m. Your plan for this week is ready.',
    );
  }
  return (
    'Your plan picks up where you left off',
    'One tap to see today’s call.',
  );
}
