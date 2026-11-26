/// v3 Today: "Your day so far", the day as a short timeline, done things
/// solid and what's still ahead hollow (docs/research/v3 UI.md).
library;

/// Activities shown one by one before the rest are folded into one line.
const maxWorkouts = 3;

enum StoryKind { wake, workout, planned, windDown, bedtime }

final class StoryEvent {
  const StoryEvent({
    required this.kind,
    required this.title,
    this.minute,
    this.sub,
    this.done = false,
  });
  final StoryKind kind;

  /// Minute of the day, or null for "later today".
  final int? minute;
  final String title;
  final String? sub;
  final bool done;
}

String _hm(double h) {
  final m = (h * 60).round();
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m';
}

/// The day's events in order. [workouts] are (start, end, title) in minutes
/// of the day; [planTitle] is today's session when it isn't done yet;
/// [bedtimeMinute] is tonight's lights out (may be after midnight, < 6 h).
List<StoryEvent> dayStory({
  required int nowMinute,
  required int bedtimeMinute,
  int? wakeMinute,
  double? sleptHours,
  List<(int, int, String)> workouts = const [],
  String? planTitle,
  int? plannedMinute,
}) {
  final out = <StoryEvent>[];
  if (wakeMinute != null) {
    out.add(
      StoryEvent(
        kind: StoryKind.wake,
        minute: wakeMinute,
        title: 'Woke up',
        sub: sleptHours == null ? null : '${_hm(sleptHours)} asleep',
        done: true,
      ),
    );
  }
  // Busy days (a band counts every walk): the latest few, the rest as one
  // line.
  final shown = workouts.length > maxWorkouts
      ? workouts.sublist(workouts.length - maxWorkouts)
      : workouts;
  if (workouts.length > shown.length) {
    final n = workouts.length - shown.length;
    out.add(
      StoryEvent(
        kind: StoryKind.workout,
        minute: workouts.first.$1,
        title: '$n earlier ${n == 1 ? 'activity' : 'activities'}',
        done: true,
      ),
    );
  }
  for (final (start, end, title) in shown) {
    out.add(
      StoryEvent(
        kind: StoryKind.workout,
        minute: start,
        title: title,
        sub: '${end - start} min',
        done: true,
      ),
    );
  }
  // Bedtime after midnight sorts after the evening.
  final bed = bedtimeMinute < 6 * 60 ? bedtimeMinute + 1440 : bedtimeMinute;
  if (planTitle != null) {
    final late = plannedMinute != null && plannedMinute < nowMinute;
    out.add(
      StoryEvent(
        kind: StoryKind.planned,
        minute: plannedMinute,
        title: planTitle,
        sub: plannedMinute == null
            ? 'Planned for later today'
            : late
            ? 'Planned, still time today'
            : 'Planned',
      ),
    );
  }
  out.add(
    StoryEvent(
      kind: StoryKind.windDown,
      minute: (bed - 30) % 1440,
      title: 'Wind down',
      sub: 'Screens down, lights low',
      done: nowMinute >= bed - 30,
    ),
  );
  out.add(
    StoryEvent(
      kind: StoryKind.bedtime,
      minute: bedtimeMinute,
      title: 'Lights out',
      sub: 'For the sleep you need tonight',
    ),
  );
  int key(StoryEvent e) {
    final m = e.minute;
    if (m == null) return bed - 31; // later today: just before wind-down
    return m < 6 * 60 && e.kind != StoryKind.wake ? m + 1440 : m;
  }

  out.sort((a, b) => key(a).compareTo(key(b)));
  return out;
}
