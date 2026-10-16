import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('catalogue keys are unique and the old tags are kept', () {
    final keys = [for (final e in journalCatalog) e.key];
    expect(keys.toSet().length, keys.length);
    expect(keys, containsAll(defaultJournalKeys));
    expect(journalCatalog.length, greaterThanOrEqualTo(60));
    expect(keys.contains(checkinTag), isFalse);
  });

  test('custom keys are slugs', () {
    expect(customKey('Hot yoga!'), 'custom_hot_yoga');
    expect(customKey('  '), 'custom_entry');
    expect(customEntry('custom_x', 'X').group, EntryGroup.lifestyle);
  });

  test('minutes after noon put late bedtimes after early ones', () {
    expect(minutesAfterNoon(DateTime(2026, 1, 1, 23)), 11 * 60);
    expect(minutesAfterNoon(DateTime(2026, 1, 2, 0, 30)), 12 * 60 + 30);
    expect(minutesAfterNoon(DateTime(2026, 1, 1, 12)), 0);
  });

  group('autoEntries', () {
    test('thresholds', () {
      final a = autoEntries(
        AutoFacts(
          steps: 8000,
          briskMinutes: 29,
          zone2Minutes: 30,
          strengthDone: true,
          lastWorkoutEnd: DateTime(2026, 1, 1, 20),
          sleepStart: DateTime(2026, 1, 1, 22, 59),
          napMinutes: 20,
          bedMinute: 12 * 60,
          usualBedMinute: 11 * 60,
          strain: 13.9,
        ),
      );
      expect(a, {
        'auto_steps': true,
        'auto_brisk': false,
        'auto_zone2': true,
        'auto_strength': true,
        'auto_late_workout': true,
        'auto_nap': true,
        'auto_late_bed': true,
        'auto_high_strain': false,
      });
    });

    test('unknown data is left out, not "no"', () {
      expect(autoEntries(const AutoFacts()), {'auto_strength': false});
    });

    test('a workout 3 h or more before sleep is not late', () {
      final a = autoEntries(
        AutoFacts(
          lastWorkoutEnd: DateTime(2026, 1, 1, 19),
          sleepStart: DateTime(2026, 1, 1, 22),
        ),
      );
      expect(a['auto_late_workout'], isFalse);
    });
  });

  test('overnight fast', () {
    expect(overnightFastHours(20 * 60, 8 * 60), 12);
    expect(overnightFastHours(null, 8 * 60), isNull);
    expect(overnightFastHours(23 * 60, 12 * 60 + 30), 13.5);
  });
}
