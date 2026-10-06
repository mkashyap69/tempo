import 'package:backtest/health_export.dart';
import 'package:health_source/health_source.dart';
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

  test('reads matching HR, sleep and HRV, ignores other sources', () async {
    const xml = [
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Mi Fit" unit="count/min" startDate="2020-01-01 08:00:10 +0000" endDate="2020-01-01 08:00:10 +0000" value="70"/>',
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Mi Fit" unit="count/min" startDate="2020-01-01 08:00:40 +0000" endDate="2020-01-01 08:00:40 +0000" value="80"/>',
      '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="2020-01-01 08:01:00 +0000" endDate="2020-01-01 08:01:00 +0000" value="200"/>',
      '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Mi Fit" startDate="2020-01-01 08:02:00 +0000" endDate="2020-01-01 08:04:00 +0000" value="HKCategoryValueSleepAnalysisAsleepDeep"/>',
      '<Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Mi Fit" unit="ms" startDate="2020-01-01 08:03:00 +0000" endDate="2020-01-01 08:03:00 +0000" value="42"/>',
    ];
    final d = await readExport(
      Stream.fromIterable(xml),
      RegExp('Mi Fit'),
      params: const GridParams(maxHrGapMinutes: 2, holdMinutes: 2),
    );
    final from = DateTime.utc(2020, 1, 1, 8);
    final m = scoringMinutes(
      d.grid.minutes(from, from.add(const Duration(minutes: 5))),
    ).minutes;
    expect(m.map((x) => x.hr), [75, 75, 75, null, null]);
    expect(m.map((x) => x.stage), [
      Stage.wake,
      Stage.wake,
      Stage.deep,
      Stage.deep,
      Stage.unknown,
    ]);
    expect(d.vitals.single.kind, HealthKind.hrvSdnn);
  });

  test('sleep values map to kinds; in bed is a container', () {
    expect(
      sleepKind('HKCategoryValueSleepAnalysisInBed'),
      HealthKind.sleepInBed,
    );
    expect(
      sleepKind('HKCategoryValueSleepAnalysisAsleepCore'),
      HealthKind.sleepLight,
    );
    expect(sleepKind('nope'), isNull);
  });
}
