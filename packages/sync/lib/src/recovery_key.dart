import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bip39_english.dart';

/// The 24-word recovery key shown once at setup (decision G-O4).
///
/// 256 bits of entropy written as BIP-39 English words: 256 bits plus an
/// 8-bit SHA-256 checksum make 24 words of 11 bits. It unlocks the account's
/// data key when the platform keychain can't (a move between iPhone and
/// Android, or a lost keychain). It is random, not a password, so it needs
/// no stretching; [KeyWrap] derives a wrapping key from it with HKDF.
class RecoveryKey {
  RecoveryKey._(this.entropy);

  /// The 32 random bytes the words encode.
  final Uint8List entropy;

  static const wordCount = 24;

  /// A new key from a cryptographically secure source.
  factory RecoveryKey.generate([Random? random]) {
    final r = random ?? Random.secure();
    return RecoveryKey._(
      Uint8List.fromList([for (var i = 0; i < 32; i++) r.nextInt(256)]),
    );
  }

  factory RecoveryKey.fromEntropy(List<int> entropy) {
    if (entropy.length != 32) {
      throw ArgumentError(
        'a recovery key holds 32 bytes, not ${entropy.length}',
      );
    }
    return RecoveryKey._(Uint8List.fromList(entropy));
  }

  /// Parses words as typed: any case, any whitespace, commas or numbers
  /// between them ("1. abandon 2. ability …" from a printout works). Throws
  /// [FormatException] with a message fit to show the user.
  static Future<RecoveryKey> parse(String typed) async {
    final words = typed
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length != wordCount) {
      throw FormatException(
        'A recovery key has $wordCount words; this has ${words.length}.',
      );
    }
    final bits = StringBuffer();
    for (final (i, w) in words.indexed) {
      final n = _index[w];
      if (n == null) {
        throw FormatException(
          'Word ${i + 1}, “$w”, isn’t a recovery-key word.',
        );
      }
      bits.write(n.toRadixString(2).padLeft(11, '0'));
    }
    final s = bits.toString(); // 264 bits
    final entropy = Uint8List.fromList([
      for (var i = 0; i < 256; i += 8)
        int.parse(s.substring(i, i + 8), radix: 2),
    ]);
    final check = int.parse(s.substring(256), radix: 2);
    if (await _checksum(entropy) != check) {
      throw const FormatException(
        'These words don’t add up to a recovery key. Check each one against your copy.',
      );
    }
    return RecoveryKey._(entropy);
  }

  /// The 24 words, in order.
  Future<List<String>> words() async {
    final bits = StringBuffer();
    for (final b in entropy) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    bits.write((await _checksum(entropy)).toRadixString(2).padLeft(8, '0'));
    final s = bits.toString();
    return [
      for (var i = 0; i < s.length; i += 11)
        bip39English[int.parse(s.substring(i, i + 11), radix: 2)],
    ];
  }

  static Future<int> _checksum(List<int> entropy) async =>
      (await Sha256().hash(entropy)).bytes.first;

  static final Map<String, int> _index = {
    for (final (i, w) in bip39English.indexed) w: i,
  };
}
