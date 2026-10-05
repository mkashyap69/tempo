import 'dart:convert';
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
      for (final v in [AuthVariant.modern, AuthVariant.legacy]) {
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

  test('chunked auth packets carry the length on the first write', () {
    final packets = chunkedPackets(0, [1, 2, 3, 4]);
    expect(packets, hasLength(1));
    expect(packets.single, [
      0x03,
      0x07,
      0x00,
      0x00,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x82,
      0x00,
      1,
      2,
      3,
      4,
    ]);
  });

  test('chunked reader emits the challenge once, then ok', () {
    final reader = ChunkedAuthReader();
    final body = List<int>.filled(64, 0x11);
    final first = [
      0x03,
      0x01,
      0x00,
      0x00,
      0x00,
      67,
      0,
      0,
      0,
      0x82,
      0x00,
      0x10,
      0x04,
      0x01,
      ...body,
    ];
    expect(reader.add(first), 'challenge');
    expect(reader.add(first), isNull);
    expect(reader.bytes, body);
    reader.reset();
    expect(
      reader.add([
        0x03,
        0x06,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0x82,
        0x00,
        0x10,
        0x05,
        0x01,
      ]),
      'ok',
    );
  });

  test('sect163r2 public key matches the B-163 vector', () {
    final pub = huamiPublicForTest(
      Uint8List.fromList([
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0a,
        0x0b,
        0x0c,
        0x0d,
        0x0e,
        0x0f,
        0x10,
        0x11,
        0x12,
        0x13,
        0x14,
        0x15,
        0x16,
        0x17,
        0x18,
      ]),
    );
    expect(
      hex(pub),
      'a1e4ad02c2a44ea24152962c140ea063c69b2e5c07000000'
      'cd5073a06d67b78a3bc5f519ab85fb9cf5855dc801000000',
    );
  });

  test('sect163r2 shared secret matches the B-163 vector', () {
    final sw = Stopwatch()..start();
    final shared = huamiSharedForTest(
      Uint8List.fromList([
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0a,
        0x0b,
        0x0c,
        0x0d,
        0x0e,
        0x0f,
        0x10,
        0x11,
        0x12,
        0x13,
        0x14,
        0x15,
        0x16,
        0x17,
        0x18,
      ]),
      Uint8List.fromList([
        0xe7,
        0xc1,
        0xed,
        0xdd,
        0x59,
        0x69,
        0x4a,
        0x9a,
        0x09,
        0xe4,
        0x12,
        0xdf,
        0xe6,
        0xd5,
        0x16,
        0xd4,
        0x51,
        0x18,
        0x7b,
        0xd2,
        0x00,
        0x00,
        0x00,
        0x00,
        0x88,
        0x3d,
        0x62,
        0xd3,
        0x5b,
        0x8d,
        0xbd,
        0x8f,
        0x15,
        0xee,
        0xfb,
        0x70,
        0x61,
        0x99,
        0xfd,
        0x22,
        0x8f,
        0x30,
        0xe1,
        0x89,
        0x01,
        0x00,
        0x00,
        0x00,
      ]),
    );
    sw.stop();
    expect(
      hex(shared),
      '5dd0ce43e619060186f7983a0a1cb07ad38ca35402000000'
      '1d1a085428da00d343ca152231dd5b1360c566f905000000',
    );
    expect(sw.elapsedMilliseconds, lessThan(800));
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

  test('battery parse: SIG byte 0, Huami byte 1, out of range ignored', () {
    expect(parseBattery([64], huami: false), 64);
    expect(parseBattery([0x0f, 82, 0, 0], huami: true), 82);
    expect(parseBattery([200], huami: false), isNull);
    expect(parseBattery([], huami: true), isNull);
  });

  test('chunk assembler reports payload length', () {
    final a = ChunkAssembler()
      ..add([0, 1, 2, 3])
      ..add([1, 4]);
    expect(a.length, 4);
  });

  test('new alert bytes: category, count, text cut to 20 bytes', () {
    expect(newAlertBytes('Hi'), [0x00, 0x01, 0x48, 0x69]);
    final long = newAlertBytes('Easy run at 18:00? Start when ready');
    expect(long.length, 20);
    expect(long.sublist(0, 2), [0x00, 0x01]);
    // Multi-byte characters are never split.
    final uni = newAlertBytes('Run 35′ — 18:00 ✓✓✓✓', maxBytes: 12);
    expect(() => utf8.decode(uni.sublist(2)), returnsNormally);
  });
}
