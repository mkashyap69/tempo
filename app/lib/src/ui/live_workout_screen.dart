import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import 'format.dart';
import 'providers.dart';
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
        // Per-minute TRIMP, pro-rated by seconds since the previous reading.
        if (_last != null) {
          final dt = now.difference(_last!).inMilliseconds / 60000;
          _trimp +=
              sc.minuteTrimp(bpm, hrRest: _rest, hrMax: _max) *
              dt.clamp(0, 0.1);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Live workout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              _bpm?.toString() ?? '--',
              style: Theme.of(context).textTheme.displayLarge
                  ?.copyWith(color: zoneColours[zone]),
            ),
          ),
          Center(
            child: Text(
              'bpm · ${zone == 0 ? 'below zones' : 'zone $zone'} · $_status',
            ),
          ),
          const SizedBox(height: 16),
          Section('Session', [
            Kv('Elapsed', '${elapsed.inMinutes} min'),
            Kv('Strain gained (estimate)', n1(sc.strainFromTrimp(_trimp))),
          ]),
          Section('Heart rate', [
            SimpleLine(
              points: List.of(_points),
              color: Colors.red,
              xLabel: (m) => '${m.round()}m',
            ),
          ]),
          const Text(
            'Keep this screen open. Wrist HR lags in intervals and lifting.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
