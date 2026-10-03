/// Pure byte-level encoders/decoders. No BLE here, so it is unit-testable.
///
/// All opcodes and layouts are `TODO(verify)` until confirmed against a
/// capture in docs/packets/. Once confirmed, replace the synthetic test
/// vectors in test/ with golden vectors from the capture.
library;

import 'dart:typed_data';

/// Auth handshake variant. Which one the band speaks depends on firmware;
/// the spike tries [modern] first and falls back to [legacy].
enum AuthVariant {
  /// Opcodes with the high bit set. TODO(verify)
  modern(requestRandom: [0x82, 0x00, 0x02], sendKeyPrefix: [0x83, 0x00]),

  /// Original Huami opcodes. TODO(verify)
  legacy(requestRandom: [0x02, 0x00], sendKeyPrefix: [0x03, 0x00]);

  const AuthVariant({required this.requestRandom, required this.sendKeyPrefix});

  final List<int> requestRandom;
  final List<int> sendKeyPrefix;

  int get requestOpcode => requestRandom[0];
  int get sendKeyOpcode => sendKeyPrefix[0];

  Uint8List sendKey(Uint8List encrypted) =>
      Uint8List.fromList([...sendKeyPrefix, ...encrypted]);
}

/// Response header byte on the auth characteristic. TODO(verify)
const authResponseHeader = 0x10;

/// Status byte meaning success. TODO(verify)
const authStatusOk = 0x01;

/// A notification on the auth characteristic: `[0x10, opcode, status, ...]`.
final class AuthResponse {
  const AuthResponse(this.opcode, this.status, this.payload);

  final int opcode;
  final int status;
  final Uint8List payload;

  bool get ok => status == authStatusOk;

  /// Returns null for anything that is not shaped like an auth response.
  static AuthResponse? parse(List<int> data) {
    if (data.length < 3 || data[0] != authResponseHeader) return null;
    return AuthResponse(data[1], data[2], Uint8List.fromList(data.sublist(3)));
  }

  /// The 16-byte challenge, if this is a successful random-number reply.
  Uint8List? challengeFor(AuthVariant v) =>
      opcode == v.requestOpcode && ok && payload.length >= 16
      ? Uint8List.sublistView(payload, 0, 16)
      : null;

  @override
  String toString() =>
      'AuthResponse(op=0x${opcode.toRadixString(16)}, '
      'status=0x${status.toRadixString(16)}, ${payload.length}B)';
}

/// Heart Rate Measurement (SIG 0x2A37). Flags bit 0: 0 = uint8 BPM,
/// 1 = uint16 LE BPM. Standard layout; TODO(verify) the band follows it.
int? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final wide = data[0] & 0x01 == 1;
  if (wide) {
    if (data.length < 3) return null;
    return data[1] | (data[2] << 8);
  }
  if (data.length < 2) return null;
  return data[1];
}

/// Writes to the HR control point (0x2A39). Huami-specific. TODO(verify)
abstract final class HrCommands {
  static final stopManual = Uint8List.fromList([0x15, 0x02, 0x00]);
  static final stopContinuous = Uint8List.fromList([0x15, 0x01, 0x00]);
  static final startContinuous = Uint8List.fromList([0x15, 0x01, 0x01]);
  static final keepAlive = Uint8List.fromList([0x16]);

  /// How often to resend [keepAlive]. TODO(verify) against when HR stops.
  static const keepAliveInterval = Duration(seconds: 12);
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
