import 'dart:async';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'key_store.dart';
import 'packet_file_log.dart';

enum Phase { idle, scanning, connecting, authenticating, live, error }

class SpikeState {
  const SpikeState({
    this.phase = Phase.idle,
    this.hasKey = false,
    this.results = const [],
    this.bpm,
    this.lines = const [],
    this.logPath,
  });

  final Phase phase;
  final bool hasKey;
  final List<ScanResult> results;
  final int? bpm;
  final List<String> lines;
  final String? logPath;

  SpikeState copyWith({
    Phase? phase,
    bool? hasKey,
    List<ScanResult>? results,
    int? bpm,
    List<String>? lines,
    String? logPath,
  }) => SpikeState(
    phase: phase ?? this.phase,
    hasKey: hasKey ?? this.hasKey,
    results: results ?? this.results,
    bpm: bpm ?? this.bpm,
    lines: lines ?? this.lines,
    logPath: logPath ?? this.logPath,
  );
}

final spikeProvider = NotifierProvider<SpikeController, SpikeState>(
  SpikeController.new,
);

class SpikeController extends Notifier<SpikeState> {
  final _keys = KeyStore();
  AuthKey? _key;
  MiBand? _band;
  PacketFileLog? _log;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<int>? _hrSub;

  @override
  SpikeState build() {
    ref.onDispose(_teardown);
    _loadKey();
    return const SpikeState();
  }

  void _say(String line) =>
      state = state.copyWith(lines: [...state.lines, line]);

  Future<void> _loadKey() async {
    try {
      _key = await _keys.load();
      state = state.copyWith(hasKey: _key != null);
    } on FormatException catch (e) {
      _say('Stored key invalid: ${e.message}');
    }
  }

  Future<void> saveKey(String input) async {
    try {
      _key = await _keys.save(input);
      state = state.copyWith(hasKey: true);
      _say('Key saved to secure storage.');
    } on FormatException catch (e) {
      _say(e.message);
    }
  }

  Future<void> forgetKey() async {
    await _keys.clear();
    _key = null;
    state = state.copyWith(hasKey: false);
  }

  Future<void> scan() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _say('Bluetooth is off.');
      return;
    }
    state = state.copyWith(phase: Phase.scanning, results: []);
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((rs) {
      // Show named devices; band-looking names first.
      final named = rs.where((r) => r.device.platformName.isNotEmpty).toList()
        ..sort((a, b) => _rank(a).compareTo(_rank(b)));
      state = state.copyWith(results: named);
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    if (state.phase == Phase.scanning) {
      state = state.copyWith(phase: Phase.idle);
    }
  }

  int _rank(ScanResult r) =>
      bandNameHints.any((h) => r.device.platformName.contains(h)) ? 0 : 1;

  Future<void> connect(BluetoothDevice device) async {
    final key = _key;
    if (key == null) {
      _say('Enter the auth key first.');
      return;
    }
    await FlutterBluePlus.stopScan();
    await _teardown();
    _log = await PacketFileLog.open();
    state = state.copyWith(phase: Phase.connecting, logPath: _log!.file.path);
    final band = _band = MiBand(device, log: _log!);
    try {
      _say('Connecting to ${device.platformName}…');
      await band.connect();
      _say('Firmware: ${await band.readFirmware()}');
      state = state.copyWith(phase: Phase.authenticating);
      final variant = await band.authenticate(key);
      _say('Authenticated (${variant.name} protocol).');
      final hr = await band.startLiveHr();
      state = state.copyWith(phase: Phase.live);
      _say('Live HR started. Waiting for readings…');
      _hrSub = hr.listen((bpm) => state = state.copyWith(bpm: bpm));
    } catch (e) {
      _say('Failed: $e');
      state = state.copyWith(phase: Phase.error);
      await _teardown();
    }
  }

  Future<void> disconnect() async {
    await _teardown();
    state = state.copyWith(phase: Phase.idle);
    _say('Disconnected. Log: ${state.logPath}');
  }

  Future<void> _teardown() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _hrSub?.cancel();
    _hrSub = null;
    final band = _band;
    _band = null;
    if (band != null) {
      try {
        await band.stopLiveHr();
      } catch (_) {}
      try {
        await band.disconnect();
      } catch (_) {}
    }
    await _log?.close();
    _log = null;
  }
}
