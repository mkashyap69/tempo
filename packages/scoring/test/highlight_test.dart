import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 10, 22); // a Thursday

  group('triggers', () {
    test('nothing notable, nothing to say', () {
      expect(highlightCandidates(const HighlightFacts()), isEmpty);
    });

    test('each threshold, just under and at', () {
      List<HighlightKind> kinds(HighlightFacts f) => [
        for (final h in highlightCandidates(f)) h.kind,
      ];
      expect(kinds(const HighlightFacts(debtHours: 1.9)), isEmpty);
      expect(kinds(const HighlightFacts(debtHours: 2)), [
        HighlightKind.sleepDebt,
      ]);
      expect(kinds(const HighlightFacts(sri: 66)), isEmpty);
      expect(kinds(const HighlightFacts(sri: 60)), [HighlightKind.regularity]);
      expect(kinds(const HighlightFacts(jetlagMinutes: 59)), isEmpty);
      expect(kinds(const HighlightFacts(jetlagMinutes: -70)), [
        HighlightKind.socialJetlag,
      ]);
      expect(kinds(const HighlightFacts(stillMinutes: 119)), isEmpty);
      expect(kinds(const HighlightFacts(stillMinutes: 130)), [
        HighlightKind.stillStretch,
      ]);
      expect(kinds(const HighlightFacts(ageDelta: .2)), isEmpty);
      expect(kinds(const HighlightFacts(ageDelta: -.4)), [
        HighlightKind.tempoAge,
      ]);
      expect(kinds(const HighlightFacts(strengthGapDays: 9)), isEmpty);
      expect(kinds(const HighlightFacts(strengthGapDays: 12)), [
        HighlightKind.strength,
      ]);
      expect(kinds(const HighlightFacts(load: LoadStatus.building)), isEmpty);
      expect(kinds(const HighlightFacts(load: LoadStatus.detraining)), [
        HighlightKind.load,
      ]);
    });

    test('brisk waits for Thursday and a real gap', () {
      List<Highlight> b(double avg, int wd) =>
          highlightCandidates(HighlightFacts(briskAvg: avg, weekday: wd));
      expect(b(10, 2), isEmpty);
      expect(b(25, 4), isEmpty);
      expect(b(10, 4).single.kind, HighlightKind.brisk);
    });

    test('a record beats only the last 90 nights', () {
      expect(
        highlightCandidates(const HighlightFacts(rhr: 50, rhrLow: 51))
            .single
            .key,
        'pb:rhr',
      );
      expect(
        highlightCandidates(const HighlightFacts(rhr: 51, rhrLow: 51)),
        isEmpty,
      );
      expect(
        highlightCandidates(const HighlightFacts(hrv: 80, hrvHigh: 75))
            .single
            .key,
        'pb:hrv',
      );
    });

    test('the text uses your own numbers', () {
      final h = highlightCandidates(
        const HighlightFacts(debtHours: 2.25, stillMinutes: 130),
      );
      expect(h.first.title, '2 h 15 m of sleep debt');
      expect(h.last.title, 'Still for 2 h 10 m');
    });

    test('highest priority first', () {
      final h = highlightCandidates(
        const HighlightFacts(
          bodyOff: ['Resting HR'],
          debtHours: 3,
          sri: 50,
          strengthGapDays: 14,
        ),
      );
      expect(h.map((x) => x.kind), [
        HighlightKind.bodySignal,
        HighlightKind.sleepDebt,
        HighlightKind.regularity,
        HighlightKind.strength,
      ]);
    });
  });

  group('pick', () {
    final cands = highlightCandidates(
      const HighlightFacts(debtHours: 3, sri: 50, stillMinutes: 150),
    );

    test('the top one when nothing was shown', () {
      expect(pickHighlight(cands, [], today)!.kind, HighlightKind.sleepDebt);
    });

    test('none on a rest day or a Monday', () {
      expect(pickHighlight(cands, [], today, restDay: true), isNull);
      expect(pickHighlight(cands, [], today, monday: true), isNull);
    });

    test('the day keeps its card', () {
      final shown = [(kind: 'regularity', key: 'regularity', day: today)];
      expect(
        pickHighlight(cands, shown, today)!.kind,
        HighlightKind.regularity,
      );
    });

    test('a kind in its cool-down gives way to the next', () {
      final shown = [
        (
          kind: 'sleepDebt',
          key: 'debt',
          day: today.subtract(const Duration(days: 2)),
        ),
      ];
      expect(
        pickHighlight(cands, shown, today)!.kind,
        HighlightKind.regularity,
      );
      final later = [
        (
          kind: 'sleepDebt',
          key: 'debt',
          day: today.subtract(const Duration(days: 3)),
        ),
      ];
      expect(pickHighlight(cands, later, today)!.kind, HighlightKind.sleepDebt);
    });

    test('one journal behaviour waits three weeks', () {
      final c = highlightCandidates(
        const HighlightFacts(
          impact: (
            key: 'late_meal',
            name: 'Late meal',
            effect: '−6 points on Recovery',
            hurts: true,
          ),
        ),
      );
      final shown = [
        (
          kind: 'journalImpact',
          key: 'journal:late_meal',
          day: today.subtract(const Duration(days: 10)),
        ),
      ];
      expect(pickHighlight(c, shown, today), isNull);
      expect(
        pickHighlight(c, [
          (
            kind: 'journalImpact',
            key: 'journal:late_meal',
            day: today.subtract(const Duration(days: 21)),
          ),
        ], today),
        isNotNull,
      );
    });

    test('everything cooling down shows nothing', () {
      final shown = [
        for (final c in cands)
          (
            kind: c.kind.name,
            key: c.key,
            day: today.subtract(const Duration(days: 1)),
          ),
      ];
      expect(pickHighlight(cands, shown, today), isNull);
    });
  });
}
