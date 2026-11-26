import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

Impact imp(String key, double effect, ImpactConfidence c) => Impact(
  key: key,
  outcome: Outcome.recovery,
  effect: effect,
  low: effect - 1,
  high: effect + 1,
  nYes: 10,
  nNo: 20,
  confidence: c,
);

void main() {
  final list = [
    imp('alcohol', -11, ImpactConfidence.high),
    imp('late_meal', -4, ImpactConfidence.moderate),
    imp('evening_walk', 5, ImpactConfidence.low),
    imp('reading', 1, ImpactConfidence.high), // under the 2-point minimum
    imp('sauna', 9, ImpactConfidence.none), // not sure enough
    imp('caffeine', -6, ImpactConfidence.notEnough),
  ];

  test(
    'biggest sure effects first, helping habits done, hurting ones skipped',
    () {
      final s = experimentSuggestions(list);
      expect(s.map((e) => e.key), ['alcohol', 'evening_walk', 'late_meal']);
      expect(s[0].doIt, isFalse);
      expect(s[1].doIt, isTrue);
      expect(s[2].doIt, isFalse);
    },
  );

  test('leaves out what is running or already tried, and caps the list', () {
    final s = experimentSuggestions(list, exclude: {'alcohol'}, max: 1);
    expect(s.single.key, 'evening_walk');
  });

  test('nothing to suggest without clear effects', () {
    expect(
      experimentSuggestions([imp('reading', 1, ImpactConfidence.high)]),
      isEmpty,
    );
  });
}
