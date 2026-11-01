import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final mon = DateTime(2026, 10, 26, 18);
  final thu = DateTime(2026, 10, 29, 18);
  SetLog s(
    String ex,
    DateTime at, {
    double kg = 60,
    int reps = 8,
    int seconds = 0,
  }) => SetLog(exercise: ex, at: at, kg: kg, reps: reps, seconds: seconds);

  test('repeat last session takes the newest day in the order done', () {
    final sets = [
      s('back_squat', mon),
      s('back_squat', mon.add(const Duration(minutes: 3))),
      s('bench_press', thu.add(const Duration(minutes: 10)), reps: 6),
      s('bench_press', thu.add(const Duration(minutes: 13)), reps: 6),
      s('bench_press', thu.add(const Duration(minutes: 16)), reps: 5),
      s(
        'plank',
        thu.add(const Duration(minutes: 20)),
        kg: 0,
        reps: 0,
        seconds: 45,
      ),
      s('not_in_library', thu),
    ];
    final r = lastSessionRoutine(sets)!;
    expect(r.name, 'Last session');
    expect([for (final x in r.items) x.name], ['Bench press', 'Plank']);
    expect(r.items[0].sets, 3);
    expect(r.items[0].reps, '6');
    expect(r.items[1].reps, '45 s');
  });

  test('nothing to repeat', () {
    expect(lastSessionRoutine(const []), isNull);
    expect(lastSessionRoutine([s('not_in_library', thu)]), isNull);
  });

  test('focus from where the work is', () {
    Routine r(List<String> names) =>
        Routine('x', [for (final n in names) Exercise(n, sets: 3, reps: '8')]);
    expect(
      routineFocus(r(['Back squat', 'Romanian deadlift'])),
      StrengthFocus.lower,
    );
    expect(routineFocus(r(['Bench press', 'Pull-up'])), StrengthFocus.upper);
    expect(routineFocus(r(['Back squat', 'Bench press'])), StrengthFocus.full);
  });

  test('a routine round-trips and opens as a strength session', () {
    final r = Routine('Push day', const [
      Exercise('Bench press', sets: 4, reps: '6'),
    ]);
    final back = Routine.fromJson(r.toJson());
    expect(back.name, 'Push day');
    expect(back.items.single.sets, 4);
    final sess = routineSession(back, minutes: 50);
    expect(sess.sport, Sport.strength);
    expect(sess.title, 'Push day');
    expect(sess.minutes, 50);
    expect(
      (sess.detail! as StrengthDetail).exercises.single.name,
      'Bench press',
    );
  });
}
