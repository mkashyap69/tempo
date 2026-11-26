import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/core/day_story.dart';

void main() {
  test('wake, workouts, the plan, wind-down and bedtime in order', () {
    final s = dayStory(
      nowMinute: 9 * 60,
      bedtimeMinute: 22 * 60 + 50,
      wakeMinute: 6 * 60 + 52,
      sleptHours: 7.7,
      workouts: [(8 * 60 + 10, 8 * 60 + 28, 'Walking')],
      planTitle: 'Tempo run',
      plannedMinute: 17 * 60 + 30,
    );
    expect(s.map((e) => e.kind), [
      StoryKind.wake,
      StoryKind.workout,
      StoryKind.planned,
      StoryKind.windDown,
      StoryKind.bedtime,
    ]);
    expect(s.first.sub, '7 h 42 m asleep');
    expect(s[1].sub, '18 min');
    expect(s.where((e) => e.done).length, 2);
    expect(s[3].minute, 22 * 60 + 20);
  });

  test('an unscheduled plan sits just before wind-down', () {
    final s = dayStory(
      nowMinute: 9 * 60,
      bedtimeMinute: 23 * 60,
      planTitle: 'Easy run',
    );
    expect(s.map((e) => e.kind), [
      StoryKind.planned,
      StoryKind.windDown,
      StoryKind.bedtime,
    ]);
    expect(s.first.sub, 'Planned for later today');
  });

  test('a bedtime after midnight stays last', () {
    final s = dayStory(nowMinute: 20 * 60, bedtimeMinute: 30);
    expect(s.last.kind, StoryKind.bedtime);
    expect(s[s.length - 2].minute, 0);
  });

  test('wind-down is done once its time has passed', () {
    final s = dayStory(nowMinute: 22 * 60 + 40, bedtimeMinute: 22 * 60 + 50);
    expect(s.firstWhere((e) => e.kind == StoryKind.windDown).done, isTrue);
  });

  test('a busy day folds the earlier activities into one line', () {
    final s = dayStory(
      nowMinute: 18 * 60,
      bedtimeMinute: 23 * 60,
      workouts: [for (var h = 8; h < 14; h++) (h * 60, h * 60 + 10, 'Walking')],
    );
    final w = s.where((e) => e.kind == StoryKind.workout).toList();
    expect(w.length, maxWorkouts + 1);
    expect(w.first.title, '3 earlier activities');
  });
}
