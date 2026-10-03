import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'auth_key.dart';

/// AES-128-ECB over exactly one 16-byte block, as the auth handshake needs.
Uint8List encryptChallenge(AuthKey key, Uint8List challenge) {
  if (challenge.length != 16) {
    throw ArgumentError.value(challenge.length, 'challenge', 'need 16 bytes');
  }
  final cipher = AESEngine()..init(true, KeyParameter(key.bytes));
  final out = Uint8List(16);
  cipher.processBlock(challenge, 0, out, 0);
  return out;
}
