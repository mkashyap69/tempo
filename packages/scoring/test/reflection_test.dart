import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 24, 9);
  Reflection r(int hoursAgo, Set<ReflectTag> tags) => Reflection(
    at: now.subtract(Duration(hours: hoursAgo)),
    title: 'Upper body',
    tags: tags,
  );

  test('sore in the last 36 h offers to ease the week', () {
    final c = reflectCall([
      r(14, {ReflectTag.sore}),
    ], now)!;
    expect(c.action, ReflectAction.easeWeek);
  });

  test('pain wins over sore; the newest counts', () {
    final c = reflectCall([
      r(30, {ReflectTag.pain}),
      r(10, {ReflectTag.sore, ReflectTag.pain}),
      r(5, {ReflectTag.strong}),
    ], now)!;
    expect(c.action, ReflectAction.injury);
    expect(c.from.at, now.subtract(const Duration(hours: 10)));
  });

  test('older than 36 h, other tags, or already handled: nothing', () {
    expect(
      reflectCall([
        r(40, {ReflectTag.sore}),
      ], now),
      isNull,
    );
    expect(
      reflectCall([
        r(4, {ReflectTag.tired, ReflectTag.hard}),
      ], now),
      isNull,
    );
    final x = r(4, {ReflectTag.sore});
    expect(reflectCall([x], now, handled: {x.at}), isNull);
  });

  test('empty reflections', () {
    expect(Reflection(at: now, title: 'Run').isEmpty, isTrue);
    expect(Reflection(at: now, title: 'Run', text: ' ok ').isEmpty, isFalse);
  });
}
