import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_source/health_source.dart';
import 'package:share_plus/share_plus.dart';

import '../core/data_source.dart';
import '../core/format.dart';
import '../core/health_check.dart';
import '../core/health_reader.dart';
import '../core/health_sync.dart' show SourceMetric, sourceLabel, sourceNames;
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';

/// Profile → Developer → Health data check: reads the last 7 days straight
/// from Apple Health / Health Connect and lines it up, kind by kind, with
/// what Tempo stored, then follows last night and today through to the
/// minutes and scores. Read-only on both sides.
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

  String? get _text => _report?.text(_source!.label, _names);

  Future<void> _copy() async {
    final t = _text;
    if (t == null) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) showTempoToast(context, 'Copied');
  }

  Future<void> _save() async {
    final t = _text;
    if (t == null) return;
    final f = await saveHealthCheck(t, at: _report!.to);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Tempo ${_source!.label} data check',
        files: [XFile(f.path, mimeType: 'text/plain')],
      ),
    );
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
          'Reads the last 7 days straight from Health and compares every kind with what Tempo stored, then follows last night and today through to the scores. Nothing is written, here or in Health.',
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
          if (r.permissions case final p?)
            _Permissions(
              permissions: p,
              kinds: [for (final k in r.kinds) k.kind],
            ),
          if (r.pipeline case final q?) _Pipeline(check: q, names: _names),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Overline('Last 7 days · tap a kind for its records'),
          ),
          CardList(
            children: [
              for (final (i, k) in r.kinds.indexed) ...[
                if (i > 0) const Hair(),
                _KindRow(
                  check: k,
                  names: _names,
                  onTap: k.recent.isEmpty
                      ? null
                      : () => push(
                          context,
                          HealthRecordsScreen(check: k, names: _names),
                        ),
                ),
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
          if (r != null) ...[
            TempoButton('Save report', expand: true, onTap: _save),
            TempoButton(
              'Copy report',
              expand: true,
              kind: ButtonKind.secondary,
              onTap: _copy,
            ),
          ],
        ],
        Text(
          '“Newer” records were written after Tempo’s last read; the next read picks them up. “Dropped” are ones Tempo skips on purpose: its own, longer than a day, or without a number. Saved reports stay in Tempo’s folder on this phone until you share them.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

String kindName(HealthKind k) => switch (k) {
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

String _when(DateTime t) => '${dayShort(t)} ${clockOf(t)}';

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
        : 'Last read ${_when(r.lastRead!)}.';
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

/// A titled card of key–value lines.
class _Facts extends StatelessWidget {
  const _Facts({required this.title, required this.rows, this.note});
  final String title;
  final List<(String, String)> rows;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Overline(title),
        ),
        const SizedBox(height: 8),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(k, style: TempoType.bodyS.c(c.text2)),
                      ),
                      Expanded(
                        child: Text(v, style: TempoType.bodyS.c(c.text1).tnum),
                      ),
                    ],
                  ),
                ),
              if (note != null) ...[
                const SizedBox(height: 6),
                Text(note!, style: TempoType.caption.c(c.text3)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Permissions extends StatelessWidget {
  const _Permissions({required this.permissions, required this.kinds});
  final HealthPermissions permissions;
  final List<HealthKind> kinds;

  static String _yn(bool? v) =>
      v == null ? 'Unknown' : (v ? 'Allowed' : 'Not allowed');

  @override
  Widget build(BuildContext context) {
    final p = permissions;
    final hidden = p.kinds.values.every((v) => v == null);
    return _Facts(
      title: 'Permissions',
      rows: [
        if (p.history != null) ('Older than 30 days', _yn(p.history)),
        if (p.background != null) ('In the background', _yn(p.background)),
        if (hidden)
          ('Each kind', 'Health doesn’t say')
        else
          for (final k in kinds) (kindName(k), _yn(p.kinds[k])),
      ],
      note: hidden
          ? 'Apple Health never tells an app what it may read: a kind you turned off just reads empty. Check Settings → Health → Data Access & Devices → Tempo.'
          : null,
    );
  }
}

class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.check, required this.names});
  final PipelineCheck check;
  final Map<String, String> names;

  static String _hm(int min) =>
      '${min ~/ 60}h ${(min % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final q = check;
    String src(String id) => sourceLabel(id, names);
    final stages = [
      for (final s in const ['deep', 'rem', 'light', 'asleep', 'awake'])
        if ((q.stages[s] ?? 0) > 0) '$s ${_hm(q.stages[s]!)}',
    ].join(' · ');
    return _Facts(
      title: 'Last night and today',
      rows: [
        ('Asleep, records', _hm(q.sleepRecordMin)),
        ('Asleep, minutes', _hm(q.sleepMin)),
        if (stages.isNotEmpty) ('Stages', stages),
        for (final a in q.sleepApps)
          (
            'Sleep app',
            '${a.label} · ${a.staged ? 'stages' : 'no stages'}${a.used ? '' : ' · not used'}',
          ),
        if (q.tempoWrote) ('Sleep app', 'Tempo’s own exports · skipped'),
        ('HR records today', '${q.hrRecords}'),
        (
          'HR minutes today',
          '${q.hrMeasuredMin} measured · ${q.hrMin} with HR',
        ),
        ('Steps today', '${q.stepsTempo} in Tempo'),
        for (final e in q.stepsBySource.entries)
          ('', '${src(e.key)} ${e.value} in records'),
        for (final m in SourceMetric.values)
          (
            'Source · ${m.name}',
            q.chosen[m] == null ? 'Every app' : src(q.chosen[m]!),
          ),
        (
          'Score today',
          q.today == null ? 'None yet' : HealthCheckReport.scoreLine(q.today!),
        ),
        (
          'Score yesterday',
          q.yesterday == null
              ? 'None'
              : HealthCheckReport.scoreLine(q.yesterday!),
        ),
      ],
      note:
          'Night: ${_when(q.nightFrom)} – ${clockOf(q.nightTo)}. Records and minutes should agree within a few minutes; steps in records double-count when phone and watch both write them.',
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({required this.check, required this.names, this.onTap});
  final KindCheck check;
  final Map<String, String> names;
  final VoidCallback? onTap;

  static String _verdict(KindVerdict v) => switch (v) {
    KindVerdict.ok => 'OK',
    KindVerdict.empty => 'No data',
    KindVerdict.missing => 'Missing',
    KindVerdict.extra => 'Extra',
    KindVerdict.odd => 'Odd values',
    KindVerdict.failed => 'Read failed',
  };

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
          if (k.min != null)
            'Range ${HealthCheckReport.num(k.min!)}–${HealthCheckReport.num(k.max!)}',
          if (k.latest != null) 'latest ${_when(k.latest!)}',
        ].join(' · '),
        if (k.sources.isNotEmpty)
          [
            for (final e in k.sources.entries)
              '${sourceLabel(e.key, names)} ${e.value}',
          ].join(' · '),
      ],
    ];
    return Pressable(
      label: kindName(k.kind),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kindName(k.kind),
                    style: TempoType.label.c(c.text1),
                  ),
                ),
                TempoBadge(
                  _verdict(k.verdict),
                  small: true,
                  color: warn ? context.s.recLow : null,
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  TempoIcon(TempoIcons.chevron, size: 14, color: c.text3),
                ],
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
      ),
    );
  }
}

/// The newest records of one kind exactly as Health returned them, so units,
/// ids and sources can be checked by eye.
class HealthRecordsScreen extends StatelessWidget {
  const HealthRecordsScreen({
    super.key,
    required this.check,
    required this.names,
  });
  final KindCheck check;
  final Map<String, String> names;

  static String _status(RecordStatus s) => switch (s) {
    RecordStatus.stored => 'Stored',
    RecordStatus.newer => 'Newer',
    RecordStatus.missing => 'Missing',
    RecordStatus.dropped => 'Dropped',
  };

  static String _clockSec(DateTime t) =>
      '${clockOf(t)} :${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final k = check;
    return TempoPage(
      gap: 16,
      bottom: 48,
      children: [
        DetailHeader(title: kindName(k.kind)),
        Text(
          'The newest ${k.recent.length} of ${k.inHealth} records from the last 7 days, as Health gave them. Value units are the plugin’s; sleep values are minutes.',
          style: TempoType.bodyS.c(c.text2),
        ),
        CardList(
          children: [
            for (final (i, cr) in k.recent.indexed) ...[
              if (i > 0) const Hair(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${HealthCheckReport.num(cr.record.value)}'
                            '${cr.record.extra == null ? '' : ' · ${cr.record.extra}'}',
                            style: TempoType.label.c(c.text1).tnum,
                          ),
                        ),
                        if (cr.odd) ...[
                          TempoBadge(
                            'Odd',
                            small: true,
                            color: context.s.recLow,
                          ),
                          const SizedBox(width: 6),
                        ],
                        TempoBadge(
                          _status(cr.status),
                          small: true,
                          color: cr.status == RecordStatus.missing
                              ? context.s.recLow
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cr.record.start == cr.record.end
                          ? '${dayShort(cr.record.start)} ${_clockSec(cr.record.start)}'
                          : '${dayShort(cr.record.start)} ${_clockSec(cr.record.start)} – ${_clockSec(cr.record.end)}',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                    Text(
                      '${sourceLabel(cr.record.sourceApp, names)} · ${cr.record.sourceApp}',
                      style: TempoType.caption.c(c.text2),
                    ),
                    SelectableText(
                      cr.record.uuid,
                      style: TempoType.caption.c(c.text3),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
