import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'recovery_key.dart';

/// The account's 256-bit data key. Every segment is encrypted under it. It
/// exists in plain form only in memory on the user's phones; stored, it is
/// always a [WrappedKey].
class DataKey {
  DataKey(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != 32) throw ArgumentError('a data key is 32 bytes');
  }

  factory DataKey.generate([Random? random]) {
    final r = random ?? Random.secure();
    return DataKey([for (var i = 0; i < 32; i++) r.nextInt(256)]);
  }

  final Uint8List bytes;

  SecretKey get secret => SecretKey(bytes);
}

/// How a wrapped key was unlocked.
enum WrapKind {
  /// By the recovery key's words.
  recovery,

  /// By a key held in the platform's synced keychain (iCloud Keychain item,
  /// Android Block Store).
  keychain,
}

/// A data key encrypted under a wrapping key. Safe to store on the server
/// (`sync_manifests`) or in the platform keychain.
class WrappedKey {
  const WrappedKey({
    required this.kind,
    required this.keyVersion,
    required this.nonce,
    required this.box,
  });

  final WrapKind kind;
  final int keyVersion;
  final Uint8List nonce;

  /// Ciphertext and the 16-byte Poly1305 tag.
  final Uint8List box;

  Map<String, Object> toJson() => {
    'v': 1,
    'kind': kind.name,
    'kv': keyVersion,
    'nonce': base64.encode(nonce),
    'box': base64.encode(box),
  };

  factory WrappedKey.fromJson(Map<String, Object?> j) {
    if (j['v'] != 1)
      throw FormatException('unknown wrapped-key version ${j['v']}');
    return WrappedKey(
      kind: WrapKind.values.byName(j['kind']! as String),
      keyVersion: j['kv']! as int,
      nonce: base64.decode(j['nonce']! as String),
      box: base64.decode(j['box']! as String),
    );
  }
}

/// Raised when a key or segment doesn't open: wrong key, or the bytes were
/// changed or moved.
class SyncCryptoException implements Exception {
  const SyncCryptoException(this.message);
  final String message;
  @override
  String toString() => 'SyncCryptoException: $message';
}

/// Wraps and unwraps the data key (XChaCha20-Poly1305). The associated data
/// binds the account id, the wrap kind and the key version, so a wrapped key
/// can't be swapped between accounts or kinds.
abstract final class KeyWrap {
  static final _aead = Xchacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// The wrapping key a recovery key unlocks.
  static Future<SecretKey> recoveryWrappingKey(RecoveryKey rk, String uid) =>
      _hkdf.deriveKey(
        secretKey: SecretKey(rk.entropy),
        nonce: utf8.encode('tempo/sync/recovery-salt/v1'),
        info: lengthPrefixed(uid),
      );

  static Uint8List _aad(String uid, WrapKind kind, int keyVersion) =>
      Uint8List.fromList([
        ...utf8.encode('tempo/sync/wrap/v1'),
        ...lengthPrefixed(uid),
        ...lengthPrefixed(kind.name),
        ...uintBytes(keyVersion, 4),
      ]);

  static Future<WrappedKey> wrap(
    DataKey key, {
    required SecretKey wrappingKey,
    required String uid,
    required WrapKind kind,
    required int keyVersion,
    List<int>? nonce,
  }) async {
    final n = nonce ?? _aead.newNonce();
    final box = await _aead.encrypt(
      key.bytes,
      secretKey: wrappingKey,
      nonce: n,
      aad: _aad(uid, kind, keyVersion),
    );
    return WrappedKey(
      kind: kind,
      keyVersion: keyVersion,
      nonce: Uint8List.fromList(n),
      box: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  static Future<DataKey> unwrap(
    WrappedKey w, {
    required SecretKey wrappingKey,
    required String uid,
  }) async {
    if (w.box.length != 32 + 16) {
      throw const SyncCryptoException('wrapped key has the wrong length');
    }
    try {
      final plain = await _aead.decrypt(
        SecretBox(
          w.box.sublist(0, 32),
          nonce: w.nonce,
          mac: Mac(w.box.sublist(32)),
        ),
        secretKey: wrappingKey,
        aad: _aad(uid, w.kind, w.keyVersion),
      );
      return DataKey(plain);
    } on SecretBoxAuthenticationError {
      throw const SyncCryptoException('the key does not unlock this backup');
    }
  }
}
