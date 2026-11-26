import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('three bedtimes for 100, 85 and 70 % of the need', () {
    // 8 h need, wake 7:00, 10 min to fall asleep.
    final o = bedtimeOptions(8, 7 * 60);
    expect(o.map((x) => x.share), [1.0, .85, .7]);
    expect(o[0].minute, 22 * 60 + 50);
    expect(o[1].minute, 24 * 60 + 2 - 1440); // 6 h 48 m: 00:02
    expect(o[2].minute, 1 * 60 + 14); // 5 h 36 m: 01:14
  });

  test('wake time follows weekday or weekend', () {
    final fri = DateTime(2026, 11, 20); // Friday
    final nights = [
      for (var i = 0; i < 14; i++)
        () {
          final d = fri.subtract(Duration(days: i));
          final weekend = d.weekday >= DateTime.saturday;
          return (d, weekend ? 9 * 60 : 7 * 60);
        }(),
    ];
    expect(wakeFor(DateTime(2026, 11, 23), nights), 7 * 60); // Monday
    expect(wakeFor(DateTime(2026, 11, 21), nights), 9 * 60); // Saturday
  });

  test('too few of the kind: all nights; too few at all: null', () {
    final mon = DateTime(2026, 11, 16);
    final weekdays = [
      for (var i = 0; i < 5; i++) (mon.add(Duration(days: i)), 7 * 60),
    ];
    expect(wakeFor(DateTime(2026, 11, 22), weekdays), 7 * 60);
    expect(wakeFor(mon, weekdays.take(2).toList()), isNull);
  });
}
