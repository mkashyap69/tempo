/// The morning call: one sentence that says what today is for, written in
/// one place so Today, Plan, the morning notification and the widgets
/// never disagree (docs/research/User flow and journey.md §7).
///
/// Rules: the day state wins over the recovery number (night signals that
/// make a rest day outrank a green score), and the reason given is the one
/// that caused the state.
library;

import 'coach.dart';
import 'coach_day.dart';
import 'load.dart';

/// Colour of the call's lead words.
enum CallTone { good, mid, low, plain, muted }

/// What decided the call.
enum CallReason {
  none,
  noData,
  stale,
  firstDay,
  calibrating,
  waiting,
  illness,
  overreaching,
  lowRecovery,
  highRhr,
  shortNight,
  recentHard,
  loadHot,
  primed,
  steady,
}

final class DailyCall {
  const DailyCall(this.lead, this.tone, this.rest, this.reason, {this.note});

  /// Coloured lead words, then the rest of the sentence.
  final String lead, rest;
  final CallTone tone;
  final CallReason reason;

  /// A second, quieter line (why the number and the call differ).
  final String? note;

  String get text => '$lead$rest';
}

/// Everything the call depends on. Strings for clock times come from the
/// app, which knows the user's 12/24 h preference.
final class CallInput {
  const CallInput({
    this.noData = false,
    this.health = false,
    this.stale = false,
    this.firstDay = false,
    this.calibrating = false,
    this.nights = 0,
    this.recovery,
    this.state = DayState.general,
    this.rhr = RhrFlag.none,
    this.shortNight = false,
    this.load = LoadStatus.learning,
    this.daysSinceHard,
    required this.target,
    this.bedtime = '',
    this.planTitle,
    this.planHard = false,
    this.plainWords = false,
  });

  final bool noData, health, stale, firstDay, calibrating;
  final int nights;
  final double? recovery;
  final DayState state;
  final RhrFlag rhr;
  final bool shortNight;
  final LoadStatus load;
  final int? daysSinceHard;

  /// Today's strain target after [targetForState].
  final StrainTarget target;
  final String bedtime;

  /// Today's session, or null on a rest day.
  final String? planTitle;
  final bool planHard;

  /// Wellbeing and fat-loss priorities: words first, no strain numbers.
  final bool plainWords;
}

CallTone recoveryTone(double r) => r >= 67
    ? CallTone.good
    : r >= 34
    ? CallTone.mid
    : CallTone.low;

/// The strain target once the day state is known: a rest day is capped at
/// 8 whatever the recovery, an ease-off day tops out at 13.
StrainTarget targetForState(StrainTarget t, DayState s) {
  if (t.general || t.cap) return t;
  return switch (s) {
    DayState.rest => const StrainTarget(0, 8, cap: true),
    DayState.easeOff when t.hi > 13 => StrainTarget(t.lo < 10 ? t.lo : 10, 13),
    _ => t,
  };
}

/// Why an ease-off day eases off, in the order that most likely caused it.
CallReason easeReason(CallInput i) {
  if (i.rhr == RhrFlag.elevated) return CallReason.highRhr;
  if (i.shortNight) return CallReason.shortNight;
  if (i.load == LoadStatus.overreaching) return CallReason.loadHot;
  if (i.daysSinceHard != null && i.daysSinceHard! < 2) {
    return CallReason.recentHard;
  }
  return CallReason.steady;
}

String _because(CallReason r, int? daysSinceHard) => switch (r) {
  CallReason.highRhr => 'your resting heart rate is above usual',
  CallReason.shortNight => 'last night was short',
  CallReason.loadHot => 'your load is running hot',
  CallReason.recentHard =>
    daysSinceHard == 0
        ? 'you already trained hard today'
        : 'yesterday was hard',
  _ => '',
};

/// A few words for notifications and widgets: "night HR high".
String reasonShort(CallReason r) => switch (r) {
  CallReason.illness => 'night HR high',
  CallReason.overreaching => 'load overreaching',
  CallReason.highRhr => 'resting HR up',
  CallReason.shortNight => 'short night',
  CallReason.recentHard => 'hard session fresh',
  CallReason.loadHot => 'load high',
  _ => '',
};

DailyCall dailyCall(CallInput i) {
  final device = i.health ? 'watch' : 'band';
  if (i.noData) {
    return DailyCall(
      i.health ? 'Connect Health' : 'Connect your band',
      CallTone.plain,
      ' to see today’s recovery, strain and sleep.',
      CallReason.noData,
    );
  }
  if (i.stale) {
    return DailyCall(
      'Yesterday’s data',
      CallTone.muted,
      i.health
          ? ' — let your watch sync to Health before you train so today’s plan uses last night’s sleep.'
          : ' — sync before you train so today’s plan uses last night’s sleep.',
      CallReason.stale,
    );
  }
  if (i.firstDay) {
    return DailyCall(
      'Welcome to Tempo.',
      CallTone.plain,
      ' Wear your $device tonight — your first sleep and recovery arrive tomorrow morning.',
      CallReason.firstDay,
    );
  }
  if (i.calibrating) {
    return DailyCall(
      'Night ${i.nights.clamp(1, 14)} of 14.',
      CallTone.plain,
      ' Tempo is learning your normal — keep today moderate.',
      CallReason.calibrating,
    );
  }
  final r = i.recovery;
  if (r == null) {
    return DailyCall(
      'Last night isn’t in yet',
      CallTone.plain,
      i.health
          ? ' — once your watch syncs last night to Health, today adapts.'
          : ' — sync near your band to see today’s recovery.',
      CallReason.waiting,
    );
  }
  final pct = r.round();
  final lead = i.plainWords ? _plainLead(r) : 'Recovery $pct%';
  final t = i.target;
  final range = '${t.lo.round()}–${t.hi.round()}';

  // Rest: illness first, then overreaching with a second sign, then a low
  // recovery.
  if (i.state == DayState.rest || t.cap) {
    if (i.rhr == RhrFlag.illness) {
      return DailyCall(
        'Take it easy today.',
        CallTone.low,
        ' Your night heart rate ran well above usual — rest, and pause the plan if you’re coming down with something.',
        CallReason.illness,
        note: r >= 34
            ? 'Recovery reads $pct%, but your night signals outrank it today.'
            : null,
      );
    }
    final over = i.load == LoadStatus.overreaching;
    return DailyCall(
      over && r > 33 ? 'Rest today.' : lead,
      CallTone.low,
      over && r > 33
          ? ' Your load is overreaching and ${i.shortNight
                ? 'last night was short'
                : i.rhr == RhrFlag.elevated
                ? 'your resting heart rate is up'
                : 'recovery is $pct%'} — the most productive thing today is nothing hard.'
          : i.plainWords
          ? ' Make today a rest day: walk, stretch and be in bed by ${i.bedtime}.'
          : ' — rest day. Keep strain under ${t.hi.round()} and be in bed by ${i.bedtime}.',
      over && r > 33 ? CallReason.overreaching : CallReason.lowRecovery,
    );
  }

  if (i.state == DayState.easeOff) {
    final why = easeReason(i);
    if (why != CallReason.steady && r >= 67) {
      return DailyCall(
        lead,
        CallTone.mid,
        i.plainWords
            ? ' But ${_because(why, i.daysSinceHard)}, so keep it easy today; a walk or easy session fits.'
            : ' — but ${_because(why, i.daysSinceHard)}. Keep it aerobic today; aim for $range strain.',
        why,
      );
    }
    if (r < 50) {
      return DailyCall(
        lead,
        recoveryTone(r),
        i.plainWords
            ? ' Go gently today; light movement helps more than a hard push.'
            : ' — keep strain under ${t.hi.round()} today.',
        CallReason.lowRecovery,
      );
    }
    return DailyCall(
      lead,
      recoveryTone(r),
      i.plainWords
          ? ' A steady day — keep it moderate.'
          : ' — a steady day. Keep it moderate; aim for $range strain.',
      CallReason.steady,
    );
  }

  final what = i.planTitle == null
      ? 'a hard session'
      : i.planHard
      ? i.planTitle!.toLowerCase()
      : 'a solid session';
  return DailyCall(
    lead,
    recoveryTone(r),
    i.plainWords
        ? ' A good day to move more — ${i.planTitle == null ? 'a brisk walk or a workout' : 'today’s ${i.planTitle!.toLowerCase()} or a brisk walk'} both fit.'
        : ' — you’re primed. A good day for $what; aim for $range strain.',
    CallReason.primed,
  );
}

String _plainLead(double r) => r >= 67
    ? 'Well rested.'
    : r >= 34
    ? 'Steady.'
    : 'Running low.';

/// What Today leads with (§7 of the flow doc).
enum DayPhase { newcomer, rest, morning, day, done, evening }

/// The phase of the day for Today's layout: the first 14 nights and rest
/// days have their own; otherwise the clock decides, and a finished
/// session turns the day into its recap until the evening.
DayPhase dayPhase({
  required int nowMinute,
  required int bedtimeMinute,
  bool firstDay = false,
  bool calibrating = false,
  bool restDay = false,
  bool sessionDone = false,
}) {
  if (firstDay || calibrating) return DayPhase.newcomer;
  if (restDay) return DayPhase.rest;
  // A bedtime after midnight belongs to tonight, not this morning.
  final bed = bedtimeMinute < 6 * 60 ? bedtimeMinute + 1440 : bedtimeMinute;
  if (nowMinute >= bed - 120) return DayPhase.evening;
  if (sessionDone) return DayPhase.done;
  return nowMinute < 12 * 60 ? DayPhase.morning : DayPhase.day;
}
