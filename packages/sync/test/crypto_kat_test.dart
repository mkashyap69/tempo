// Known-answer tests for the crypto (CLAUDE.md: packages/sync has KATs).
// Vectors marked "reference" were computed independently with
// @noble/ciphers 1.3.0 and @noble/hashes 1.8.0 from the layout in
// segment.dart and keys.dart; the XChaCha20-Poly1305 vector is from
// draft-irtf-cfrg-xchacha-03 §A.3.1.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sync/src/bytes.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  test('XChaCha20-Poly1305 matches draft-irtf-cfrg-xchacha §A.3.1', () async {
    final box = await Xchacha20.poly1305Aead().encrypt(
      utf8.encode(
        "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.",
      ),
      secretKey: SecretKey(
        unhex(
          '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f',
        ),
      ),
      nonce: unhex('404142434445464748494a4b4c4d4e4f5051525354555657'),
      aad: unhex('50515253c0c1c2c3c4c5c6c7'),
    );
    expect(
      hex(box.cipherText),
      'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb'
      '731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452'
      '2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9'
      '21f9664c97637da9768812f615c68b13b52e',
    );
    expect(hex(box.mac.bytes), 'c0875924c1c7987947deafd8780acf49');
  });

  const id = SegmentId(uid: 'uid-123', device: 'dev-A', seq: 7, keyVersion: 1);
  final key = DataKey(List.generate(32, (i) => i));
  final nonce = List.generate(24, (i) => 0xa0 + i);
  final plain = utf8.encode(
    '{"journal":[{"day":"2026-11-04","updated_at":1}]}',
  );
  const sealed =
      '5453473101000000010000000000000007a0a1a2a3a4a5a6a7a8a9aaabacadae'
      'afb0b1b2b3b4b5b6b73ece6072c22fcacd0d4d17d20a12c7a14288a50e9836f8'
      'ef3071bacad797dc1af3f2da4b273219a8fa8a1a74a105d273d8e4e6aca2fbae'
      '8bcdf6bd6e560ae6c906';

  test('a segment seals to the reference bytes', () async {
    expect(hex(await Segment.sealBytes(id, plain, key, nonce: nonce)), sealed);
  });

  test('the reference segment opens', () async {
    expect(
      utf8.decode(await Segment.openBytes(id, unhex(sealed), key)),
      utf8.decode(plain),
    );
    expect(Segment.keyVersionOf(unhex(sealed)), 1);
  });

  test('a recovery key derives the reference wrapping key and wrap', () async {
    final rk = RecoveryKey.fromEntropy(List.filled(32, 0));
    final wk = await KeyWrap.recoveryWrappingKey(rk, 'uid-123');
    expect(
      hex(await wk.extractBytes()),
      '76c051cd01aa793c1a20983f644facf4fac2d96b219d2702e54e44901449ea64',
    );
    final w = await KeyWrap.wrap(
      key,
      wrappingKey: wk,
      uid: 'uid-123',
      kind: WrapKind.recovery,
      keyVersion: 1,
      nonce: List.generate(24, (i) => i),
    );
    expect(
      hex(w.box),
      '5bb65ec3212c44fe868e93ea85c285cfce4911f2603d20e21e03d05017a024c7'
      'b51416f3cc7e6e8110b310deb9701f79',
    );
    final back = await KeyWrap.unwrap(
      WrappedKey.fromJson(jsonDecode(jsonEncode(w.toJson()))),
      wrappingKey: wk,
      uid: 'uid-123',
    );
    expect(back.bytes, key.bytes);
  });
}
