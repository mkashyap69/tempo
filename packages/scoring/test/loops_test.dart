// Feedback-loop regression tests (docs/research/Algorithm review.md §11.5):
// simulated users scored night after night through scoreDay, each day's
// result fed back as history, as the app does.
import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// One simulated night: hours asleep from 23:00, and the sleeping HR.
typedef Night = ({double hours, int hr});

/// Scores [nights.length] days in order. Day i's night starts at 23:00 the
/// evening before; awake minutes sit at 70 bpm, which adds no strain.
List<DailyScore> simulate(List<Night> nights, {String source = bandSource}) {
  final d0 = DateTime(2026, 1, 1);
  final minutes = <Minute>[];
  for (var i = 0; i <= nights.length; i++) {
    final bed = d0.add(Duration(days: i - 1, hours: 23));
    final n = i < nights.length ? nights[i] : (hours: 7.5, hr: 52);
    final asleep = (n.hours * 60).round();
    for (var m = 0; m < 24 * 60; m++) {
      minutes.add(
        Minute(
          bed.add(Duration(minutes: m)),
          hr: m < asleep ? n.hr + m % 3 : 70,
          stage: m < asleep ? Stage.light : Stage.wake,
        ),
      );
    }
  }
  final history = <DailyScore>[];
  for (var i = 0; i < nights.length; i++) {
    final day = d0.add(Duration(days: i));
    final from = day.subtract(const Duration(hours: 12));
    final to = day.add(const Duration(hours: 36));
    final s = scoreDay(
      date: day,
      minutes: [
        for (final m in minutes)
          if (!m.ts.isBefore(from) && m.ts.isBefore(to)) m,
      ],
      history: history,
      source: source,
    );
    history.insert(0, s);
  }
  return history.reversed.toList();
}

void main() {
  test('sleeping the base need every night: no debt, need = base', () {
    final days = simulate(List.filled(30, (hours: 7.5, hr: 52)));
    final last = days.last;
    expect(last.debtHours, 0);
    expect(last.baseNeedHours, 7.5);
    expect(last.needHours, closeTo(7.5, 1e-9));
    expect(last.sleepScore, greaterThan(95));
  });

  test('L1: debt reaches the cap when short, and clears once you sleep', () {
    final days = simulate([
      ...List.filled(10, (hours: 6.5, hr: 52)),
      ...List.filled(10, (hours: 8, hr: 52)),
    ]);
    // Ten 1-h-short nights: capped at 2 h, need 7.5 + 1.
    expect(days[10].debtHours, 2);
    expect(days[10].needHours, closeTo(8.5, 1e-9));
    // Algo 9 kept it at 2 h for good once there; now it falls every
    // full night and is under half an hour within ten.
    for (var i = 11; i < 20; i++) {
      final prev = days[i - 1].debtHours!;
      if (prev > 0) expect(days[i].debtHours, lessThan(prev));
    }
    expect(days.last.debtHours, lessThan(.5));
  });

  test('L1: a normal night after a short week does not hold the cap', () {
    final days = simulate([
      ...List.filled(7, (hours: 6, hr: 52)),
      ...List.filled(5, (hours: 7.5, hr: 52)),
    ]);
    expect(days[7].debtHours, 2);
    // Algo 9: need 8.5+ made 7.5 h a 1-h shortfall, so debt stayed 2 h.
    expect(days.last.debtHours, lessThan(1.5));
  });

  test('L2: varied sleep with flat HR does not learn the longest night', () {
    // 6.5–9.5 h, resting HR unrelated to length: algo 9 ranked by
    // Recovery, which held sleep performance, and learned ~9 h.
    final days = simulate([
      for (var i = 0; i < 40; i++) (hours: 6.5 + (i * 7 % 13) / 4, hr: 52),
    ]);
    expect(days.last.baseNeedHours, lessThanOrEqualTo(8));
  });

  test('L2: base need follows the nights after which HR was lowest', () {
    // 8.5 h nights come with a 6 bpm lower resting HR than 7 h ones.
    final days = simulate([
      for (var i = 0; i < 30; i++)
        i.isEven ? (hours: 8.5, hr: 48) : (hours: 7.0, hr: 54),
    ]);
    expect(days.last.baseNeedHours, 8.5);
  });

  test('L3: a short week lowers recovery that week, not the next one', () {
    // Sleep and resting HR wobble a little night to night, the same in
    // both runs (a flat history has no spread to judge against).
    Night n(int i, double h) => (hours: h + (i % 3) / 4, hr: 51 + i % 3);
    final base = simulate([for (var i = 0; i < 40; i++) n(i, 7.5)]);
    final dipped = simulate([
      for (var i = 0; i < 40; i++) n(i, i >= 25 && i < 30 ? 6 : 7.5),
    ]);
    // Same 7.5 h nights afterwards: the same recovery as never short,
    // because Recovery's sleep input is against the base, not the
    // debt-raised need.
    expect(dipped.last.recovery, closeTo(base.last.recovery!, 1));
    expect(dipped[27].recovery, lessThan(base[27].recovery!));
  });

  test('need never runs away: base + half the cap + strain at most', () {
    final days = simulate([
      for (var i = 0; i < 60; i++) (hours: i % 5 == 0 ? 5.0 : 7.0, hr: 52),
    ]);
    for (final d in days) {
      expect(d.needHours, lessThanOrEqualTo(d.baseNeedHours! + 1 + .21));
      expect(d.baseNeedHours, inInclusiveRange(7, 9));
    }
  });
}
