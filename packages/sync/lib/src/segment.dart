import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'codec.dart';
import 'keys.dart';

/// Where a segment belongs. All of it is bound into the associated data, so
/// a segment copied to another account, device or position fails to open.
class SegmentId {
  const SegmentId({
    required this.uid,
    required this.device,
    required this.seq,
    required this.keyVersion,
  });

  final String uid;
  final String device;

  /// Per device, from 1, never reused.
  final int seq;
  final int keyVersion;

  /// The object path under the sync bucket (Backend plan → Cloud Storage):
  /// one object per upload, holding every table that changed (launch plan
  /// cost lever 2).
  String get path => 'u/$uid/d/$device/${seq.toString().padLeft(10, '0')}.seg';

  @override
  bool operator ==(Object o) =>
      o is SegmentId &&
      o.uid == uid &&
      o.device == device &&
      o.seq == seq &&
      o.keyVersion == keyVersion;

  @override
  int get hashCode => Object.hash(uid, device, seq, keyVersion);
}

/// One encrypted upload.
///
/// Bytes: `TSG1` · format version (1 byte, 1) · key version (4 bytes, big
/// endian) · seq (8 bytes) · nonce (24) · ciphertext · Poly1305 tag (16).
/// The plaintext is [RowCodec] output. The cipher is XChaCha20-Poly1305
/// under the [DataKey]; associated data is `tempo/sync/segment/v1`, the uid
/// and device (length-prefixed), seq and key version.
abstract final class Segment {
  static final magic = ascii.encode('TSG1');
  static const formatVersion = 1;
  static const _headerLength = 4 + 1 + 4 + 8;
  static final _aead = Xchacha20.poly1305Aead();

  static Uint8List associatedData(SegmentId id) => Uint8List.fromList([
    ...utf8.encode('tempo/sync/segment/v1'),
    ...lengthPrefixed(id.uid),
    ...lengthPrefixed(id.device),
    ...uintBytes(id.seq, 8),
    ...uintBytes(id.keyVersion, 4),
  ]);

  /// Encrypts [tables] (table name → rows). [nonce] is for tests only.
  static Future<Uint8List> seal(
    SegmentId id,
    Map<String, List<Map<String, Object?>>> tables,
    DataKey key, {
    List<int>? nonce,
  }) => sealBytes(id, RowCodec.encode(tables), key, nonce: nonce);

  static Future<Uint8List> sealBytes(
    SegmentId id,
    List<int> plaintext,
    DataKey key, {
    List<int>? nonce,
  }) async {
    final n = nonce ?? _aead.newNonce();
    if (n.length != 24) throw ArgumentError('XChaCha20 nonces are 24 bytes');
    final box = await _aead.encrypt(
      plaintext,
      secretKey: key.secret,
      nonce: n,
      aad: associatedData(id),
    );
    return Uint8List.fromList([
      ...magic,
      formatVersion,
      ...uintBytes(id.keyVersion, 4),
      ...uintBytes(id.seq, 8),
      ...n,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// The key version a segment was sealed with, to pick the right key.
  static int keyVersionOf(List<int> bytes) {
    _checkHeader(bytes);
    return readUint(bytes, 5, 4);
  }

  static void _checkHeader(List<int> bytes) {
    if (bytes.length < _headerLength + 24 + 16 ||
        !bytesEqual(bytes.sublist(0, 4), magic)) {
      throw const FormatException('not a Tempo sync segment');
    }
    if (bytes[4] != formatVersion) {
      throw FormatException(
        'segment format ${bytes[4]} is newer than this app; update Tempo',
      );
    }
  }

  /// Opens a segment expected at [id]. Throws [SyncCryptoException] when the
  /// key is wrong or the bytes were changed or moved.
  static Future<Uint8List> openBytes(
    SegmentId id,
    List<int> bytes,
    DataKey key,
  ) async {
    _checkHeader(bytes);
    if (readUint(bytes, 5, 4) != id.keyVersion ||
        readUint(bytes, 9, 8) != id.seq) {
      throw const SyncCryptoException('segment is not the one expected here');
    }
    const n0 = _headerLength, c0 = n0 + 24;
    final tag0 = bytes.length - 16;
    try {
      final plain = await _aead.decrypt(
        SecretBox(
          bytes.sublist(c0, tag0),
          nonce: bytes.sublist(n0, c0),
          mac: Mac(bytes.sublist(tag0)),
        ),
        secretKey: key.secret,
        aad: associatedData(id),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const SyncCryptoException('segment did not authenticate');
    }
  }

  static Future<Map<String, List<Map<String, Object?>>>> open(
    SegmentId id,
    List<int> bytes,
    DataKey key,
  ) async => RowCodec.decode(await openBytes(id, bytes, key));
}
