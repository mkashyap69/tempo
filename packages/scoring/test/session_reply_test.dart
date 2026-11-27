import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('on plan: the plan holds, nothing to add', () {
    final r = sessionReply(
      rpe: expectedRpe(Intensity.hard),
      planned: Intensity.hard,
      trend: Effort.onTrack,
    );
    expect(r.line, contains('plan holds'));
    expect(r.next, isNull);
  });

  test('harder than planned once is not a pattern', () {
    final r = sessionReply(
      rpe: expectedRpe(Intensity.moderate) + 3,
      planned: Intensity.moderate,
      trend: Effort.onTrack,
    );
    expect(r.line, 'Harder than planned.');
    expect(r.next, contains('isn’t a pattern'));
  });

  test(
    'a run of hard-feeling sessions: the coach will ease the next hard day',
    () {
      final r = sessionReply(
        rpe: expectedRpe(Intensity.hard) + 2,
        planned: Intensity.hard,
        trend: Effort.heavy,
      );
      expect(r.next, contains('suggest an easier session'));
    },
  );

  test('a run of easy-feeling sessions: an easy day can step up', () {
    final r = sessionReply(
      rpe: expectedRpe(Intensity.easy) - 2,
      planned: Intensity.easy,
      trend: Effort.light,
    );
    expect(r.line, startsWith('Easier than planned'));
    expect(r.next, contains('stepping an easy day up'));
  });
}
