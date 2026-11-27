import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The account a purchase is bought under (backend/src/account_ids.ts).
/// iOS `appAccountToken`: RFC 4122 version-5 UUID of the uid under Tempo's
/// namespace. Android `obfuscatedAccountId`: SHA-256 hex of the uid.
const appAccountNamespace = '6f1d3c52-8f0e-4b8e-9a43-2a7d6c1b5e90';

String appAccountToken(String uid) {
  final ns = [
    for (var i = 0; i < 32; i += 2)
      int.parse(
        appAccountNamespace.replaceAll('-', '').substring(i, i + 2),
        radix: 16,
      ),
  ];
  final h = sha1.convert([...ns, ...utf8.encode(uid)]).bytes.sublist(0, 16);
  h[6] = (h[6] & 0x0f) | 0x50;
  h[8] = (h[8] & 0x3f) | 0x80;
  final x = h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${x.substring(0, 8)}-${x.substring(8, 12)}-${x.substring(12, 16)}-'
      '${x.substring(16, 20)}-${x.substring(20)}';
}

String obfuscatedAccountId(String uid) =>
    sha256.convert(utf8.encode(uid)).toString();
