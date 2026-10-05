import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final a = DateTime(2026, 10, 4, 23);
  final b = a.add(const Duration(hours: 8));
  List<Spo2Point> mins(int n, int Function(int) v, {int q = 64}) => [
    for (var i = 0; i < n; i++)
      (ts: a.add(Duration(minutes: i)), avg: v(i), quality: q),
  ];
  List<DropEvent> drops(int n, {int drop = 4}) => [
    for (var i = 0; i < n; i++)
      (ts: a.add(Duration(minutes: 3 * i + 1)), drop: drop),
  ];

  test('rate bands: 0 → 100, 5 → 90, 15 → 55, 30 → 35, 65 → 0', () {
    expect(scoreForRate(0), 100);
    expect(scoreForRate(5), 90);
    expect(scoreForRate(15), 55);
    expect(scoreForRate(30), 35);
    expect(scoreForRate(65), 0);
    expect(scoreForRate(10), lessThan(scoreForRate(9)));
  });

  test('calm night: few events, steady 96 %', () {
    final n = breathingNight(
      start: a,
      end: b,
      sleptHours: 8,
      spo2: mins(400, (_) => 96),
      events: drops(8),
    )!;
    expect(n.eventsPerHour, 1);
    expect(n.avgSpo2, 96);
    expect(n.belowNinety, 0);
    expect(n.score, 98);
    expect(n.label, 'Good');
  });

  test('time below 90 % and many events lower the score', () {
    final n = breathingNight(
      start: a,
      end: b,
      sleptHours: 8,
      spo2: mins(400, (i) => i % 10 == 0 ? 88 : 95),
      events: drops(96),
    )!;
    expect(n.eventsPerHour, 12);
    expect(n.belowNinety, closeTo(.1, 1e-9));
    expect(n.lowestSpo2, 88);
    // 12/h → 65.5; 10 % under 90 → −15; avg 94.3 → −1.4
    expect(n.score, 49);
    expect(n.label, 'Poor');
  });

  test(
    'low-confidence minutes, small drops and outside events are ignored',
    () {
      final n = breathingNight(
        start: a,
        end: b,
        sleptHours: 8,
        spo2: [...mins(100, (_) => 96), ...mins(50, (_) => 80, q: 10)],
        events: [
          ...drops(4, drop: 2),
          (ts: b.add(const Duration(hours: 1)), drop: 9),
        ],
      )!;
      expect(n.minutes, 100);
      expect(n.lowestSpo2, 96);
      expect(n.events, 0);
    },
  );

  test('too little SpO₂: no score', () {
    expect(
      breathingNight(
        start: a,
        end: b,
        sleptHours: 8,
        spo2: mins(30, (_) => 96),
        events: const [],
      ),
      isNull,
    );
  });
}
