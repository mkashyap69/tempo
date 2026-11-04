import 'package:sync/sync.dart';
import 'package:test/test.dart';

Object byDay(Row r) => r['day']!;

void main() {
  group('append-only', () {
    test('inserts what is missing and never changes a stored row', () {
      final p = planMerge(
        SyncClass.appendOnly,
        local: {
          'a': {'day': 'a', 'v': 1},
        },
        incoming: [
          {'day': 'a', 'v': 2},
          {'day': 'b', 'v': 3},
        ],
        keyOf: byDay,
      );
      expect(p.insert, [
        {'day': 'b', 'v': 3},
      ]);
      expect(p.replace, isEmpty);
    });
  });

  group('user-entered', () {
    test('the later edit wins, the earlier one is ignored', () {
      final local = {
        'd1': {'day': 'd1', 'note': 'old', 'updated_at': 5},
      };
      final newer = planMerge(
        SyncClass.userEntered,
        local: local,
        incoming: [
          {'day': 'd1', 'note': 'new', 'updated_at': 9},
        ],
        keyOf: byDay,
      );
      expect(newer.replace.single['note'], 'new');
      final older = planMerge(
        SyncClass.userEntered,
        local: local,
        incoming: [
          {'day': 'd1', 'note': 'older', 'updated_at': 1},
        ],
        keyOf: byDay,
      );
      expect(older.isEmpty, isTrue);
    });

    test('ISO timestamps compare as times', () {
      final p = planMerge(
        SyncClass.userEntered,
        local: {
          'd': {'day': 'd', 'updated_at': '2026-11-04T08:00:00Z'},
        },
        incoming: [
          {'day': 'd', 'updated_at': '2026-11-04T09:00:00+00:00'},
        ],
        keyOf: byDay,
      );
      expect(p.replace, hasLength(1));
    });

    test('applying the same rows twice changes nothing the second time', () {
      final incoming = [
        {'day': 'd', 'note': 'x', 'updated_at': 3},
      ];
      final first = planMerge(
        SyncClass.userEntered,
        local: const {},
        incoming: incoming,
        keyOf: byDay,
      );
      final local = {for (final r in first.insert) byDay(r): r};
      expect(
        planMerge(
          SyncClass.userEntered,
          local: local,
          incoming: incoming,
          keyOf: byDay,
        ).isEmpty,
        isTrue,
      );
    });

    test('order doesn’t matter, ties included', () {
      final a = {'day': 'd', 'note': 'a', 'updated_at': 4};
      final b = {'day': 'd', 'note': 'b', 'updated_at': 4};
      final c = {'day': 'd', 'note': 'c', 'updated_at': 2};
      final results = <Object?>{};
      for (final order in [
        [a, b, c],
        [c, b, a],
        [b, c, a],
      ]) {
        final p = planMerge(
          SyncClass.userEntered,
          local: const {},
          incoming: order,
          keyOf: byDay,
        );
        results.add(p.insert.single['note']);
      }
      expect(results, {'b'});
    });
  });

  test('derived and device-local tables are never merged', () {
    expect(
      () => planMerge(
        SyncClass.derived,
        local: const {},
        incoming: const [],
        keyOf: byDay,
      ),
      throwsArgumentError,
    );
  });

  test('every class uploads or not as planned', () {
    expect(uploads('health_records'), isTrue);
    expect(uploads('journal'), isTrue);
    expect(uploads('daily_scores'), isFalse);
    expect(uploads('sync_state'), isFalse);
    expect(() => uploads('new_table'), throwsStateError);
  });
}
