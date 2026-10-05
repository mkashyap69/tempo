import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'auth_key.dart';
import 'crypto.dart';
import 'fetch.dart';
import 'packet_log.dart';
import 'protocol.dart';
import 'settings.dart';
import 'uuids.dart';

class BandException implements Exception {
  BandException(this.message);
  final String message;
  @override
  String toString() => 'BandException: $message';
}

/// Raw result of one history fetch.
final class FetchResult {
  const FetchResult(this.type, this.start, this.data, this.expected, this.gaps);
  final FetchType type;

  /// Band-reported time of the first record; null if nothing to send.
  final DateTime? start;
  final Uint8List data;
  final int expected;
  final int gaps;
}

/// One connected Mi Band 6. Every write and notification goes to [log].
class MiBand {
  MiBand(this.device, {this.log = const NoopPacketLog()});

  /// Reconnect to a band remembered from an earlier pairing (MAC on Android,
  /// peripheral UUID on iOS).
  MiBand.fromId(String id, {PacketLog log = const NoopPacketLog()})
    : this(BluetoothDevice.fromId(id), log: log);

  final BluetoothDevice device;
  final PacketLog log;

  final _chars = <String, BluetoothCharacteristic>{};
  final _notify = <String, StreamController<List<int>>>{};
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _keepAlive;

  static const _timeout = Duration(seconds: 10);

  String get id => device.remoteId.str;

  void _info(String note) =>
      log.record(PacketEvent(dir: PacketDir.info, note: note));

  Future<void> connect() async {
    _info('connect $id "${device.platformName}"');
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

  bool has(String uuid) => _chars.containsKey(Guid(uuid).str128);

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

  /// Notifications from [uuid], subscribed once and shared.
  Future<Stream<List<int>>> _notifications(String uuid) async {
    final existing = _notify[uuid];
    if (existing != null) return existing.stream;
    final c = _char(uuid);
    final ctrl = _notify[uuid] = StreamController<List<int>>.broadcast();
    _subs.add(
      c.onValueReceived.listen((v) {
        log.record(
          PacketEvent(dir: PacketDir.rx, characteristic: uuid, bytes: v),
        );
        ctrl.add(v);
      }),
    );
    await c.setNotifyValue(true);
    return ctrl.stream;
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
    if (variants.contains(AuthVariant.chunked) &&
        has(BandUuids.chunkedRead) &&
        has(BandUuids.chunkedWrite)) {
      _info('auth: trying chunked');
      if (await _authenticateChunked(key)) return AuthVariant.chunked;
      // A timed-out chunked handshake must not fall through. Modern `82 00 02`
      // on this firmware answers `10 83 07` and the band shows "update the app".
      throw BandException(
        'Band did not finish auth. Move it closer and try again.',
      );
    }
    final responses = (await _notifications(BandUuids.auth))
        .map(AuthResponse.parse)
        .where((r) => r != null)
        .cast<AuthResponse>()
        .asBroadcastStream();
    AuthResponse? rejected;
    for (final variant in variants.where((v) => v != AuthVariant.chunked)) {
      _info('auth: trying ${variant.name}');
      final challengeF = responses
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
      final doneF = responses
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
      // Status other than success after a real challenge. Sending the
      // legacy opcode next makes firmware V1.0.6.20 show "update the app".
      rejected = done;
      _info('auth: ${variant.name} rejected key: $done');
      break;
    }
    if (rejected != null) {
      throw BandException('band rejected key ($rejected). Wrong or stale key?');
    }
    throw BandException('no auth variant got a challenge from the band');
  }

  /// Firmware V1.0.6.x auth on characteristics 0016/0017. TODO(verify).
  Future<bool> _authenticateChunked(AuthKey key) async {
    final incoming = await _notifications(BandUuids.chunkedRead);
    final reader = ChunkedAuthReader();
    final queued = <String>[];
    final poke = StreamController<void>.broadcast();
    final sub = incoming.listen((data) {
      final step = reader.add(data);
      if (step == null) return;
      queued.add(step);
      poke.add(null);
    });
    Future<String> next() async {
      while (queued.isEmpty) {
        await poke.stream.first.timeout(const Duration(seconds: 20));
      }
      return queued.removeAt(0);
    }

    try {
      final ecdh = HuamiEcdh.generate();
      final hello = Uint8List.fromList([
        0x04,
        0x02,
        0x00,
        0x02,
        ...ecdh.publicBytes,
      ]);
      for (final packet in chunkedPackets(0, hello)) {
        await _write(BandUuids.chunkedWrite, packet);
      }
      final step = await next();
      if (step == 'fail') {
        throw BandException('chunked auth rejected');
      }
      if (step != 'challenge') {
        _info('auth: chunked first reply was $step');
        return false;
      }
      final body = reader.bytes;
      if (body.length < 64) {
        _info('auth: chunked challenge is ${body.length}B');
        return false;
      }
      final reply = ecdh.secondCommand(
        key,
        Uint8List.sublistView(body, 0, 16),
        Uint8List.sublistView(body, 16, 64),
      );
      reader.reset();
      final resultF = next();
      for (final packet in chunkedPackets(1, reply)) {
        await _write(BandUuids.chunkedWrite, packet);
      }
      final result = await resultF;
      _info('auth: chunked result $result');
      return result == 'ok';
    } on BandException {
      rethrow;
    } on TimeoutException {
      _info('auth: chunked timed out');
      return false;
    } catch (e) {
      _info('auth: chunked failed: $e');
      return false;
    } finally {
      await sub.cancel();
      await poke.close();
    }
  }

  /// Pairing-time configuration (PLAN.md → BLE layer step 5). Each write is
  /// attempted independently so one unsupported setting doesn't block the rest.
  /// [onStep] is called before each write with its name ('time', 'user',
  /// 'hr interval', 'sleep assist', 'stress'), then with `done` per result.
  Future<List<String>> configure(
    UserProfile profile, {
    int hrEveryMinutes = 1,
    bool sleepAssist = true,
    bool stress = true,
    bool wornLeft = true,
    void Function(String name, {required bool done, bool ok})? onStep,
  }) async {
    final failed = <String>[];
    Future<void> step(String name, String uuid, List<int> bytes) async {
      onStep?.call(name, done: false);
      try {
        if (!has(uuid)) throw BandException('missing $uuid');
        await _write(uuid, bytes);
        onStep?.call(name, done: true, ok: true);
      } catch (e) {
        _info('configure $name failed: $e');
        failed.add(name);
        onStep?.call(name, done: true, ok: false);
      }
    }

    await step(
      'time',
      BandUuids.currentTime,
      SettingsCommands.currentTime(DateTime.now()),
    );
    await step(
      'user',
      BandUuids.userSettings,
      SettingsCommands.userInfo(profile),
    );
    await step(
      'wrist',
      BandUuids.userSettings,
      SettingsCommands.wearLocation(left: wornLeft),
    );
    await step(
      'hr interval',
      BandUuids.heartRateControlPoint,
      SettingsCommands.hrInterval(hrEveryMinutes),
    );
    await step(
      'sleep assist',
      BandUuids.heartRateControlPoint,
      SettingsCommands.sleepAssist(sleepAssist),
    );
    await step(
      'stress',
      BandUuids.config,
      SettingsCommands.stressMonitoring(stress),
    );
    return failed;
  }

  /// Tells the band which wrist it is on.
  Future<void> setWearLocation({required bool left}) =>
      _write(BandUuids.userSettings, SettingsCommands.wearLocation(left: left));

  Future<void> setSleepAssist(bool on) =>
      _write(BandUuids.heartRateControlPoint, SettingsCommands.sleepAssist(on));

  Future<void> setStressMonitoring(bool on) =>
      _write(BandUuids.config, SettingsCommands.stressMonitoring(on));

  /// Writes one alarm slot. Disable with `enabled: false`.
  Future<void> setAlarm(BandAlarm a) =>
      _write(BandUuids.config, SettingsCommands.alarm(a));

  /// Fetches [type] records since [since]. Returns raw bytes; parse with the
  /// functions in fetch.dart.
  /// [onProgress] gets (payload bytes so far, records the band announced).
  Future<FetchResult> fetch(
    FetchType type,
    DateTime since, {
    void Function(int bytes, int records)? onProgress,
  }) async {
    final control = await _notifications(BandUuids.fetchControl);
    final data = await _notifications(BandUuids.activityData);
    final asm = ChunkAssembler();
    var announced = 0;
    final dataSub = data.listen((p) {
      asm.add(p);
      onProgress?.call(asm.length, announced);
    });
    try {
      final replyF = control
          .map(FetchStartReply.parse)
          .firstWhere((r) => r != null)
          .timeout(_timeout);
      await _write(BandUuids.fetchControl, FetchCommands.start(type, since));
      final reply = (await replyF)!;
      if (!reply.ok || reply.count == 0 || reply.start == null) {
        _info(
          'fetch ${type.key}: nothing (ok=${reply.ok}, count=${reply.count})',
        );
        return FetchResult(type, null, Uint8List(0), 0, 0);
      }
      _info('fetch ${type.key}: ${reply.count} from ${reply.start}');
      announced = reply.count;
      onProgress?.call(0, announced);
      final doneF = control
          .map(parseTransferDone)
          .firstWhere((r) => r != null)
          .timeout(const Duration(minutes: 3));
      await _write(BandUuids.fetchControl, FetchCommands.transfer);
      final ok = (await doneF)!;
      if (!ok) throw BandException('fetch ${type.key}: band reported failure');
      final bytes = asm.take();
      _info('fetch ${type.key}: ${bytes.length}B, ${asm.gaps} sequence gaps');
      return FetchResult(type, reply.start, bytes, reply.count, asm.gaps);
    } finally {
      await dataSub.cancel();
    }
  }

  /// Workouts recorded on the band since [since], oldest first. The band
  /// hands out one summary per fetch, so this asks again from just after
  /// each one until it has nothing newer (at most [max]). Summaries that
  /// don't parse are skipped but still in the packet log.
  Future<List<BandWorkout>> fetchWorkouts(
    DateTime since, {
    int max = 30,
  }) async {
    final out = <BandWorkout>[];
    var from = since;
    for (var i = 0; i < max; i++) {
      final r = await fetch(FetchType.workouts, from);
      final start = r.start;
      if (start == null || r.data.isEmpty) break;
      final w = parseWorkoutSummary(r.data, start);
      if (w != null) out.add(w);
      final next = (w?.start ?? start).add(const Duration(seconds: 1));
      if (!next.isAfter(from)) break; // band repeated itself
      from = next;
    }
    return out;
  }

  /// Battery percent, or null if neither characteristic answers.
  Future<int?> readBattery() async {
    for (final (uuid, huami) in [
      (BandUuids.batteryLevel, false),
      (BandUuids.huamiBattery, true),
    ]) {
      final c = _chars[Guid(uuid).str128];
      if (c == null || !c.properties.read) continue;
      try {
        final v = await c.read();
        log.record(
          PacketEvent(
            dir: PacketDir.rx,
            characteristic: uuid,
            bytes: v,
            note: 'read',
          ),
        );
        final pct = parseBattery(v, huami: huami);
        if (pct != null) return pct;
      } catch (e) {
        _info('battery read $uuid failed: $e');
      }
    }
    return null;
  }

  /// Short vibration on the band. Silently skipped if unsupported.
  Future<void> buzz({bool strong = false}) async {
    if (!has(BandUuids.alertLevel)) {
      _info('buzz: no alert characteristic');
      return;
    }
    await _write(
      BandUuids.alertLevel,
      strong ? AlertCommands.high : AlertCommands.mild,
    );
  }

  /// Starts continuous HR measurement; emits BPM about once a second.
  Future<Stream<int>> startLiveHr() async {
    final raw = await _notifications(BandUuids.heartRateMeasurement);
    await _write(BandUuids.heartRateControlPoint, HrCommands.stopManual);
    await _write(BandUuids.heartRateControlPoint, HrCommands.stopContinuous);
    await _write(BandUuids.heartRateControlPoint, HrCommands.startContinuous);
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(HrCommands.keepAliveInterval, (_) {
      _write(
        BandUuids.heartRateControlPoint,
        HrCommands.keepAlive,
      ).catchError((Object e) => _info('keep-alive failed: $e'));
    });
    return raw
        .map(parseHeartRateMeasurement)
        .where((b) => b != null)
        .cast<int>();
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
    for (final c in _notify.values) {
      await c.close();
    }
    _notify.clear();
    _info('disconnect');
    await device.disconnect();
  }
}
