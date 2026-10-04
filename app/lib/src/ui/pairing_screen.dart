import 'dart:async';

import 'package:band_ble/band_ble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/band_link.dart';
import '../core/key_store.dart';
import '../core/packet_file_log.dart';
import '../core/profile.dart';
import '../core/score_service.dart';
import '../core/sync_service.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

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
      final every = int.tryParse(await db.setting(hrIntervalKey) ?? '') ?? 1;
      final failed = await band.configure(profile, hrEveryMinutes: every);
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
      appBar: AppBar(
        title: const Text(
          'Pair Mi Band 6',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Athlete Profile',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tempo calculates Heart Rate Reserve (HRR) and Banister TRIMP on-device.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 16),
                if (!_hasKey) ...[
                  TextField(
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Auth key (32 hex digits)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Color(0xFF16A34A),
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Auth key loaded from secure storage',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _birthYear,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Birth year',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _height,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Height cm',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _weight,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Weight kg',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Male (affects TRIMP factor)'),
                  value: _male,
                  onChanged: (v) => setState(() => _male = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hardware Discovery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Force-stop Mi Fitness / Zepp Life first: only one app can hold the band.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _scanning || _busy ? null : _scan,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(_scanning ? 'Scanning…' : 'Scan for Band'),
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final r in _results)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: r.device.platformName.contains('Band')
                              ? accent
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        title: Text(
                          r.device.platformName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${r.device.remoteId.str} · ${r.rssi} dBm',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _busy ? null : () => _pair(r.device),
                          child: const Text('Connect'),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 14),
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Console Logs',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final l in _lines)
                    Text(
                      l,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
