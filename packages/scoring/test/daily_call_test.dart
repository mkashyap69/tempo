import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// The call for a recovery and readiness, with today's target following the
/// state the way the app derives it.
DailyCall call(
  double r, {
  RhrFlag rhr = RhrFlag.none,
  bool short = false,
  LoadStatus load = LoadStatus.maintaining,
  int? sinceHard,
  bool plain = false,
  String? plan = 'Threshold intervals',
  bool hard = true,
}) {
  final base = dayState(recovery: r, load: load, daysSinceHard: sinceHard);
  final state = readiness(
    base,
    rhr: rhr,
    shortNight: short,
    overreaching: load == LoadStatus.overreaching,
  );
  final target = targetForState(strainTarget(recovery: r, load: load), state);
  return dailyCall(
    CallInput(
      recovery: r,
      state: state,
      rhr: rhr,
      shortNight: short,
      load: load,
      daysSinceHard: sinceHard,
      target: target,
      bedtime: '10:45pm',
      planTitle: plan,
      planHard: hard,
      plainWords: plain,
    ),
  );
}

void main() {
  group('targetForState', () {
    const t = StrainTarget(13, 16);
    test('rest caps at 8 whatever the recovery', () {
      final r = targetForState(t, DayState.rest);
      expect(r.cap, isTrue);
      expect(r.hi, 8);
    });
    test('ease off tops out at 13', () {
      final r = targetForState(t, DayState.easeOff);
      expect((r.lo, r.hi), (10, 13));
    });
    test('go and general are unchanged', () {
      expect(targetForState(t, DayState.go), same(t));
      const g = StrainTarget(10, 14, general: true);
      expect(targetForState(g, DayState.rest), same(g));
    });
    test('a lower ease-off target keeps its low end', () {
      final r = targetForState(const StrainTarget(8, 14), DayState.easeOff);
      expect((r.lo, r.hi), (8, 13));
    });
  });

  group('state wins over the number', () {
    test('illness on a green morning is a rest day, with a note', () {
      final c = call(72, rhr: RhrFlag.illness);
      expect(c.reason, CallReason.illness);
      expect(c.tone, CallTone.low);
      expect(c.lead, 'Take it easy today.');
      expect(c.text, isNot(contains('primed')));
      expect(c.note, contains('72%'));
    });
    test('overreaching with a short night is rest, and says why', () {
      final c = call(70, load: LoadStatus.overreaching, short: true);
      expect(c.reason, CallReason.overreaching);
      expect(c.rest, contains('last night was short'));
    });
    test('overreaching under 50 says the recovery, not a made-up sign', () {
      final c = call(45, load: LoadStatus.overreaching);
      expect(c.reason, CallReason.overreaching);
      expect(c.rest, contains('recovery is 45%'));
    });
    test('low recovery is a rest day with the cap', () {
      final c = call(25);
      expect(c.reason, CallReason.lowRecovery);
      expect(c.rest, contains('under 8'));
      expect(c.rest, contains('10:45pm'));
    });
  });

  group('ease off names the cause', () {
    final cases = {
      CallReason.highRhr: call(80, rhr: RhrFlag.elevated),
      CallReason.shortNight: call(80, short: true),
      CallReason.recentHard: call(80, sinceHard: 1),
      CallReason.loadHot: call(70, load: LoadStatus.overreaching),
    };
    final words = {
      CallReason.highRhr: 'resting heart rate is above usual',
      CallReason.shortNight: 'last night was short',
      CallReason.recentHard: 'yesterday was hard',
      CallReason.loadHot: 'load is running hot',
    };
    for (final e in cases.entries) {
      test(e.key.name, () {
        expect(e.value.reason, e.key);
        expect(e.value.tone, CallTone.mid);
        expect(e.value.rest, contains(words[e.key]));
        expect(e.value.rest, contains('10–13'));
      });
    }
    test('a hard session earlier today', () {
      expect(call(80, sinceHard: 0).rest, contains('already trained hard'));
    });
    test('a yellow morning is steady', () {
      final c = call(55);
      expect(c.reason, CallReason.steady);
      expect(c.tone, CallTone.mid);
    });
    test('under 50 keeps strain under the top', () {
      expect(call(42).rest, contains('under 12'));
    });
  });

  group('go', () {
    test('primed names a hard plan', () {
      final c = call(85);
      expect(c.reason, CallReason.primed);
      expect(c.tone, CallTone.good);
      expect(c.rest, contains('threshold intervals'));
    });
    test('an easy plan is a solid session', () {
      expect(
        call(85, plan: 'Easy run', hard: false).rest,
        contains('a solid session'),
      );
    });
  });

  group('plain words', () {
    test('no strain numbers for wellbeing', () {
      for (final c in [
        call(85, plain: true),
        call(55, plain: true),
        call(80, short: true, plain: true),
        call(25, plain: true),
      ]) {
        expect(c.text, isNot(contains('strain')), reason: c.text);
        expect(c.lead, isNot(contains('%')));
      }
    });
  });

  group('before scores', () {
    const t = StrainTarget(8, 12, general: true);
    test('no data', () {
      final c = dailyCall(const CallInput(noData: true, target: t));
      expect(c.reason, CallReason.noData);
      expect(c.lead, 'Connect your band');
    });
    test('stale beats everything after it', () {
      final c = dailyCall(
        const CallInput(stale: true, recovery: 90, target: t, health: true),
      );
      expect(c.reason, CallReason.stale);
      expect(c.rest, contains('Health'));
    });
    test('calibrating counts nights', () {
      final c = dailyCall(
        const CallInput(calibrating: true, nights: 4, target: t),
      );
      expect(c.lead, 'Night 4 of 14.');
    });
    test('waiting for last night', () {
      final c = dailyCall(
        const CallInput(state: DayState.go, target: StrainTarget(13, 16)),
      );
      expect(c.reason, CallReason.waiting);
    });
  });

  test('reasonShort covers the notification reasons', () {
    expect(reasonShort(CallReason.illness), 'night HR high');
    expect(reasonShort(CallReason.primed), '');
  });

  group('dayPhase', () {
    DayPhase at(
      int h, {
      int bed = 22 * 60 + 45,
      bool done = false,
      bool rest = false,
    }) => dayPhase(
      nowMinute: h * 60,
      bedtimeMinute: bed,
      sessionDone: done,
      restDay: rest,
    );
    test('the clock', () {
      expect(at(7), DayPhase.morning);
      expect(at(14), DayPhase.day);
      expect(at(21), DayPhase.evening);
    });
    test('a finished session until the evening', () {
      expect(at(19, done: true), DayPhase.done);
      expect(at(21, done: true), DayPhase.evening);
    });
    test('a bedtime after midnight', () {
      expect(at(21, bed: 30), DayPhase.day);
      expect(at(23, bed: 30), DayPhase.evening);
    });
    test('rest and the first nights have their own', () {
      expect(at(21, rest: true), DayPhase.rest);
      expect(
        dayPhase(nowMinute: 600, bedtimeMinute: 1350, calibrating: true),
        DayPhase.newcomer,
      );
    });
  });
}
