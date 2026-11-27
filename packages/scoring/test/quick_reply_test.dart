import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final threshold = sessionTemplate('threshold_run');
  final easy = sessionTemplate('easy_run');

  group('short on time', () {
    test('intervals keep fewer reps and fit the time', () {
      final o = quickReplyOffer(
        threshold,
        QuickReply.shortOnTime,
        minutes: 30,
      )!;
      expect(o.to.minutes, lessThanOrEqualTo(threshold.minutes));
      expect(repCount(o.to)!, lessThan(repCount(threshold)!));
      expect(repCount(o.to)!, greaterThanOrEqualTo(2));
      expect(o.headline, 'Keep the quality, cut the extras.');
    });

    test('an easy session just gets shorter', () {
      final o = quickReplyOffer(easy, QuickReply.shortOnTime, minutes: 20)!;
      expect(o.to.minutes, lessThanOrEqualTo(25));
      expect(o.headline, 'Same session, shorter.');
    });

    test('nothing to do when the plan already fits', () {
      expect(
        quickReplyOffer(easy, QuickReply.shortOnTime, minutes: 60),
        isNull,
      );
    });
  });

  group('feeling flat', () {
    test('a hard day becomes easy and the hard session waits', () {
      final o = quickReplyOffer(threshold, QuickReply.feelingFlat)!;
      expect(o.to.isHard, isFalse);
      expect(o.to.minutes, lessThanOrEqualTo(45));
      expect(o.why, contains('back on a better morning'));
    });

    test('an easy day gets shorter', () {
      final o = quickReplyOffer(easy, QuickReply.feelingFlat)!;
      expect(o.to.minutes, lessThan(easy.minutes));
    });
  });

  group('up for more', () {
    test('only on a go day from 67', () {
      expect(
        quickReplyOffer(threshold, QuickReply.upForMore, recovery: 60),
        isNull,
      );
      expect(
        quickReplyOffer(
          threshold,
          QuickReply.upForMore,
          recovery: 80,
          state: DayState.easeOff,
        ),
        isNull,
      );
    });

    test('intervals get one more rep at the same pace', () {
      final o = quickReplyOffer(
        threshold,
        QuickReply.upForMore,
        recovery: 80,
        state: DayState.go,
        maxMinutes: 120,
      )!;
      expect(repCount(o.to), repCount(threshold)! + 1);
      expect(o.why, contains('${repCount(threshold)! + 1} reps'));
    });

    test('a steady session gets longer', () {
      final o = quickReplyOffer(
        easy,
        QuickReply.upForMore,
        recovery: 80,
        state: DayState.go,
        maxMinutes: 120,
      )!;
      expect(o.to.minutes, greaterThan(easy.minutes));
    });
  });

  test('rest days have no replies', () {
    for (final r in QuickReply.values) {
      expect(
        quickReplyOffer(
          sessionTemplate('rest'),
          r,
          recovery: 90,
          state: DayState.go,
        ),
        isNull,
      );
    }
  });
}
