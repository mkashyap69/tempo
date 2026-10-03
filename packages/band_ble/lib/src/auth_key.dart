import 'dart:typed_data';

/// A 16-byte Huami auth key. `toString` never prints the key.
final class AuthKey {
  AuthKey._(this._bytes);

  final Uint8List _bytes;

  /// Accepts 32 hex digits, with an optional `0x` prefix and whitespace.
  static AuthKey parse(String input) {
    var s = input.trim().replaceAll(RegExp(r'\s'), '');
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(s)) {
      throw const FormatException('Auth key must be 32 hex digits');
    }
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return AuthKey._(out);
  }

  /// Raw bytes, for the cipher only. Do not log.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'AuthKey(<redacted>)';
}
