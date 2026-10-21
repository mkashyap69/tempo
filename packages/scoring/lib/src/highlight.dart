/// Today's insight: one card a day, picked from what Tempo already knows
/// (docs/research/User flow and journey.md §7). Each candidate has a
/// trigger, a priority, a cool-down and one action. Thresholds are
/// starting values to tune from the field diary.
library;

import 'dart:math';

import 'everyday.dart' show briskTarget;
import 'load.dart';

enum HighlightKind {
  bodySignal,
  sleepDebt,
  experimentDone,
  load,
  journalImpact,
  regularity,
  socialJetlag,
  tempoAge,
  stillStretch,
  brisk,
  personalBest,
  strength,
}

/// Where the card's button goes.
enum HighlightAction {
  signals,
  tonight,
  experiment,
  week,
  tryExperiment,
  bedtimeNudge,
  sleep,
  tempoAge,
  day,
  picks,
  trend,
  logStrength,
}

final class Highlight {
  const Highlight({
    required this.kind,
    required this.key,
    required this.tag,
    required this.title,
    required this.body,
    required this.action,
    required this.actionLabel,
    required this.priority,
  });
  final HighlightKind kind;

  /// Stable id for cool-downs ("journal:late_meal").
  final String key;
  final String tag, title, body, actionLabel;
  final HighlightAction action;
  final int priority;
}

/// Days before the same kind can show again.
const highlightCooldown = <HighlightKind, int>{
  HighlightKind.bodySignal: 2,
  HighlightKind.sleepDebt: 3,
  HighlightKind.experimentDone: 30,
  HighlightKind.load: 7,
  HighlightKind.journalImpact: 5,
  HighlightKind.regularity: 7,
  HighlightKind.socialJetlag: 7,
  HighlightKind.tempoAge: 6,
  HighlightKind.stillStretch: 3,
  HighlightKind.brisk: 4,
  HighlightKind.personalBest: 5,
  HighlightKind.strength: 7,
};

/// One journal behaviour or one kind of record waits this long before it
/// can show again, whatever else showed in between.
const highlightKeyCooldown = 21;

const _keyed = {
  HighlightKind.journalImpact,
  HighlightKind.personalBest,
  HighlightKind.experimentDone,
};

/// What the app knows today, all optional.
final class HighlightFacts {
  const HighlightFacts({
    this.bodyOff = const [],
    this.debtHours = 0,
    this.sri,
    this.jetlagMinutes,
    this.stillMinutes,
    this.briskAvg,
    this.weekday = 1,
    this.impact,
    this.experimentDone,
    this.load = LoadStatus.learning,
    this.loadPercent,
    this.ageDelta,
    this.ageLever,
    this.rhr,
    this.rhrLow,
    this.hrv,
    this.hrvHigh,
    this.strengthGapDays,
  });

  /// Night signals off when they aren't enough for the rest-day alert.
  final List<String> bodyOff;
  final double debtHours;

  /// Sleep regularity index and weekend shift.
  final double? sri;
  final int? jetlagMinutes;

  /// Longest still stretch so far today.
  final int? stillMinutes;

  /// Brisk minutes a day over the last week; ISO weekday of today.
  final double? briskAvg;
  final int weekday;

  /// The journal behaviour with the clearest effect: its key, name and
  /// the effect in words ("−6 points on Recovery").
  final ({String key, String name, String effect, bool hurts})? impact;

  /// An experiment that ended in the last 3 days.
  final ({String key, String name, String result})? experimentDone;
  final LoadStatus load;

  /// 7-day vs 28-day load, in percent above (+) or below (−).
  final int? loadPercent;

  /// Tempo Age change this week (years) and the lever that moved it most.
  final double? ageDelta;
  final String? ageLever;

  /// Last night's resting HR and the lowest of the 90 nights before it.
  final double? rhr, rhrLow;

  /// Last night's HRV and the highest of the 90 nights before it.
  final double? hrv, hrvHigh;

  /// Days since the last strength session, when strength is on the plan.
  final int? strengthGapDays;
}

String _hm(double h) {
  final m = (h * 60).round();
  return m >= 60
      ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m'
      : '$m min';
}

/// Every candidate today's facts trigger, highest priority first.
List<Highlight> highlightCandidates(HighlightFacts f) {
  final out = <Highlight>[];
  if (f.bodyOff.isNotEmpty) {
    final n = f.bodyOff.first;
    out.add(
      Highlight(
        kind: HighlightKind.bodySignal,
        key: 'body:${f.bodyOff.join(',')}',
        tag: 'Body',
        title: f.bodyOff.length == 1
            ? 'Your ${n.toLowerCase()} is off your usual'
            : '${f.bodyOff.length} night signals are off',
        body: 'One night isn’t a worry on its own. An easier start today helps you see if it settles.',
        action: HighlightAction.signals,
        actionLabel: 'See signals',
        priority: 90,
      ),
    );
  }
  if (f.debtHours >= 2) {
    out.add(
      Highlight(
        kind: HighlightKind.sleepDebt,
        key: 'debt',
        tag: 'Sleep',
        title: '${_hm(f.debtHours)} of sleep debt',
        body: 'Short nights this week add up. Tonight’s bedtime already allows for some of it.',
        action: HighlightAction.tonight,
        actionLabel: 'Plan tonight',
        priority: 80,
      ),
    );
  }
  if (f.experimentDone case final e?) {
    out.add(
      Highlight(
        kind: HighlightKind.experimentDone,
        key: 'experiment:${e.key}',
        tag: 'Journal',
        title: 'Experiment done: ${e.name.toLowerCase()}',
        body: e.result,
        action: HighlightAction.experiment,
        actionLabel: 'See the result',
        priority: 75,
      ),
    );
  }
  if (f.load == LoadStatus.overreaching || f.load == LoadStatus.detraining) {
    final over = f.load == LoadStatus.overreaching;
    final p = f.loadPercent?.abs();
    out.add(
      Highlight(
        kind: HighlightKind.load,
        key: 'load:${f.load.name}',
        tag: 'Load',
        title: over ? 'Your load is running hot' : 'Your load has dropped',
        body: over
            ? 'The last 7 days are ${p == null ? 'well' : '$p%'} above your usual 28. The plan eases the next days.'
            : 'The last 7 days are ${p == null ? 'well' : '$p%'} under your usual 28. Fitness slips if it stays there.',
        action: HighlightAction.week,
        actionLabel: 'See this week',
        priority: 70,
      ),
    );
  }
  if (f.impact case final i?) {
    out.add(
      Highlight(
        kind: HighlightKind.journalImpact,
        key: 'journal:${i.key}',
        tag: 'Journal',
        title: '${i.name}: ${i.effect}',
        body: i.hurts
            ? 'From your check-ins. Two weeks without it would show if it’s real for you.'
            : 'From your check-ins. Two weeks of doing it daily would show if it’s real for you.',
        action: HighlightAction.tryExperiment,
        actionLabel: 'Try 14 days',
        priority: 65,
      ),
    );
  }
  if (f.sri != null && f.sri! < 65) {
    out.add(
      Highlight(
        kind: HighlightKind.regularity,
        key: 'regularity',
        tag: 'Sleep',
        title: 'Your sleep times are irregular',
        body:
            'Regularity ${f.sri!.round()} of 100 over two weeks. Bed within the same 30 minutes, weekends too, is one of the simplest levers there is.',
        action: HighlightAction.bedtimeNudge,
        actionLabel: 'Set a bedtime nudge',
        priority: 60,
      ),
    );
  }
  if (f.jetlagMinutes != null && f.jetlagMinutes!.abs() >= 60) {
    final h = f.jetlagMinutes!.abs() / 60;
    out.add(
      Highlight(
        kind: HighlightKind.socialJetlag,
        key: 'jetlag',
        tag: 'Sleep',
        title:
            'Weekends run ${_hm(h)} ${f.jetlagMinutes! > 0 ? 'later' : 'earlier'}',
        body: 'Your sleep midpoint shifts between workdays and days off, like a small time-zone change each week.',
        action: HighlightAction.sleep,
        actionLabel: 'See your rhythm',
        priority: 55,
      ),
    );
  }
  if (f.ageDelta != null && f.ageDelta!.abs() >= .3) {
    final d = f.ageDelta!;
    out.add(
      Highlight(
        kind: HighlightKind.tempoAge,
        key: 'age',
        tag: 'Tempo Age',
        title:
            'Tempo Age moved ${d < 0 ? '−' : '+'}${d.abs().toStringAsFixed(1)} years',
        body: f.ageLever == null
            ? 'This week’s update is in.'
            : 'Moved most by ${f.ageLever!.toLowerCase()}.',
        action: HighlightAction.tempoAge,
        actionLabel: 'See what moved it',
        priority: 50,
      ),
    );
  }
  if (f.stillMinutes != null && f.stillMinutes! >= 120) {
    out.add(
      Highlight(
        kind: HighlightKind.stillStretch,
        key: 'still',
        tag: 'Movement',
        title: 'Still for ${_hm(f.stillMinutes! / 60)}',
        body: 'Your longest stretch without moving today. A five-minute walk resets it.',
        action: HighlightAction.day,
        actionLabel: 'See your day',
        priority: 45,
      ),
    );
  }
  if (f.briskAvg != null && f.weekday >= 4 && f.briskAvg! < briskTarget * .7) {
    out.add(
      Highlight(
        kind: HighlightKind.brisk,
        key: 'brisk',
        tag: 'Movement',
        title: '${f.briskAvg!.round()} brisk minutes a day',
        body:
            'Under the $briskTarget a day that counts toward the weekly health minimum. A brisk walk today closes the gap.',
        action: HighlightAction.picks,
        actionLabel: 'Start a brisk walk',
        priority: 40,
      ),
    );
  }
  if (f.rhr != null && f.rhrLow != null && f.rhr! < f.rhrLow!) {
    out.add(
      Highlight(
        kind: HighlightKind.personalBest,
        key: 'pb:rhr',
        tag: 'Fitness',
        title: 'Lowest resting heart rate in 90 days',
        body:
            '${f.rhr!.round()} bpm last night. Resting heart rate falls as fitness and sleep improve.',
        action: HighlightAction.trend,
        actionLabel: 'See trend',
        priority: 35,
      ),
    );
  } else if (f.hrv != null && f.hrvHigh != null && f.hrv! > f.hrvHigh!) {
    out.add(
      Highlight(
        kind: HighlightKind.personalBest,
        key: 'pb:hrv',
        tag: 'Fitness',
        title: 'Highest HRV in 90 days',
        body: '${f.hrv!.round()} ms last night.',
        action: HighlightAction.trend,
        actionLabel: 'See trend',
        priority: 35,
      ),
    );
  }
  if (f.strengthGapDays != null && f.strengthGapDays! >= 10) {
    out.add(
      Highlight(
        kind: HighlightKind.strength,
        key: 'strength',
        tag: 'Strength',
        title: '${f.strengthGapDays} days since strength',
        body: 'Two strength days a week keep muscle and bone. A short session counts.',
        action: HighlightAction.logStrength,
        actionLabel: 'Log strength',
        priority: 30,
      ),
    );
  }
  out.sort((a, b) => b.priority.compareTo(a.priority));
  return out;
}

/// One shown insight, as the app keeps it.
typedef HighlightShown = ({String kind, String key, DateTime day});

/// Today's card, or null. Rest days and Mondays (the week review) show
/// none; once picked, the day keeps the same card.
Highlight? pickHighlight(
  List<Highlight> candidates,
  List<HighlightShown> shown,
  DateTime today, {
  bool restDay = false,
  bool monday = false,
}) {
  if (restDay || monday || candidates.isEmpty) return null;
  final d0 = DateTime(today.year, today.month, today.day);
  int ago(DateTime d) => d0.difference(DateTime(d.year, d.month, d.day)).inDays;
  for (final s in shown) {
    if (ago(s.day) == 0) {
      return candidates.where((c) => c.key == s.key).firstOrNull;
    }
  }
  for (final c in candidates) {
    final cool = highlightCooldown[c.kind] ?? 7;
    final blocked = shown.any(
      (s) =>
          (s.kind == c.kind.name && ago(s.day) < cool) ||
          (_keyed.contains(c.kind) &&
              s.key == c.key &&
              ago(s.day) < max(cool, highlightKeyCooldown)),
    );
    if (!blocked) return c;
  }
  return null;
}
