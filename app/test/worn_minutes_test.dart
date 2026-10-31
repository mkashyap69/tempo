import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;
import 'package:tempo/src/core/stages.dart';

void main() {
  st.MinuteSample row(int kind, {int? hr, int steps = 0}) => st.MinuteSample(
    ts: st.toTs(DateTime(2026, 10, 31, 10, 25)),
    steps: steps,
    intensity: 10,
    kind: kind,
    hr: hr,
  );

  test('an unworn minute keeps no heart rate and no steps', () {
    // 5–20 Oct: 0xf3, 0x83, 0x73, 0x03 are the band's not-worn codes.
    for (final kind in [0xf3, 0x83, 0x73, 0x03]) {
      final m = minuteOf(row(kind, hr: 88, steps: 40));
      expect(m.hr, isNull, reason: '0x${kind.toRadixString(16)}');
      expect(m.steps, 0);
      expect(m.offWrist, isTrue);
      expect(m.stage, sc.Stage.unknown);
    }
    // Worn minutes are untouched.
    final w = minuteOf(row(0x50, hr: 72, steps: 5));
    expect((w.hr, w.steps, w.offWrist), (72, 5, false));
  });

  test('a heart rate no body makes is dropped, steps stay', () {
    final m = minuteOf(row(0x01, hr: 227, steps: 95));
    expect(m.hr, isNull);
    expect(m.steps, 95);
    expect(worn(row(0x50, hr: 20)).hr, isNull);
    expect(worn(row(0x50, hr: 190)).hr, 190);
    // The raw row is never changed.
    final raw = row(0xf3, hr: 88, steps: 40);
    worn(raw);
    expect(raw.hr, 88);
    expect(raw.copyWith(hr: const Value(null)).hr, isNull);
  });
}
