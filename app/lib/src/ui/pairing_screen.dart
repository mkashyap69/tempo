import 'dart:async';

import 'package:band_ble/band_ble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/band_link.dart';
import '../core/key_store.dart';
import '../core/packet_file_log.dart';
import '../core/profile.dart';
import '../core/sync_service.dart';
import 'providers.dart';

/// Scan → key → profile → authenticate → write band settings → first sync.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _keys = KeyStore();
  final _key = TextEditingController();
  final _birthYear = TextEditingController(text: '1990');
  final _height = TextEditingController(text: '175');
  final _weight = TextEditingController(text: '70');
  bool _male = true;
  bool _hasKey = false;
  bool _scanning = false, _busy = false;
  List<ScanResult> _results = [];
  final _lines = <String>[];
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _keys
        .load()
        .then((k) => setState(() => _hasKey = k != null))
        .catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_key, _birthYear, _height, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String s) => setState(() => _lines.add(s));

  Future<void> _scan() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _say('Bluetooth is off.');
      return;
    }
    setState(() {
      _scanning = true;
      _results = [];
    });
    await _sub?.cancel();
    _sub = FlutterBluePlus.onScanResults.listen((rs) {
      int rank(ScanResult r) =>
          bandNameHints.any((h) => r.device.platformName.contains(h)) ? 0 : 1;
      setState(() {
        _results = rs.where((r) => r.device.platformName.isNotEmpty).toList()
          ..sort((a, b) => rank(a).compareTo(rank(b)));
      });
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _pair(BluetoothDevice device) async {
    final db = ref.read(dbProvider);
    if (!_hasKey) {
      try {
        await _keys.save(_key.text);
        _key.clear();
        setState(() => _hasKey = true);
      } on FormatException catch (e) {
        _say(e.message);
        return;
      }
    }
    final profile = UserProfile(
      birthDate: DateTime(int.tryParse(_birthYear.text) ?? 1990),
      heightCm: int.tryParse(_height.text) ?? 175,
      weightKg: double.tryParse(_weight.text) ?? 70,
      male: _male,
    );
    await FlutterBluePlus.stopScan();
    setState(() => _busy = true);
    final log = await PacketFileLog.open();
    final band = MiBand(device, log: log);
    try {
      _say('Connecting to ${device.platformName}…');
      await band.connect();
      _say('Firmware: ${await band.readFirmware()}');
      final variant = await band.authenticate((await _keys.load())!);
      _say('Authenticated (${variant.name}).');
      final failed = await band.configure(profile);
      _say(
        failed.isEmpty
            ? 'Band settings written.'
            : 'Settings not written: ${failed.join(', ')}',
      );
      await saveProfile(db, profile);
      await db.putSetting(deviceIdKey, band.id);
      await db.putSetting(deviceNameKey, device.platformName);
      _say('First sync (last 7 days)…');
      final r = await SyncService(db).syncWith(band);
      _say('Synced: $r');
      await band.disconnect();
      ref.invalidate(pairedProvider);
    } catch (e) {
      _say('Failed: $e');
      try {
        await band.disconnect();
      } catch (_) {}
    } finally {
      await log.close();
      _say('Packet log: ${log.file.path}');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair your band')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Force-stop Mi Fitness / Zepp Life first: only one app can hold the band.',
          ),
          const SizedBox(height: 12),
          if (!_hasKey)
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Auth key (32 hex digits)',
              ),
            )
          else
            const Text('Auth key stored in secure storage.'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _birthYear,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Birth year'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Height cm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight kg'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Male'),
            value: _male,
            onChanged: (v) => setState(() => _male = v),
          ),
          FilledButton(
            onPressed: _scanning || _busy ? null : _scan,
            child: Text(_scanning ? 'Scanning…' : 'Scan'),
          ),
          for (final r in _results)
            ListTile(
              title: Text(r.device.platformName),
              subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm'),
              onTap: _busy ? null : () => _pair(r.device),
            ),
          const Divider(),
          for (final l in _lines) Text(l),
        ],
      ),
    );
  }
}
