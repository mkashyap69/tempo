import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// The call input for a recovery, with state and target derived the way the
/// app does (dayState → readiness → targetForState).
CallInput input(
  double? r, {
  RhrFlag rhr = RhrFlag.none,
  bool short = false,
  LoadStatus load = LoadStatus.maintaining,
  int? sinceHard,
  bool calibrating = false,
  bool stale = false,
}) {
  final base = dayState(
    recovery: r,
    calibrating: calibrating,
    load: load,
    daysSinceHard: sinceHard,
  );
  final state = readiness(
    base,
    rhr: rhr,
    shortNight: short,
    overreaching: load == LoadStatus.overreaching,
  );
  final target = targetForState(strainTarget(recovery: r, load: load), state);
  return CallInput(
    recovery: r,
    calibrating: calibrating,
    stale: stale,
    nights: calibrating ? 5 : 30,
    state: state,
    rhr: rhr,
    shortNight: short,
    load: load,
    daysSinceHard: sinceHard,
    target: target,
    bedtime: '22:45',
    planTitle: 'Tempo run',
    planHard: true,
  );
}

void main() {
  group('callWord', () {
    test('no word while there is nothing to decide on', () {
      expect(callWord(input(null)), isNull);
      expect(callWord(input(70, calibrating: true)), isNull);
      expect(callWord(input(80, stale: true)), isNull);
      expect(callShift(input(null)), isNull);
    });

    test('high recovery, fresh legs and a known load is Push', () {
      expect(callWord(input(90, sinceHard: 4)), CallWord.push);
      expect(callWord(input(90)), CallWord.push);
    });

    test('Push needs a load Tempo has learned and three easy days', () {
      expect(callWord(input(90, load: LoadStatus.learning)), CallWord.build);
      expect(callWord(input(90, sinceHard: 2)), CallWord.build);
    });

    test('a go day under 85 is Build', () {
      expect(callWord(input(78, sinceHard: 2)), CallWord.build);
      expect(callWord(input(67)), CallWord.build);
    });

    test('a short night or raised resting HR turns a go day into Ease', () {
      expect(callWord(input(80, short: true)), CallWord.ease);
      expect(callWord(input(80, rhr: RhrFlag.elevated)), CallWord.ease);
      expect(callWord(input(80, sinceHard: 1)), CallWord.ease);
    });

    test('a middling recovery with no other reason is Steady', () {
      expect(callWord(input(58)), CallWord.steady);
    });

    test('a low recovery on an ease-off day is Ease, 33 or less is Rest', () {
      expect(callWord(input(45)), CallWord.ease);
      expect(callWord(input(33)), CallWord.rest);
    });

    test('night signals and overreaching outrank a green number', () {
      expect(callWord(input(80, rhr: RhrFlag.illness)), CallWord.rest);
      expect(callWord(input(45, load: LoadStatus.overreaching)), CallWord.rest);
    });

    test('labels', () {
      expect(CallWord.values.map(callWordLabel), [
        'Push',
        'Build',
        'Steady',
        'Ease',
        'Rest',
      ]);
    });
  });

  group('callShift', () {
    test('names the nearest threshold for each word', () {
      expect(callShift(input(90))!, contains('Build'));
      expect(callShift(input(78, sinceHard: 3))!, contains('Push'));
      expect(callShift(input(58))!, contains('Build'));
      expect(callShift(input(33))!, contains('above 33'));
    });

    test('an ease day says what brings Build back', () {
      expect(callShift(input(80, sinceHard: 1))!, contains('last hard'));
      expect(callShift(input(80, short: true))!, contains('full night'));
      expect(callShift(input(45))!, contains('Steady'));
    });

    test('illness is lifted by the night heart rate', () {
      expect(
        callShift(input(80, rhr: RhrFlag.illness))!,
        contains('Night heart rate'),
      );
    });
  });
}
