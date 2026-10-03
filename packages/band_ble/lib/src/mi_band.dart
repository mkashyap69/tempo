import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'auth_key.dart';
import 'crypto.dart';
import 'packet_log.dart';
import 'protocol.dart';
import 'uuids.dart';

class BandException implements Exception {
  BandException(this.message);
  final String message;
  @override
  String toString() => 'BandException: $message';
}

/// One connected Mi Band 6. Every write and notification goes to [log].
class MiBand {
  MiBand(this.device, {this.log = const NoopPacketLog()});

  final BluetoothDevice device;
  final PacketLog log;

  final _chars = <String, BluetoothCharacteristic>{};
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _keepAlive;

  static const _timeout = Duration(seconds: 10);

  void _info(String note) =>
      log.record(PacketEvent(dir: PacketDir.info, note: note));

  Future<void> connect() async {
    _info('connect ${device.remoteId.str} "${device.platformName}"');
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
    );
    final services = await device.discoverServices();
    for (final s in services) {
      _info('service ${s.uuid.str128}');
      for (final c in s.characteristics) {
        _chars[c.uuid.str128] = c;
        final p = c.properties;
        final props = [
          if (p.read) 'read',
          if (p.write) 'write',
          if (p.writeWithoutResponse) 'writeNoResp',
          if (p.notify) 'notify',
          if (p.indicate) 'indicate',
        ].join(',');
        _info('  char ${c.uuid.str128} [$props]');
      }
    }
  }

  BluetoothCharacteristic _char(String uuid) {
    final c = _chars[Guid(uuid).str128];
    if (c == null) throw BandException('characteristic $uuid not found');
    return c;
  }

  Future<void> _write(
    String uuid,
    List<int> bytes, {
    bool redact = false,
  }) async {
    final c = _char(uuid);
    log.record(
      PacketEvent(
        dir: PacketDir.tx,
        characteristic: uuid,
        bytes: redact ? null : bytes,
        note: redact ? '${bytes.length}B, payload redacted' : null,
      ),
    );
    await c.write(bytes, withoutResponse: !c.properties.write);
  }

  Future<void> _subscribe(String uuid, void Function(List<int>) onData) async {
    final c = _char(uuid);
    _subs.add(
      c.onValueReceived.listen((v) {
        log.record(
          PacketEvent(dir: PacketDir.rx, characteristic: uuid, bytes: v),
        );
        onData(v);
      }),
    );
    await c.setNotifyValue(true);
  }

  /// Reads firmware / software revision strings, logging both.
  Future<String> readFirmware() async {
    final parts = <String>[];
    for (final uuid in [
      BandUuids.firmwareRevision,
      BandUuids.softwareRevision,
    ]) {
      final c = _chars[Guid(uuid).str128];
      if (c == null || !c.properties.read) continue;
      final v = await c.read();
      log.record(
        PacketEvent(
          dir: PacketDir.rx,
          characteristic: uuid,
          bytes: v,
          note: 'read',
        ),
      );
      parts.add(String.fromCharCodes(v));
    }
    final fw = parts.join(' / ');
    _info('firmware "$fw"');
    return fw;
  }

  /// Runs the AES challenge handshake. Tries each variant in order and
  /// returns the one the band accepted.
  Future<AuthVariant> authenticate(
    AuthKey key, {
    List<AuthVariant> variants = AuthVariant.values,
  }) async {
    final responses = StreamController<AuthResponse>.broadcast();
    await _subscribe(BandUuids.auth, (v) {
      final r = AuthResponse.parse(v);
      if (r != null) responses.add(r);
    });
    try {
      for (final variant in variants) {
        _info('auth: trying ${variant.name}');
        final challengeF = responses.stream
            .firstWhere((r) => r.opcode == variant.requestOpcode)
            .timeout(_timeout);
        await _write(BandUuids.auth, variant.requestRandom);
        final AuthResponse cr;
        try {
          cr = await challengeF;
        } on TimeoutException {
          _info('auth: ${variant.name} no challenge reply');
          continue;
        }
        final challenge = cr.challengeFor(variant);
        if (challenge == null) {
          _info('auth: ${variant.name} rejected request: $cr');
          continue;
        }
        final doneF = responses.stream
            .firstWhere((r) => r.opcode == variant.sendKeyOpcode)
            .timeout(_timeout);
        // The encrypted reply is redacted from the log on principle.
        await _write(
          BandUuids.auth,
          variant.sendKey(encryptChallenge(key, Uint8List.fromList(challenge))),
          redact: true,
        );
        final done = await doneF;
        if (done.ok) {
          _info('auth: OK via ${variant.name}');
          return variant;
        }
        throw BandException('band rejected key ($done). Wrong or stale key?');
      }
      throw BandException('no auth variant got a challenge from the band');
    } finally {
      await responses.close();
    }
  }

  /// Starts continuous HR measurement; emits BPM about once a second.
  Future<Stream<int>> startLiveHr() async {
    final bpm = StreamController<int>.broadcast();
    await _subscribe(BandUuids.heartRateMeasurement, (v) {
      final hr = parseHeartRateMeasurement(v);
      if (hr != null) bpm.add(hr);
    });
    await _write(BandUuids.heartRateControlPoint, HrCommands.stopManual);
    await _write(BandUuids.heartRateControlPoint, HrCommands.stopContinuous);
    await _write(BandUuids.heartRateControlPoint, HrCommands.startContinuous);
    _keepAlive = Timer.periodic(HrCommands.keepAliveInterval, (_) {
      _write(
        BandUuids.heartRateControlPoint,
        HrCommands.keepAlive,
      ).catchError((Object e) => _info('keep-alive failed: $e'));
    });
    return bpm.stream;
  }

  Future<void> stopLiveHr() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    await _write(BandUuids.heartRateControlPoint, HrCommands.stopContinuous);
  }

  Future<void> disconnect() async {
    _keepAlive?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _info('disconnect');
    await device.disconnect();
  }
}
