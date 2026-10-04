import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import 'format.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Real-time HR from the band, written to hr_live; zone and strain gained.
class LiveWorkoutScreen extends ConsumerStatefulWidget {
  const LiveWorkoutScreen({super.key});
  @override
  ConsumerState<LiveWorkoutScreen> createState() => _LiveWorkoutState();
}

class _LiveWorkoutState extends ConsumerState<LiveWorkoutScreen> {
  BandLink? _link;
  StreamSubscription<int>? _sub;
  String _status = 'Connecting…';
  int? _bpm;
  double _trimp = 0;
  DateTime? _started, _last;
  final _points = <FlSpot>[];
  double _rest = 60, _max = 190;
  final Map<int, int> _zoneSeconds = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final db = ref.read(dbProvider);
    final recent = await db.scoresBefore(
      dayOf(DateTime.now()).add(const Duration(days: 1)),
      limit: 1,
    );
    if (recent.isNotEmpty) {
      _rest = recent.first.rhr ?? 60;
      _max = recent.first.hrMax.toDouble();
    }
    try {
      final link = _link = await BandLink.open(db);
      final hr = await link.band.startLiveHr();
      _started = DateTime.now();
      if (mounted) setState(() => _status = 'Live');
      _sub = hr.listen((bpm) {
        final now = DateTime.now();
        if (_last != null) {
          final dt = now.difference(_last!).inMilliseconds / 60000;
          _trimp +=
              sc.minuteTrimp(bpm, hrRest: _rest, hrMax: _max) *
              dt.clamp(0, 0.1);
          final z = zoneFor(bpm, _rest, _max);
          if (z >= 1 && z <= 5) {
            _zoneSeconds[z] =
                (_zoneSeconds[z] ?? 0) + now.difference(_last!).inSeconds;
          }
        }
        _last = now;
        db.appendHrLive(st.toTs(now), bpm);
        if (mounted) {
          setState(() {
            _bpm = bpm;
            _points.add(
              FlSpot(now.difference(_started!).inSeconds / 60, bpm.toDouble()),
            );
            if (_points.length > 1800) _points.removeAt(0);
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    final link = _link;
    if (link != null) {
      link.band.stopLiveHr().catchError((_) {}).whenComplete(link.close);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zone = _bpm == null ? 0 : zoneFor(_bpm!, _rest, _max);
    final elapsed = _started == null
        ? Duration.zero
        : DateTime.now().difference(_started!);
    final sessionStrain = sc.strainFromTrimp(_trimp);
    final totalZoneSeconds = _zoneSeconds.values
        .fold<int>(0, (a, b) => a + b)
        .clamp(1, 1000000);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Live Session',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFFEAE3),
                foregroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'End',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // 1. Hero Pulsing Heart Rate Box (Mockup Screen 3 style)
          SoftCard(
            blob: true,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                SizedBox.square(
                  dimension: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow blob
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.35),
                              accent.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                      // Outer Progress Arc based on HR reserve
                      CircularProgressIndicator(
                        value: _bpm == null
                            ? 0.0
                            : ((_bpm! - _rest) / (_max - _rest)).clamp(
                                0.05,
                                1.0,
                              ),
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFFF0F0F5),
                        valueColor: AlwaysStoppedAnimation(zoneColours[zone]),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _bpm?.toString() ?? '–',
                            style: const TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                              color: ink,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'BPM LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  zone == 0 ? 'Below Training Zones' : 'Zone $zone · Threshold',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: zoneColours[zone],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1 Hz continuous stream · $_status',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Dual Strain & Time Cards
          Row(
            children: [
              Expanded(
                child: SoftCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Session Strain',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n1(sessionStrain),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Banister TRIMP',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SoftCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Duration',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Active time',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. Heart Rate Reserve Zone Stack
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heart Rate Reserve (HRR) Distribution',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 14),
                for (int z = 5; z >= 1; z--) ...[
                  _ZoneRow(
                    name: 'Zone $z',
                    color: zoneColours[z],
                    fraction: (_zoneSeconds[z] ?? 0) / totalZoneSeconds,
                  ),
                  if (z > 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.name,
    required this.color,
    required this.fraction,
  });
  final String name;
  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFF1F1F5),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            '${(fraction * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ],
    );
  }
}
