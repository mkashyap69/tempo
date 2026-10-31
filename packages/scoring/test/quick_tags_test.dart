import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  Map<String, (bool, double?)> m(List<QuickEntry> es) => {
    for (final e in es) e.key: (e.value, e.amount),
  };
  const bed = 23 * 60;

  test('coffee: last caffeine time, late after 14:00', () {
    expect(m(quickTagEntries(QuickTag.coffee, 9 * 60, bedtime: bed)), {
      'last_caffeine': (true, 540.0),
    });
    final late = m(
      quickTagEntries(
        QuickTag.coffee,
        16 * 60 + 30,
        amounts: {'last_caffeine': 540},
        bedtime: bed,
      ),
    );
    expect(late['last_caffeine'], (true, 990.0));
    expect(late['caffeine_late'], (true, null));
    // An earlier coffee logged after a later one keeps the later time.
    expect(
      m(
        quickTagEntries(
          QuickTag.coffee,
          600,
          amounts: {'last_caffeine': 990},
          bedtime: bed,
        ),
      )['last_caffeine'],
      (true, 990.0),
    );
  });

  test('meal: first and last meal, late within 2 h of bed', () {
    final lunch = m(
      quickTagEntries(
        QuickTag.meal,
        13 * 60,
        amounts: {'first_meal': 480},
        bedtime: bed,
      ),
    );
    expect(lunch['first_meal'], (true, 480.0));
    expect(lunch['last_meal'], (true, 780.0));
    expect(lunch.containsKey('late_meal'), isFalse);
    final late = m(quickTagEntries(QuickTag.meal, 21 * 60 + 30, bedtime: bed));
    expect(late['late_meal'], (true, null));
    // Bedtime after midnight: a 23:30 meal is 60 min before a 00:30 bed.
    expect(
      m(quickTagEntries(QuickTag.meal, 23 * 60 + 30, bedtime: 30))
          .containsKey('late_meal'),
      isTrue,
    );
  });

  test('alcohol counts drinks; daylight is a yes', () {
    expect(
      m(
        quickTagEntries(
          QuickTag.alcohol,
          20 * 60,
          amounts: {'drinks': 1},
          bedtime: bed,
        ),
      ),
      {'alcohol': (true, null), 'drinks': (true, 2.0)},
    );
    expect(m(quickTagEntries(QuickTag.daylight, 480, bedtime: bed)), {
      'daylight': (true, null),
    });
  });
}
