import 'dart:async';

import 'package:band_ble/band_ble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/band_link.dart';
import '../core/home_widgets.dart';
import '../core/key_store.dart';
import '../core/packet_file_log.dart';
import '../core/profile.dart';
import '../core/score_service.dart';
import '../core/sync_service.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';

enum PairStep {
  scan,
  select,
  key,
  authenticating,
  writing,
  success,
  wrongKey,
  notFound,
  busy,
}

/// Scan → select → key → authenticate → write band settings → first sync.
/// The auth key never leaves the phone (Keychain / Keystore).
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingState();
}

class _Prog {
  _Prog(this.label, {this.state = 0});
  final String label;

  /// 0 todo, 1 now, 2 done, 3 failed
  int state;
  String note = '';
}

class _PairingState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  final _keys = KeyStore();
  final _key = TextEditingController();
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();
  var _step = PairStep.scan;
  List<ScanResult> _found = [];
  ScanResult? _pick;
  bool _hasKey = false, _cancelled = false;
  StreamSubscription<List<ScanResult>>? _sub;
  Timer? _scanTimer;
  MiBand? _band;
  PacketFileLog? _log;
  final _prog = <_Prog>[];
  String _fw = '', _err = '';
  int? _battery;
  DateTime? _authStart;

  @override
  void initState() {
    super.initState();
    _keys
        .load()
        .then((k) => mounted ? setState(() => _hasKey = k != null) : null)
        .catchError((Object _) {});
    _scan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scanTimer?.cancel();
    _pulse.dispose();
    _key.dispose();
    FlutterBluePlus.stopScan().catchError((Object _) {});
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    final b = _band, l = _log;
    _band = null;
    _log = null;
    try {
      await b?.disconnect();
    } catch (_) {}
    await l?.close();
  }

  String get _hex => _key.text
      .replaceAll(RegExp(r'\s'), '')
      .replaceFirst(RegExp('^0[xX]'), '');
  bool get _validChars => RegExp(r'^[0-9a-fA-F]*$').hasMatch(_hex);
  bool get _keyOk => _validChars && _hex.length == 32;

  Future<void> _scan() async {
    setState(() {
      _step = PairStep.scan;
      _found = [];
      _cancelled = false;
    });
    try {
      final a = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
      );
      if (a != BluetoothAdapterState.on) {
        await requestBluetooth();
        if (await FlutterBluePlus.adapterState.first !=
            BluetoothAdapterState.on) {
          try {
            await FlutterBluePlus.turnOn();
          } catch (_) {}
        }
      }
      await _sub?.cancel();
      _sub = FlutterBluePlus.onScanResults.listen((rs) {
        if (!mounted) return;
        final bands =
            rs
                .where(
                  (r) => bandNameHints.any(
                    (h) =>
                        r.device.platformName.contains(h) ||
                        r.advertisementData.advName.contains(h),
                  ),
                )
                .toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi));
        setState(() => _found = bands);
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));
      // Move on as soon as something turns up and settles, else after 30 s.
      _scanTimer?.cancel();
      _scanTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        final scanning = FlutterBluePlus.isScanningNow;
        if (!mounted || _step != PairStep.scan) return t.cancel();
        if (_found.isNotEmpty && t.tick >= 6 || !scanning) {
          t.cancel();
          await FlutterBluePlus.stopScan();
          setState(() {
            _step = _found.isEmpty ? PairStep.notFound : PairStep.select;
            _pick = _found.isEmpty ? null : _found.first;
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _step = PairStep.notFound);
    }
  }

  void _selectDone() {
    if (_pick == null) return;
    if (_hasKey) {
      _connect();
    } else {
      setState(() => _step = PairStep.key);
    }
  }

  Future<void> _connect() async {
    if (!_hasKey) {
      try {
        await _keys.save(_key.text);
        _hasKey = true;
      } on FormatException {
        return;
      }
    }
    final device = _pick!.device;
    final db = ref.read(dbProvider);
    _prog
      ..clear()
      ..addAll([
        _Prog('Connected over Bluetooth', state: 1),
        _Prog('Verifying auth key'),
        _Prog('Writing band settings'),
        _Prog('First sync'),
      ]);
    setState(() => _step = PairStep.authenticating);
    _log = await PacketFileLog.open();
    final band = _band = MiBand(device, log: _log!);
    try {
      try {
        await band.connect();
      } catch (e) {
        _err = '$e';
        await _fail(PairStep.busy);
        return;
      }
      if (_cancelled) return;
      _fw = await band.readFirmware();
      if (_fw.isNotEmpty) await db.putSetting(Keys.firmware, _fw);
      _mark(0, 2);
      _mark(1, 1);
      _authStart = DateTime.now();
      try {
        await band.authenticate((await _keys.load())!);
      } on BandException catch (e) {
        _err = e.message;
        HapticFeedback.heavyImpact(); // warning: auth key invalid
        await _fail(
          e.message.contains('rejected') ? PairStep.wrongKey : PairStep.busy,
        );
        return;
      }
      if (_cancelled) return;
      _mark(
        1,
        2,
        note: '${DateTime.now().difference(_authStart!).inSeconds} s',
      );
      // Writing settings: show each sensor as it is turned on.
      final profile = await loadAppProfile(db) ?? const Profile();
      setState(() {
        _step = PairStep.writing;
        _prog
          ..clear()
          ..addAll([
            _Prog('Verified', state: 2),
            _Prog('Time, date and 24-hour clock'),
            _Prog('Heart rate every minute'),
            _Prog('Sleep detection with REM'),
            _Prog('Stress monitoring'),
            _Prog('First sync'),
          ]);
      });
      const order = ['time', 'hr interval', 'sleep assist', 'stress'];
      final every = int.tryParse(await db.setting(hrIntervalKey) ?? '') ?? 1;
      await band.configure(
        profile.band,
        hrEveryMinutes: every,
        sleepAssist: await db.setting(Keys.sleepAssist) != '0',
        stress: await db.setting(Keys.stressMonitor) != '0',
        wornLeft: profile.wornLeft,
        onStep: (name, {required done, ok = true}) {
          final i = order.indexOf(name);
          if (i < 0) return;
          _mark(
            i + 1,
            done ? (ok ? 2 : 3) : 1,
            note: done && !ok ? 'not confirmed' : '',
          );
        },
      );
      if (_cancelled) return;
      await saveAppProfile(db, profile);
      await db.putSetting(deviceIdKey, band.id);
      await db.putSetting(deviceNameKey, device.platformName);
      await db.putSetting(Keys.onboarded, '1');
      _battery = await band.readBattery();
      _mark(5, 1);
      final t0 = DateTime.now();
      final r = await SyncService(db).syncWith(
        band,
        onProgress: (read, total) {
          if (total > 0) _mark(5, 1, note: '${(100 * read / total).round()}%');
        },
      );
      await db.logSync(
        'First sync · ${r.minutes} min of data',
        'ok',
        took: DateTime.now().difference(t0),
      );
      _mark(5, 2);
      HapticFeedback.heavyImpact(); // success: band paired
      await _teardown();
      await afterSync(db);
      if (mounted) setState(() => _step = PairStep.success);
    } catch (e) {
      _err = '$e';
      _fail(PairStep.busy);
    }
  }

  void _mark(int i, int state, {String note = ''}) {
    if (!mounted || i >= _prog.length) return;
    setState(() {
      _prog[i].state = state;
      _prog[i].note = note;
    });
  }

  Future<void> _fail(PairStep s) async {
    await _teardown();
    if (mounted) setState(() => _step = s);
  }

  Future<void> _cancel() async {
    _cancelled = true;
    await _teardown();
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final top = MediaQuery.of(context).padding.top,
        bottom = MediaQuery.of(context).padding.bottom;
    final (stepNo, title, body) = switch (_step) {
      PairStep.scan => (
        '1 / 4',
        'Looking for your band',
        'Keep your Mi Band 6 within a metre and tap its screen to wake it.',
      ),
      PairStep.select => (
        '1 / 4',
        _found.length == 1 ? 'Found your band' : 'Found ${_found.length} bands',
        'Pick yours. Stronger signal is usually the one on your wrist.',
      ),
      PairStep.key => (
        '2 / 4',
        'Paste your auth key',
        'Your band only talks to apps that know its 32-character key. You get it once from the official app; Tempo keeps it on this phone.',
      ),
      PairStep.authenticating => (
        '3 / 4',
        'Connecting',
        'Keep the band close. This takes about 20 seconds.',
      ),
      PairStep.writing => (
        '3 / 4',
        'Setting up your band',
        'Tempo is turning on the sensors it needs. Your watch face and alarms are untouched.',
      ),
      PairStep.success => (
        '4 / 4',
        'You’re paired',
        'Wear it tonight — your first sleep and recovery arrive tomorrow morning. Calibration takes 14 nights.',
      ),
      PairStep.wrongKey => (
        '2 / 4',
        'The band rejected that key',
        'The format was right, but it isn’t this band’s key.',
      ),
      PairStep.notFound => (
        '1 / 4',
        'No band found',
        'Tempo searched for 30 seconds and didn’t see a Mi Band 6.',
      ),
      PairStep.busy => (
        '3 / 4',
        'Band is busy with another app',
        'Only one app can talk to the band at a time.',
      ),
    };
    final (cta, onCta, sec, onSec) = switch (_step) {
      PairStep.scan => (
        'Searching…',
        null,
        'Having trouble?',
        () => _tips(context),
      ),
      PairStep.select => (
        'Use this band',
        _pick == null ? null : _selectDone,
        null,
        null,
      ),
      PairStep.key => ('Connect', _keyOk ? _connect : null, null, null),
      PairStep.authenticating => ('Connecting…', null, 'Cancel', _cancel),
      PairStep.writing => ('Setting up…', null, null, null),
      PairStep.success => (
        'Go to Today',
        () => Navigator.of(context).popUntil((r) => r.isFirst),
        null,
        null,
      ),
      PairStep.wrongKey => (
        'Edit key',
        () async {
          await _keys.clear();
          setState(() {
            _hasKey = false;
            _step = PairStep.key;
          });
        },
        'Try again',
        _connect,
      ),
      PairStep.notFound => ('Search again', _scan, null, null),
      PairStep.busy => ('Try again', _connect, null, null),
    };
    final tips = switch (_step) {
      PairStep.wrongKey => [
        'Keys change whenever the band is reset or re-paired. Fetch it again from the official app.',
        if (_pick != null)
          'Make sure the key is for the band ending in ${_tail(_pick!)}.',
        'Copy all 32 characters — spaces are ignored.',
      ],
      PairStep.notFound => [
        'Wake the band by tapping its screen.',
        'Check it’s charged and within a metre.',
        'If it’s paired to another phone nearby, switch that phone’s Bluetooth off.',
      ],
      PairStep.busy => [
        'Close Mi Fitness / Zepp Life, or turn off its Bluetooth permission.',
        'Wait 10 seconds for the band to let go.',
        'Tap Try again. Tempo will hold the connection from now on.',
      ],
      _ => <String>[],
    };

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, top + 12, 10, 0),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  TempoIconButton(
                    TempoIcons.back,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Pair your band',
                        style: TempoType.label.c(c.text1),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      stepNo,
                      textAlign: TextAlign.center,
                      style: TempoType.caption.c(c.text3).tnum,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              children: [
                SizedBox(height: 200, child: Center(child: _art(context))),
                const SizedBox(height: 24),
                Text(title, style: TempoType.pageTitle.c(c.text1)),
                const SizedBox(height: 8),
                Text(body, style: TempoType.body.c(c.text2)),
                const SizedBox(height: 24),
                if (_step == PairStep.select) ...[
                  for (final r in _found) ...[
                    Pressable(
                      selected: r == _pick,
                      label: 'Mi Smart Band 6 ending in ${_tail(r)}',
                      onTap: () => setState(() => _pick = r),
                      child: AnimatedContainer(
                        duration: TempoMotion.fast,
                        constraints: const BoxConstraints(minHeight: 68),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface1,
                          borderRadius: BorderRadius.circular(TempoRadii.lg),
                          border: Border.all(
                            color: r == _pick ? c.text1 : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.device.platformName.isEmpty
                                        ? 'Mi Smart Band 6'
                                        : r.device.platformName,
                                    style: TempoType.label.copyWith(
                                      fontSize: 15,
                                      color: c.text1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'ends in ${_tail(r)} · ${r.rssi > -70
                                        ? 'strong'
                                        : r.rssi > -85
                                        ? 'fair'
                                        : 'weak'} signal',
                                    style: TempoType.caption.copyWith(
                                      fontFamily: TempoType.mono,
                                      color: c.text2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _Signal(
                              bars: r.rssi > -60
                                  ? 4
                                  : r.rssi > -70
                                  ? 3
                                  : r.rssi > -85
                                  ? 2
                                  : 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Check the last characters on the band: Settings › About.',
                    style: TempoType.bodyS.c(c.text3),
                  ),
                ],
                if (_step == PairStep.key) ...[
                  TempoField(
                    label: 'Auth key',
                    controller: _key,
                    mono: true,
                    error:
                        _hex.isNotEmpty &&
                        !_keyOk &&
                        (!_validChars || _hex.length > 32),
                    onChanged: (_) => setState(() {}),
                    trailing: TempoButton(
                      'Paste',
                      small: true,
                      kind: ButtonKind.secondary,
                      onTap: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        if (d?.text == null) return;
                        final h = d!.text!
                            .replaceAll(RegExp(r'\s'), '')
                            .replaceFirst(RegExp('^0[xX]'), '');
                        _key.text = [
                          for (var i = 0; i < h.length; i += 4)
                            h.substring(i, (i + 4).clamp(0, h.length)),
                        ].join(' ');
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hex.isEmpty
                        ? 'Spaces are ignored.'
                        : _keyOk
                        ? '✓ 32 hex characters — format looks right'
                        : !_validChars
                        ? '⚠ Keys use 0–9 and a–f only.'
                        : '⚠ ${_hex.length} of 32 characters. Keys use 0–9 and a–f only.',
                    style: TempoType.caption.c(
                      _hex.isEmpty || _keyOk ? c.text2 : s.recLow,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < 32; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i < _hex.length.clamp(0, 32)
                                  ? (_keyOk ? c.text1 : s.recLow)
                                  : c.trackOff,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Pressable(
                    onTap: () => _whereKey(context),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          TempoIcon(TempoIcons.info, size: 18, color: c.text1),
                          const SizedBox(width: 8),
                          Text(
                            'Where do I find my key?',
                            style: TempoType.label.c(c.text1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_step == PairStep.authenticating ||
                    _step == PairStep.writing)
                  CardList(
                    children: [
                      for (final p in _prog)
                        SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  child: p.state == 1
                                      ? RotationTransition(
                                          turns: _pulse,
                                          child: TempoIcon(
                                            TempoIcons.spinner,
                                            size: 18,
                                            color: c.text1,
                                            stroke: 2.25,
                                          ),
                                        )
                                      : TempoIcon(
                                          p.state == 2
                                              ? TempoIcons.check
                                              : p.state == 3
                                              ? TempoIcons.alert
                                              : TempoIcons.dot,
                                          size: 18,
                                          color: p.state == 0
                                              ? c.text3
                                              : c.text1,
                                          stroke: 2.25,
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    p.label,
                                    style: TempoType.body.c(
                                      p.state == 0 ? c.text3 : c.text1,
                                    ),
                                  ),
                                ),
                                Text(
                                  p.note,
                                  style: TempoType.caption.c(c.text3).tnum,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_step == PairStep.success)
                  TempoCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Stat(
                            'Battery',
                            _battery == null ? '—' : '$_battery%',
                          ),
                        ),
                        Expanded(
                          child: Stat(
                            'Firmware',
                            _fw.isEmpty
                                ? '—'
                                : _fw.split(' / ').last.replaceFirst('V', ''),
                            valueStyle: TempoType.label.copyWith(
                              fontSize: 15,
                              height: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Stat(
                            'HR',
                            'Every min',
                            valueStyle: TempoType.label.copyWith(
                              fontSize: 15,
                              height: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (tips.isNotEmpty)
                  CardList(
                    children: [
                      for (final (i, t) in tips.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 14,
                                child: Text(
                                  '${i + 1}',
                                  style: TempoType.label.c(c.text3),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  t,
                                  style: TempoType.bodyS.c(c.text1),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (_err.isNotEmpty &&
                    (_step == PairStep.busy || _step == PairStep.wrongKey)) ...[
                  const SizedBox(height: 12),
                  Text('Detail: $_err', style: TempoType.caption.c(c.text3)),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
            child: Column(
              children: [
                TempoButton(cta, expand: true, onTap: onCta),
                if (sec != null) ...[
                  const SizedBox(height: 4),
                  TempoButton(
                    sec,
                    kind: ButtonKind.text,
                    expand: true,
                    onTap: onSec,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _tail(ScanResult r) {
    final id = r.device.remoteId.str.replaceAll(':', '').replaceAll('-', '');
    return id.length < 2 ? id : id.substring(id.length - 2).toUpperCase();
  }

  Widget _art(BuildContext context) {
    final c = context.c;
    final band = Container(
      width: 44,
      height: 104,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.lineStrong, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 26,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F2EF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
    switch (_step) {
      case PairStep.scan:
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Stack(
            alignment: Alignment.center,
            children: [
              for (final (i, (d, col, w)) in [
                (196.0, c.line, 1.0),
                (140.0, c.lineStrong, 1.0),
                (90.0, c.text3, 1.5),
              ].indexed)
                Opacity(
                  opacity: context.reduceMotion
                      ? 1
                      : (.4 + .6 * ((1 - ((_pulse.value + i / 3) % 1)))).clamp(
                          0,
                          1,
                        ),
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: col, width: w),
                    ),
                  ),
                ),
              child!,
            ],
          ),
          child: band,
        );
      case PairStep.success:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: c.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: c.lineStrong, width: 1.5),
          ),
          alignment: Alignment.center,
          child: const TempoMark(size: 56),
        );
      case PairStep.wrongKey || PairStep.notFound || PairStep.busy:
        return Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: c.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: c.lineStrong, width: 1.5),
          ),
          alignment: Alignment.center,
          child: TempoIcon(
            _step == PairStep.wrongKey
                ? TempoIcons.alert
                : _step == PairStep.notFound
                ? TempoIcons.search
                : TempoIcons.link,
            size: 40,
            color: c.text1,
            stroke: 1.5,
          ),
        );
      default:
        return band;
    }
  }

  void _tips(BuildContext context) => showTempoSheet<void>(
    context,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Having trouble?', style: TempoType.titleL.c(ctx.c.text1)),
        const SizedBox(height: 12),
        for (final t in [
          'Wake the band by tapping its screen.',
          'Check it’s charged and within a metre.',
          'Force-stop Mi Fitness / Zepp Life: only one app can hold the band.',
          'If it’s paired to another phone nearby, switch that phone’s Bluetooth off.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('· $t', style: TempoType.body.c(ctx.c.text2)),
          ),
      ],
    ),
  );

  void _whereKey(BuildContext context) => showTempoSheet<void>(
    context,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where do I find my key?', style: TempoType.titleL.c(ctx.c.text1)),
        const SizedBox(height: 12),
        Text(
          'Pair the band once with Mi Fitness or Zepp Life, then extract the 32-character key (for example with the open-source huami-token script, or from Mi Fitness logs on Android).\n\nDon’t remove the band inside Mi Fitness afterwards — a reset makes a new key. Force-stop or uninstall the app instead.',
          style: TempoType.body.c(ctx.c.text2),
        ),
        const SizedBox(height: 16),
        const PrivacyNote(
          'Tempo stores the key only in this phone’s keychain.',
        ),
      ],
    ),
  );
}

class _Signal extends StatelessWidget {
  const _Signal({required this.bars});
  final int bars;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 16,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 4,
            height: 5.0 + i * 3.7,
            decoration: BoxDecoration(
              color: i < bars ? context.c.text1 : context.c.trackOff,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ],
    ),
  );
}
