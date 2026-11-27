/// v3 coach quick replies (0.8.0): one tap on the call card — short on
/// time, feeling flat, up for more — and the coach shows the change before
/// it makes it (canvas "Interactive coach" 1).
library;

import 'dart:math';

import 'coach.dart';

enum QuickReply { shortOnTime, feelingFlat, upForMore }

String quickReplyLabel(QuickReply r) => switch (r) {
  QuickReply.shortOnTime => 'Short on time',
  QuickReply.feelingFlat => 'Feeling flat',
  QuickReply.upForMore => 'Up for more',
};

/// The minutes Short on time offers.
const quickReplyMinutes = [20, 30, 45, 60];

typedef ReplyOffer = ({
  QuickReply reply,
  Session to,
  String headline,
  String why,
});

/// Up for more is offered only on a go day from recovery 67.
bool upForMoreAllowed({double? recovery, DayState state = DayState.general}) =>
    recovery != null && recovery >= 67 && state == DayState.go;

/// What [reply] would make of today's [plan], or null when it doesn't
/// apply (a rest day; Up for more on a day that isn't a go day; Short on
/// time with [minutes] the plan already fits in).
ReplyOffer? quickReplyOffer(
  Session plan,
  QuickReply reply, {
  int minutes = 30,
  double? recovery,
  DayState state = DayState.general,
  int maxMinutes = 90,
}) {
  if (plan.isRest || plan.segments.isEmpty) return null;
  switch (reply) {
    case QuickReply.shortOnTime:
      if (minutes >= plan.minutes) return null;
      final to = fitDay(plan, minutes);
      final before = repCount(plan), after = repCount(to);
      final String why;
      if (to.minutes > minutes) {
        why =
            'This is as short as it goes and still does its job: ${to.minutes} min.';
      } else if (before != null && after != null && after < before) {
        why =
            '$after reps instead of $before, with a shorter warm-up. Still today’s key work.';
      } else {
        why = plan.isHard
            ? 'Shorter warm-up and cool-down; the main set stays.'
            : 'Same easy effort, just less of it.';
      }
      return (
        reply: reply,
        to: to,
        headline: plan.isHard
            ? 'Keep the quality, cut the extras.'
            : 'Same session, shorter.',
        why: why,
      );
    case QuickReply.feelingFlat:
      if (plan.isHard) {
        final easy = sessionTemplate(easierKeyFor(plan));
        return (
          reply: reply,
          to: fitMinutes(easy, min(plan.minutes, 45)),
          headline: 'Easy today; the hard session waits.',
          why:
              'Your numbers may say ready, but you know how you feel. The coach brings ${plan.title.toLowerCase()} back on a better morning.',
        );
      }
      return (
        reply: reply,
        to: scaled(plan, max(20, plan.minutes * .7) / plan.minutes),
        headline: 'Shorter and gentler.',
        why: 'Keep moving, just less of it. A walk counts too.',
      );
    case QuickReply.upForMore:
      if (!upForMoreAllowed(recovery: recovery, state: state)) return null;
      final n = repCount(plan);
      if (n != null) {
        final to = scaled(plan, (n + 1) / n, cap: maxMinutes);
        if (repCount(to) == n) return null;
        return (
          reply: reply,
          to: to,
          headline: 'One more rep, not a harder one.',
          why:
              'Recovery is ${recovery!.round()} and it’s a go day, so ${n + 1} reps fit. Same pace as planned.',
        );
      }
      final to = scaled(
        plan,
        (plan.minutes + 15) / plan.minutes,
        cap: maxMinutes,
      );
      if (to.minutes <= plan.minutes) return null;
      return (
        reply: reply,
        to: to,
        headline: '${to.minutes - plan.minutes} minutes more, same effort.',
        why:
            'Recovery is ${recovery!.round()} and it’s a go day: more time at the same effort builds the base without the cost of going harder.',
      );
  }
}
