import 'package:backtest/health_export.dart';
import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('parses dates with offset', () {
    expect(
      parseHealthDate('2020-01-01 08:00:00 +0530'),
      DateTime.utc(2020, 1, 1, 2, 30),
    );
    expect(
      parseHealthDate('2020-01-01 08:00:00 -0100'),
      DateTime.utc(2020, 1, 1, 9),
    );
  });

  test('reads matching HR and sleep, ignores other sources', () async {
    const xml = [
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Mi Fit" unit="count/min" startDate="2020-01-01 08:00:10 +0000" endDate="2020-01-01 08:00:10 +0000" value="70"/>',
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Mi Fit" unit="count/min" startDate="2020-01-01 08:00:40 +0000" endDate="2020-01-01 08:00:40 +0000" value="80"/>',
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="2020-01-01 08:01:00 +0000" endDate="2020-01-01 08:01:00 +0000" value="200"/>',
      '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Mi Fit" startDate="2020-01-01 08:02:00 +0000" endDate="2020-01-01 08:04:00 +0000" value="HKCategoryValueSleepAnalysisAsleepDeep"/>',
    ];
    final g = await readExport(Stream.fromIterable(xml), RegExp('Mi Fit'));
    final from = DateTime.utc(2020, 1, 1, 8);
    final m = g.range(
      from,
      from.add(const Duration(minutes: 5)),
      fillMinutes: 2,
    );
    expect(m.map((x) => x.hr), [75, 75, 75, null, null]);
    expect(m.map((x) => x.stage), [
      Stage.unknown,
      Stage.unknown,
      Stage.deep,
      Stage.deep,
      Stage.unknown,
    ]);
  });
}
