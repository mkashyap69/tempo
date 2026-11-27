/// v3 interactive coach 3 (0.10.0): the coach answers your effort rating
/// after a session, in one line, and says what it will do about it — the
/// same effort comparison the morning adaptation uses ([effortTrend]).
library;

import 'coach.dart';

typedef SessionReply = ({String line, String? next});

/// [rpe] for a session planned at [planned]; [trend] is the effort trend
/// with this session counted.
SessionReply sessionReply({
  required int rpe,
  required Intensity planned,
  required Effort trend,
}) {
  final diff = rpe - expectedRpe(planned);
  final line = diff <= -2
      ? 'Easier than planned. That’s a good sign.'
      : diff >= 2
      ? 'Harder than planned.'
      : 'Right where it should be. The plan holds.';
  final String? next = switch (trend) {
    Effort.heavy => 'Your last sessions have felt harder than planned, so on your next hard day the coach will suggest an easier session and hold the hard one for a fresher morning.',
    Effort.light => 'Your last sessions have felt easy, so on a good morning the coach will suggest stepping an easy day up.',
    _ when diff.abs() >= 2 => 'One session isn’t a pattern. If the next one feels the same, the coach adjusts.',
    _ => null,
  };
  return (line: line, next: next);
}
