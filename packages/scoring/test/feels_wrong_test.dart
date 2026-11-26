import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('rest days have nothing to watch for', () {
    expect(feelsWrong(sessionTemplate('rest')), isEmpty);
  });

  test('an interval session offers one block fewer and going by HR', () {
    final s = sessionTemplate('threshold_run');
    final f = feelsWrong(s);
    final blocks = [
      for (final g in s.segments.sublist(1, s.segments.length - 1))
        if (g.zone >= 3) g,
    ].length;
    expect(blocks, greaterThanOrEqualTo(2));
    expect(f.first.action, contains('${blocks - 1}'));
    expect(f[1].action, contains('heart rate'));
    expect(f.last.sign, 'Sharp or growing pain');
  });

  test('an easy session is about the talk test', () {
    final f = feelsWrong(sessionTemplate('easy_run'));
    expect(f.first.sign, contains('talk'));
    expect(f.length, 2);
  });

  test('strength is about form and the warm-up sets', () {
    final f = feelsWrong(sessionTemplate('strength_full'));
    expect(f.first.sign, contains('Form'));
    expect(f.last.sign, 'Sharp or growing pain');
  });

  test('hard sessions add the stop signs', () {
    final s = sessionTemplate('threshold_run');
    expect(s.isHard, isTrue);
    expect(feelsWrong(s).map((x) => x.sign), contains(startsWith('Dizzy')));
  });
}
