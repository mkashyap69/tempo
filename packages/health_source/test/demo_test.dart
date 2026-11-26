import 'package:health_source/health_source.dart';
import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final anchor = DateTime(2026, 11, 26, 12);
  final from = DateTime(2026, 10, 27);

  List<HealthRecord> all({bool apple = true}) => [
    for (final k in demoKinds(apple: apple))
      ...demoRecords(k, from, anchor, anchor: anchor, apple: apple),
  ];

  test('deterministic, unique keys, nothing from the future', () {
    final a = all(), b = all();
    expect(a.map((r) => r.key).toList(), b.map((r) => r.key).toList());
    expect(a.map((r) => r.key).toSet().length, a.length);
    expect(a.every((r) => !r.end.isAfter(anchor)), isTrue);
    expect(a.every((r) => !r.start.isBefore(from)), isTrue);
  });

  test('reading in chunks gives the same records as one read', () {
    final whole = demoRecords(
      HealthKind.heartRate,
      from,
      anchor,
      anchor: anchor,
    ).map((r) => r.key).toSet();
    final mid = DateTime(2026, 11, 10);
    final parts = {
      ...demoRecords(HealthKind.heartRate, from, mid, anchor: anchor),
      ...demoRecords(HealthKind.heartRate, mid, anchor, anchor: anchor),
    }.map((r) => r.key).toSet();
    expect(parts, whole);
  });

  test('a night a day, about seven hours, with HR all day', () {
    final g = HealthGrid()..addAll(all());
    final mins = [for (final m in g.minutes(from, anchor)) m.toMinute()];
    final nights = detectSessions(mins)
        .where((s) => s.asleep.inHours >= 3)
        .toList();
    expect(nights.length, inInclusiveRange(28, 31));
    final normal = nights.last.asleep.inMinutes / 60;
    expect(normal, inInclusiveRange(5.5, 9));
    final awakeWithHr = mins
        .where((m) => m.stage == Stage.wake && m.hr != null)
        .length;
    expect(awakeWithHr, greaterThan(28 * 14 * 60 * .8));
  });

  test('the story: a cold and a drink show in the night vitals', () {
    final hrv = demoRecords(
      HealthKind.hrvSdnn,
      DateTime(2026, 8, 1),
      anchor,
      anchor: anchor,
    );
    double meanOn(DateTime day) {
      final xs = [
        for (final r in hrv)
          if (r.start.isAfter(DateTime(day.year, day.month, day.day - 1, 18)) &&
              r.start.isBefore(DateTime(day.year, day.month, day.day, 12)))
            r.value,
      ];
      return xs.reduce((a, b) => a + b) / xs.length;
    }

    final ill = anchor.subtract(const Duration(days: 37));
    final well = anchor.subtract(const Duration(days: 9));
    expect(demoIll(ill, anchor), isTrue);
    expect(meanOn(ill), lessThan(meanOn(well) * .85));
    expect(
      demoAlcohol(anchor.subtract(const Duration(days: 2)), anchor),
      isTrue,
    );
  });

  test('Health Connect flavour: sessions, RMSSD, SpO₂ in percent', () {
    final hc = all(apple: false);
    expect(hc.any((r) => r.kind == HealthKind.sleepSession), isTrue);
    expect(hc.any((r) => r.kind == HealthKind.hrvRmssd), isTrue);
    final spo2 = hc.firstWhere((r) => r.kind == HealthKind.spo2).value;
    expect(spo2, greaterThan(90));
  });
}
