import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// [days] days of minutes: asleep from [bed] (minutes after midnight, may
/// be negative = evening before) for [hours], awake and worn otherwise.
List<Minute> days(
  int n, {
  int Function(int day) bed = _bed,
  double hours = 8,
  DateTime? from,
}) {
  final start = from ?? DateTime(2026, 9, 1);
  final out = <Minute>[];
  for (var d = 0; d < n; d++) {
    final midnight = DateTime(start.year, start.month, start.day + d);
    final a = bed(d), b = a + (hours * 60).round();
    for (var m = 0; m < 1440; m++) {
      // Minute m of day d, asleep when inside [a, b) of this day or the
      // spill of the previous night.
      final asleep =
          (m >= a && m < b) ||
          (m + 1440 >= bed(d + 1) && m + 1440 < bed(d + 1) + hours * 60) ||
          (a < 0 && m < b);
      out.add(
        Minute(
          midnight.add(Duration(minutes: m)),
          hr: asleep ? 52 : 70,
          stage: asleep ? Stage.light : Stage.wake,
        ),
      );
    }
  }
  return out;
}

int _bed(int _) => -60; // 23:00

void main() {
  group('sleep regularity', () {
    test('the same night every day is 100', () {
      expect(sleepRegularity(days(8)), closeTo(100, 1e-9));
    });

    test('bedtime moving by hours lowers it', () {
      final shifting = days(8, bed: (d) => d.isEven ? -60 : 120);
      final sri = sleepRegularity(shifting)!;
      expect(sri, lessThan(80));
      expect(regularityBand(sri), isNot(Regularity.regular));
    });

    test('unknown and unworn minutes do not count; too little is null', () {
      expect(sleepRegularity(days(3)), isNull);
      final gaps = [
        for (final m in days(8))
          m.ts.hour >= 12 && m.ts.hour < 18
              ? Minute(m.ts, stage: Stage.unknown, offWrist: true)
              : m,
      ];
      expect(sleepRegularity(gaps), closeTo(100, 1e-9));
    });

    test('bands', () {
      expect(regularityBand(85), Regularity.regular);
      expect(regularityBand(70), Regularity.fair);
      expect(regularityBand(40), Regularity.irregular);
    });
  });

  group('social jetlag', () {
    NightSpan night(DateTime morning, int bedMin, int wakeMin) => (
      start: DateTime(
        morning.year,
        morning.month,
        morning.day,
      ).add(Duration(minutes: bedMin)),
      end: DateTime(
        morning.year,
        morning.month,
        morning.day,
      ).add(Duration(minutes: wakeMin)),
    );

    test('later weekend sleep across midnight', () {
      // Mon 2026-09-07 … Sun 2026-09-13.
      final nights = [
        for (var d = 7; d <= 11; d++)
          night(DateTime(2026, 9, d), -60, 7 * 60), // 23:00–07:00, mid 03:00
        night(DateTime(2026, 9, 12), 60, 9 * 60), // 01:00–09:00, mid 05:00
        night(DateTime(2026, 9, 13), 30, 8 * 60 + 30), // mid 04:30
      ];
      final j = socialJetlag(nights)!;
      expect(j.workMid, 180);
      expect(j.freeMid, 285); // median of two
      expect(j.minutes, closeTo(105, 1));
      expect(jetlagBand(j.minutes), JetlagBand.large);
    });

    test('mid-sleep before midnight stays continuous', () {
      final nights = [
        for (var d = 7; d <= 11; d++)
          night(DateTime(2026, 9, d), -4 * 60, 2 * 60), // 20:00–02:00, 23:00
        night(DateTime(2026, 9, 12), -2 * 60, 4 * 60), // 22:00–04:00, 01:00
        night(DateTime(2026, 9, 13), -2 * 60, 4 * 60),
      ];
      final j = socialJetlag(nights)!;
      expect(j.workMid, -60);
      expect(j.freeMid, 60);
      expect(j.minutes, 120);
    });

    test('needs free and work nights', () {
      expect(socialJetlag([night(DateTime(2026, 9, 12), -60, 420)]), isNull);
      expect(jetlagBand(-20), JetlagBand.small);
      expect(jetlagBand(45), JetlagBand.moderate);
    });
  });

  group('body signals', () {
    final steady = [for (var i = 0; i < 20; i++) 55.0 + (i % 3) - 1];
    SignalInput rhr(double? v, {List<double>? h}) => SignalInput(
      key: 'rhr',
      value: v,
      history: h ?? steady,
      higherIsWorse: true,
      minDelta: 3,
    );

    test('learning, normal, off', () {
      expect(
        bodySignals([
          rhr(60, h: [55, 56]),
        ]).level,
        BodyLevel.learning,
      );
      expect(bodySignals([rhr(56)]).level, BodyLevel.normal);
      final up = bodySignals([rhr(61)]);
      expect(up.level, BodyLevel.watch);
      expect(up.off.single.key, 'rhr');
      expect(up.off.single.delta, closeTo(6, .1));
    });

    test('better than usual is never off', () {
      expect(bodySignals([rhr(45)]).level, BodyLevel.normal);
    });

    test('a flat baseline needs the minimum change', () {
      final flat = [for (var i = 0; i < 20; i++) 55.0];
      expect(bodySignals([rhr(57, h: flat)]).level, BodyLevel.normal);
      expect(bodySignals([rhr(58, h: flat)]).level, BodyLevel.watch);
    });

    test('two signals off means rest; missing ones are skipped', () {
      final resp = SignalInput(
        key: 'resp',
        value: 17.5,
        history: [for (var i = 0; i < 20; i++) 14.0 + (i % 2) * .4],
        higherIsWorse: true,
        minDelta: 1,
      );
      final spo2 = SignalInput(
        key: 'spo2',
        value: null,
        history: [for (var i = 0; i < 20; i++) 96.0],
        higherIsWorse: false,
        minDelta: 1.5,
      );
      final b = bodySignals([rhr(62), resp, spo2]);
      expect(b.level, BodyLevel.rest);
      expect(
        b.readings.firstWhere((r) => r.key == 'spo2').state,
        SignalState.missing,
      );
    });

    test('lower-is-worse signals', () {
      final spo2 = SignalInput(
        key: 'spo2',
        value: 92,
        history: [for (var i = 0; i < 20; i++) 96.0 + (i % 2)],
        higherIsWorse: false,
        minDelta: 1.5,
      );
      expect(bodySignals([spo2]).level, BodyLevel.watch);
    });
  });

  group('movement', () {
    final t0 = DateTime(2026, 9, 1, 9);
    List<Minute> mins(List<(int steps, int? hr)> xs) => [
      for (final (i, x) in xs.indexed)
        Minute(
          t0.add(Duration(minutes: i)),
          steps: x.$1,
          hr: x.$2,
          stage: Stage.wake,
        ),
    ];

    test('brisk minutes count 100+ steps', () {
      expect(
        briskMinutes(mins([(99, 90), (100, 100), (130, 110), (0, 70)])),
        2,
      );
    });

    test('longest still stretch', () {
      final xs = mins([
        for (var i = 0; i < 30; i++) (0, 65),
        (40, 80), // a walk to the kitchen breaks it
        for (var i = 0; i < 50; i++) (5, 66),
        for (var i = 0; i < 10; i++) (0, 120), // cycling: no steps, high HR
      ]);
      final s = longestStill(xs, hrRest: 55)!;
      expect(s.minutes, 50);
      expect(s.start, t0.add(const Duration(minutes: 31)));
    });

    test('workouts and sleep end a stretch; phone-only is null', () {
      final xs = mins([for (var i = 0; i < 60; i++) (0, 65)]);
      final s = longestStill(
        xs,
        hrRest: 55,
        busy: [
          (
            t0.add(const Duration(minutes: 20)),
            t0.add(const Duration(minutes: 40)),
          ),
        ],
      )!;
      expect(s.minutes, 20);
      expect(
        longestStill(
          mins([for (var i = 0; i < 60; i++) (0, null)]),
          hrRest: 55,
        ),
        isNull,
      );
    });
  });

  group('recovery heart rate', () {
    final end = DateTime(2026, 9, 1, 18, 40);
    List<Minute> around(List<int?> hrs) => [
      for (final (i, h) in hrs.indexed)
        Minute(end.add(Duration(minutes: i - 3)), hr: h),
    ];

    test('peak of the last 3 minutes minus 2 minutes after', () {
      // −3 −2 −1 | 0 +1 +2
      expect(
        recoveryDrop(around([160, 168, 165, 150, 140, 132]), end, hrMax: 190),
        36,
      );
    });

    test('too easy or missing reading is null', () {
      expect(
        recoveryDrop(around([110, 112, 115, 100, 95, 90]), end, hrMax: 190),
        isNull,
      );
      expect(
        recoveryDrop(around([160, 168, 165, 150, 140, null]), end, hrMax: 190),
        isNull,
      );
    });
  });
}
