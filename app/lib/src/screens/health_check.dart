import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_source/health_source.dart';

import '../core/data_source.dart';
import '../core/format.dart';
import '../core/health_check.dart';
import '../core/health_reader.dart';
import '../core/health_sync.dart' show sourceLabel, sourceNames;
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// Profile → Developer → Health data check: reads the last 7 days straight
/// from Apple Health / Health Connect and lines it up, kind by kind, with
/// what Tempo stored. Read-only on both sides.
class HealthCheckScreen extends ConsumerStatefulWidget {
  const HealthCheckScreen({super.key, this.reader});

  /// Tests pass a fake; the app reads through the plugin.
  final HealthReader? reader;

  @override
  ConsumerState<HealthCheckScreen> createState() => _HealthCheckState();
}

class _HealthCheckState extends ConsumerState<HealthCheckScreen> {
  bool _running = false;
  String? _error;
  HealthCheckReport? _report;
  DataSource? _source;
  Map<String, String> _names = const {};

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    final db = ref.read(dbProvider);
    try {
      final source = await loadDataSource(db);
      if (!source.isHealth) {
        throw StateError('Tempo reads the band, not Health, on this phone.');
      }
      final r = await checkHealth(db, widget.reader ?? PluginHealthReader());
      final names = await sourceNames(db);
      if (mounted) {
        setState(() {
          _report = r;
          _source = source;
          _names = names;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copy() async {
    final r = _report, s = _source;
    if (r == null || s == null) return;
    await Clipboard.setData(ClipboardData(text: r.text(s.label, _names)));
    if (mounted) showTempoToast(context, 'Copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _report;
    return TempoPage(
      gap: 16,
      bottom: 48,
      children: [
        const DetailHeader(title: 'Health data check'),
        Text(
          'Reads the last 7 days straight from Health and compares every kind with what Tempo stored. Nothing is written, here or in Health.',
          style: TempoType.body.c(c.text1),
        ),
        if (_error != null)
          StatusBanner(
            icon: TempoIcons.alert,
            title: 'Check stopped',
            body: _error!,
            action: 'Retry',
            onAction: _run,
          ),
        if (r != null) ...[
          _Summary(report: r),
          CardList(
            children: [
              for (final (i, k) in r.kinds.indexed) ...[
                if (i > 0) const Hair(),
                _KindRow(check: k, names: _names),
              ],
            ],
          ),
        ],
        if (_running)
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          TempoButton(
            r == null ? 'Run check' : 'Run again',
            expand: true,
            kind: r == null ? ButtonKind.primary : ButtonKind.secondary,
            onTap: _run,
          ),
          if (r != null) TempoButton('Copy report', expand: true, onTap: _copy),
        ],
        Text(
          '“Newer” records were written after Tempo’s last read; the next read picks them up. “Dropped” are ones Tempo skips on purpose: its own, longer than a day, or without a number.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report});
  final HealthCheckReport report;
  @override
  Widget build(BuildContext context) {
    final r = report;
    final bad = r.kinds
        .where(
          (k) => k.verdict != KindVerdict.ok && k.verdict != KindVerdict.empty,
        )
        .length;
    final empty = r.kinds.where((k) => k.verdict == KindVerdict.empty).length;
    final read = r.lastRead == null
        ? 'Tempo hasn’t read Health yet.'
        : 'Last read ${dayShort(r.lastRead!)} ${clockOf(r.lastRead!)}.';
    if (!r.access) {
      return StatusBanner(
        icon: TempoIcons.alert,
        title: 'No access',
        body: 'Health says Tempo can’t read it. $read',
      );
    }
    return StatusBanner(
      icon: bad == 0 ? TempoIcons.check : TempoIcons.alert,
      title: bad == 0
          ? 'Everything Health has is in Tempo'
          : '$bad ${bad == 1 ? 'kind needs' : 'kinds need'} a look',
      body:
          '$read ${empty == 0 ? 'Every kind has data.' : '$empty with no data in Health this week.'}',
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({required this.check, required this.names});
  final KindCheck check;
  final Map<String, String> names;

  static String _name(HealthKind k) => switch (k) {
    HealthKind.heartRate => 'Heart rate',
    HealthKind.steps => 'Steps',
    HealthKind.sleepInBed => 'Sleep · in bed',
    HealthKind.sleepSession => 'Sleep · session',
    HealthKind.sleepAsleep => 'Sleep · asleep',
    HealthKind.sleepAwake => 'Sleep · awake',
    HealthKind.sleepLight => 'Sleep · light / core',
    HealthKind.sleepDeep => 'Sleep · deep',
    HealthKind.sleepRem => 'Sleep · REM',
    HealthKind.hrvSdnn => 'HRV · SDNN',
    HealthKind.hrvRmssd => 'HRV · RMSSD',
    HealthKind.restingHr => 'Resting heart rate',
    HealthKind.spo2 => 'Blood oxygen',
    HealthKind.workout => 'Workouts',
    HealthKind.respiratoryRate => 'Respiratory rate',
    HealthKind.water => 'Water',
    HealthKind.caffeine => 'Caffeine',
    HealthKind.wristTemp => 'Night temperature',
  };

  static String _verdict(KindVerdict v) => switch (v) {
    KindVerdict.ok => 'OK',
    KindVerdict.empty => 'No data',
    KindVerdict.missing => 'Missing',
    KindVerdict.extra => 'Extra',
    KindVerdict.odd => 'Odd values',
    KindVerdict.failed => 'Read failed',
  };

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final k = check;
    final warn = k.verdict != KindVerdict.ok && k.verdict != KindVerdict.empty;
    final lines = <String>[
      if (k.error != null)
        k.error!
      else if (k.verdict != KindVerdict.empty) ...[
        [
          'Health ${k.inHealth}',
          'stored ${k.stored}',
          if (k.newer > 0) '${k.newer} newer',
          if (k.dropped > 0) '${k.dropped} dropped',
          if (k.missing > 0) '${k.missing} missing',
          if (k.extra > 0) '${k.extra} extra',
          if (k.odd > 0) '${k.odd} odd',
        ].join(' · '),
        [
          if (k.min != null) 'Range ${_n(k.min!)}–${_n(k.max!)}',
          if (k.latest != null)
            'latest ${dayShort(k.latest!)} ${clockOf(k.latest!)}',
        ].join(' · '),
        if (k.sources.isNotEmpty)
          [
            for (final e in k.sources.entries)
              '${sourceLabel(e.key, names)} ${e.value}',
          ].join(' · '),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_name(k.kind), style: TempoType.label.c(c.text1)),
              ),
              TempoBadge(
                _verdict(k.verdict),
                small: true,
                color: warn ? context.s.recLow : null,
              ),
            ],
          ),
          for (final l in lines)
            if (l.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l, style: TempoType.caption.c(c.text2).tnum),
              ),
        ],
      ),
    );
  }
}
