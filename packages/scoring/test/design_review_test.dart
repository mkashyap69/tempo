import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  group('feelResponse', () {
    test('learning: notes the rating without a score', () {
      expect(feelResponse(4, null), startsWith('Noted: good.'));
    });

    test('agreement in each band', () {
      expect(feelResponse(5, 80), contains('recovery agrees at 80%'));
      expect(feelResponse(3, 50), contains('says the same at 50%'));
      expect(feelResponse(1, 20), contains('Take it easy today'));
    });

    test('felt better than recovery reads', () {
      expect(feelResponse(5, 25), contains('only 25%'));
      expect(feelResponse(4, 50), contains('says moderate'));
    });

    test('felt worse than recovery reads', () {
      expect(feelResponse(1, 85), contains('recovered well (85%)'));
      expect(feelResponse(2, 50), contains('middling at 50%'));
    });

    test('out-of-range ratings are clamped', () {
      expect(feelResponse(9, null), startsWith('Noted: great.'));
    });
  });

  group('halfway win', () {
    test('marks the middle week of a block of 4+ weeks', () {
      expect(halfwayWeek(12), 6);
      expect(halfwayWeek(4), 2);
      expect(halfwayWeek(3), isNull);
      final w = pickWin(
        const WinInput(blockWeek: 6, blockWeeks: 12, goal: '10K'),
      )!;
      expect(w.kind, WinKind.halfway);
      expect(w.title, 'Halfway to 10K');
      expect(w.body, startsWith('Week 7 of 12.'));
    });

    test('not in other weeks, nor once celebrated this week', () {
      expect(pickWin(const WinInput(blockWeek: 5, blockWeeks: 12)), isNull);
      expect(
        pickWin(
          const WinInput(
            blockWeek: 6,
            blockWeeks: 12,
            recentWins: {WinKind.halfway},
          ),
        ),
        isNull,
      );
    });

    test('a 30-day best recovery outranks it', () {
      final w = pickWin(
        WinInput(
          recovery: 90,
          recoveryLast30: List.filled(20, 70.0),
          blockWeek: 6,
          blockWeeks: 12,
        ),
      )!;
      expect(w.kind, WinKind.recoveryBest);
    });
  });
}
