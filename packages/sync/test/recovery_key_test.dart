import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  // BIP-39 English vectors (trezor/python-mnemonic vectors.json), 256-bit.
  final vectors = {
    '00' * 32: '${List.filled(23, 'abandon').join(' ')} art',
    '7f' * 32: 'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title',
    'ff' * 32: '${List.filled(23, 'zoo').join(' ')} vote',
  };

  for (final MapEntry(key: hexEntropy, value: phrase) in vectors.entries) {
    test('BIP-39 vector ${hexEntropy.substring(0, 2)}…', () async {
      final bytes = [
        for (var i = 0; i < 64; i += 2)
          int.parse(hexEntropy.substring(i, i + 2), radix: 16),
      ];
      final rk = RecoveryKey.fromEntropy(bytes);
      expect((await rk.words()).join(' '), phrase);
      expect((await RecoveryKey.parse(phrase)).entropy, bytes);
    });
  }

  test('typed words parse loosely', () async {
    final rk = RecoveryKey.generate();
    final words = await rk.words();
    final printed = [
      for (final (i, w) in words.indexed) '${i + 1}. ${w.toUpperCase()}',
    ].join(',\n ');
    expect((await RecoveryKey.parse(printed)).entropy, rk.entropy);
  });

  test('wrong count, unknown word and bad checksum are refused', () async {
    final words = await RecoveryKey.generate().words();
    await expectLater(
      RecoveryKey.parse(words.take(23).join(' ')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('24 words'),
        ),
      ),
    );
    await expectLater(
      RecoveryKey.parse([...words.take(23), 'tempo'].join(' ')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Word 24'),
        ),
      ),
    );
    // Swapping two words keeps every word valid but breaks the checksum
    // (unless they're equal, which a fresh key makes vanishingly unlikely).
    final swapped = [...words]
      ..[0] = words[1]
      ..[1] = words[0];
    if (words[0] != words[1]) {
      await expectLater(
        RecoveryKey.parse(swapped.join(' ')),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('a recovery key from another account does not unwrap', () async {
    final key = DataKey.generate();
    final rk = RecoveryKey.generate();
    final w = await KeyWrap.wrap(
      key,
      wrappingKey: await KeyWrap.recoveryWrappingKey(rk, 'alice'),
      uid: 'alice',
      kind: WrapKind.recovery,
      keyVersion: 1,
    );
    await expectLater(
      KeyWrap.unwrap(
        w,
        wrappingKey: await KeyWrap.recoveryWrappingKey(rk, 'bob'),
        uid: 'bob',
      ),
      throwsA(isA<SyncCryptoException>()),
    );
    await expectLater(
      KeyWrap.unwrap(
        w,
        wrappingKey: await KeyWrap.recoveryWrappingKey(
          RecoveryKey.generate(),
          'alice',
        ),
        uid: 'alice',
      ),
      throwsA(isA<SyncCryptoException>()),
    );
  });
}
