// Synthetic vectors. Once docs/packets/ holds a real capture, add golden
// tests built from it and drop the TODO(verify) markers they confirm.
import 'dart:typed_data';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthKey', () {
    test('parses hex with prefix and whitespace', () {
      final k = AuthKey.parse(' 0x000102030405060708090a0b0c0d0e0F ');
      expect(k.bytes, List.generate(16, (i) => i));
    });
    test('rejects bad input', () {
      expect(() => AuthKey.parse('abc'), throwsFormatException);
      expect(() => AuthKey.parse('g' * 32), throwsFormatException);
    });
    test('toString never shows the key', () {
      final k = AuthKey.parse('00112233445566778899aabbccddeeff');
      expect(k.toString(), isNot(contains('0011')));
    });
  });

  test('AES-128 matches the FIPS-197 C.1 vector', () {
    final key = AuthKey.parse('000102030405060708090a0b0c0d0e0f');
    final pt = Uint8List.fromList(
      List.generate(16, (i) => (i << 4) | i), // 00112233...ff
    );
    expect(hex(encryptChallenge(key, pt)), '69c4e0d86a7b0430d8cdb78070b4c55a');
  });

  group('AuthResponse', () {
    final random = List.generate(16, (i) => 0xa0 + i);
    test('extracts challenge for each variant', () {
      for (final v in AuthVariant.values) {
        final r = AuthResponse.parse([0x10, v.requestOpcode, 0x01, ...random])!;
        expect(r.challengeFor(v), random);
      }
    });
    test('no challenge on failure status or wrong opcode', () {
      final bad = AuthResponse.parse([0x10, 0x82, 0x04, ...random])!;
      expect(bad.ok, isFalse);
      expect(bad.challengeFor(AuthVariant.modern), isNull);
      expect(bad.challengeFor(AuthVariant.legacy), isNull);
    });
    test('ignores non-auth packets', () {
      expect(AuthResponse.parse([0x01, 0x02]), isNull);
      expect(AuthResponse.parse([0x11, 0x02, 0x01]), isNull);
    });
    test('sendKey prepends the variant prefix', () {
      final enc = Uint8List(16);
      expect(AuthVariant.legacy.sendKey(enc).take(2), [0x03, 0x00]);
      expect(AuthVariant.legacy.sendKey(enc).length, 18);
    });
  });

  group('parseHeartRateMeasurement', () {
    test('uint8', () => expect(parseHeartRateMeasurement([0x00, 72]), 72));
    test(
      'uint16',
      () => expect(parseHeartRateMeasurement([0x01, 0x2c, 0x01]), 300),
    );
    test('short', () {
      expect(parseHeartRateMeasurement([]), isNull);
      expect(parseHeartRateMeasurement([0x00]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0x10]), isNull);
    });
  });

  test('PacketEvent writes hex and omits redacted bytes', () {
    final at = DateTime.utc(2026, 10, 3);
    expect(
      PacketEvent(
        dir: PacketDir.tx,
        characteristic: 'x',
        bytes: [0x15, 1],
        at: at,
      ).toJsonLine(),
      '{"ts":"2026-10-03T00:00:00.000Z","dir":"tx","char":"x","hex":"1501"}',
    );
    expect(
      PacketEvent(dir: PacketDir.tx, note: 'redacted', at: at).toJsonLine(),
      isNot(contains('hex')),
    );
  });
}
