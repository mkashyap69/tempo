import 'dart:typed_data';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  final key = DataKey.generate();
  const id = SegmentId(uid: 'u1', device: 'd1', seq: 3, keyVersion: 2);
  final tables = {
    'journal': [
      {'day': '2026-11-04', 'tag': 'alcohol', 'value': 1, 'updated_at': 10},
    ],
    'health_records': [
      {'key': 'hk:abc', 'kind': 'heartRate', 'value': 61.5, 'start': 1},
    ],
  };

  test('rows survive seal and open', () async {
    final bytes = await Segment.seal(id, tables, key);
    expect(await Segment.open(id, bytes, key), tables);
  });

  test('two seals of the same rows differ (random nonce)', () async {
    expect(
      await Segment.seal(id, tables, key),
      isNot(await Segment.seal(id, tables, key)),
    );
  });

  test('the server copy holds no plaintext', () async {
    final bytes = await Segment.seal(id, tables, key);
    final text = String.fromCharCodes(bytes);
    for (final s in ['alcohol', 'heartRate', 'journal', '61.5']) {
      expect(text.contains(s), isFalse, reason: s);
    }
  });

  group('a segment does not open', () {
    late Uint8List bytes;
    setUp(() async => bytes = await Segment.seal(id, tables, key));

    test('with another key', () async {
      await expectLater(
        Segment.open(id, bytes, DataKey.generate()),
        throwsA(isA<SyncCryptoException>()),
      );
    });
    test('under another account', () async {
      const other = SegmentId(uid: 'u2', device: 'd1', seq: 3, keyVersion: 2);
      await expectLater(
        Segment.open(other, bytes, key),
        throwsA(isA<SyncCryptoException>()),
      );
    });
    test('from another device', () async {
      const other = SegmentId(uid: 'u1', device: 'd2', seq: 3, keyVersion: 2);
      await expectLater(
        Segment.open(other, bytes, key),
        throwsA(isA<SyncCryptoException>()),
      );
    });
    test('at another position', () async {
      const other = SegmentId(uid: 'u1', device: 'd1', seq: 4, keyVersion: 2);
      await expectLater(
        Segment.open(other, bytes, key),
        throwsA(isA<SyncCryptoException>()),
      );
    });
    test('with one byte changed', () async {
      final bad = Uint8List.fromList(bytes)..[bytes.length - 20] ^= 1;
      await expectLater(
        Segment.open(id, bad, key),
        throwsA(isA<SyncCryptoException>()),
      );
    });
    test('when it isn’t a segment', () {
      expect(() => Segment.keyVersionOf([1, 2, 3]), throwsFormatException);
    });
    test('from a newer format', () {
      final newer = Uint8List.fromList(bytes)..[4] = 2;
      expect(() => Segment.keyVersionOf(newer), throwsFormatException);
    });
  });

  test('object paths sort by seq', () {
    const a = SegmentId(uid: 'u', device: 'd', seq: 9, keyVersion: 1);
    const b = SegmentId(uid: 'u', device: 'd', seq: 10, keyVersion: 1);
    expect(a.path, 'u/u/d/d/0000000009.seg');
    expect(a.path.compareTo(b.path), lessThan(0));
  });

  test('canonical JSON sorts keys at every level', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {
          'd': 2,
          'c': [
            {'z': 1, 'y': 2},
          ],
        },
      }),
      '{"a":{"c":[{"y":2,"z":1}],"d":2},"b":1}',
    );
  });
}
