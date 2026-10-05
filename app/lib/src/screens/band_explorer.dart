import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/band_explorer.dart';
import '../core/band_link.dart' show BandBusyException;
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/live_session.dart';
import '../state/providers.dart';

/// Data health → Band explorer: a one-off, read-only survey of what the
/// band holds, shared as a log so new data types can be confirmed before
/// Tempo relies on them.
class BandExplorerScreen extends ConsumerStatefulWidget {
  const BandExplorerScreen({super.key});
  @override
  ConsumerState<BandExplorerScreen> createState() => _ExplorerState();
}

class _ExplorerState extends ConsumerState<BandExplorerScreen> {
  bool _running = false, _cancel = false;
  String? _error;
  final _progress = <ExplorerStage, (double, String)>{};
  ExplorerReport? _report;
  File? _file;

  Future<void> _run() async {
    if (ref.read(liveSessionProvider) != null) {
      setState(() => _error = 'Finish the workout first; it holds the band.');
      return;
    }
    setState(() {
      _running = true;
      _cancel = false;
      _error = null;
      _report = null;
      _progress.clear();
    });
    try {
      final (r, f) = await exploreBand(
        ref.read(dbProvider),
        cancelled: () => _cancel || !mounted,
        onProgress: (stage, fraction, detail) {
          if (mounted) setState(() => _progress[stage] = (fraction, detail));
        },
      );
      if (mounted) {
        setState(() {
          _report = r;
          _file = f;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is BandBusyException
              ? 'The band is busy with a sync. Try again in a moment.'
              : 'Couldn’t finish: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _share() async {
    final r = _report, f = _file;
    if (r == null || f == null) return;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Tempo band explorer',
        files: [
          XFile(f.path, mimeType: 'application/json'),
          if (r.packetLog != null && File(r.packetLog!).existsSync())
            XFile(r.packetLog!, mimeType: 'application/x-ndjson'),
        ],
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
        const DetailHeader(title: 'Band explorer'),
        Text(
          'Finds out what your Mi Band 6 can share beyond what Tempo uses today, so new data (like beat-to-beat heart rate for HRV) is only added once your band confirms it.',
          style: TempoType.body.c(c.text1),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (icon, text) in [
                (
                  TempoIcons.private,
                  'Read-only. Nothing on the band is changed or deleted.',
                ),
                (
                  TempoIcons.clock,
                  'About 5 minutes. Keep the band close and the screen on.',
                ),
                (
                  TempoIcons.heartRate,
                  'For the last 2 minutes, sit still: it records heart rate beat by beat.',
                ),
                (
                  TempoIcons.info,
                  'Before you start, note today’s VO₂ max, resting heart rate, stress and last night’s stages in Mi Fitness. Matching them speeds up decoding.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TempoIcon(icon, size: 18, color: c.text2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(text, style: TempoType.bodyS.c(c.text2)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_running || r != null)
          CardList(
            children: [
              for (final (i, (stage, title)) in [
                (ExplorerStage.characteristics, 'Band characteristics'),
                (ExplorerStage.history, 'History types (0x00–0x3f)'),
                (ExplorerStage.liveHr, 'Beat-to-beat heart rate'),
              ].indexed) ...[
                if (i > 0) const Hair(),
                _StepRow(title: title, progress: _progress[stage]),
              ],
            ],
          ),
        if (_error != null)
          StatusBanner(
            icon: TempoIcons.alert,
            title: 'Explorer stopped',
            body: _error!,
            action: 'Retry',
            onAction: _run,
          ),
        if (r != null) _Results(report: r),
        if (_running)
          TempoButton(
            'Stop',
            kind: ButtonKind.secondary,
            expand: true,
            onTap: () => setState(() => _cancel = true),
          )
        else if (r == null)
          TempoButton('Run explorer', expand: true, onTap: _run)
        else
          TempoButton('Share results', expand: true, onTap: _share),
        Text(
          'Results and the raw Bluetooth log stay on this phone until you share them. They contain band data but never your auth key.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.title, required this.progress});
  final String title;
  final (double, String)? progress;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = progress;
    final done = p != null && p.$1 >= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TempoType.label.c(c.text1))),
              if (done)
                TempoIcon(TempoIcons.check, size: 16, color: c.text1)
              else if (p == null)
                Text('Waiting', style: TempoType.caption.c(c.text3)),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 6),
            if (!done)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: p.$1,
                  backgroundColor: c.trackOff,
                  color: c.text1,
                ),
              ),
            const SizedBox(height: 4),
            Text(p.$2, style: TempoType.caption.c(c.text2).tnum),
          ],
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.report});
  final ExplorerReport report;
  @override
  Widget build(BuildContext context) {
    final r = report;
    final withData = [
      for (final p in r.probes)
        if (p.count > 0) p,
    ];
    final rm = r.rmssd;
    return Section(
      title: 'What your band has',
      child: CardList(
        children: [
          ListRow(
            'Beat-to-beat heart rate',
            chevron: false,
            sub: r.hasRr
                ? '${r.rrMs.length} intervals in ${r.packetsWithRr} readings${rm == null ? '' : ' · HRV (RMSSD) ${rm.round()} ms'}'
                : 'Not sent (${r.hrPackets.length} readings, bpm only)',
            value: r.hasRr ? 'Yes' : 'No',
          ),
          const Hair(),
          ListRow(
            'History types with data',
            chevron: false,
            sub: withData.isEmpty
                ? 'None answered with data'
                : [
                    for (final p in withData)
                      '0x${p.code.toRadixString(16).padLeft(2, '0')}${p.known == null ? ' (new)' : ' ${p.known}'} · ${p.count}',
                  ].join('\n'),
            value: '${withData.length}',
          ),
          const Hair(),
          ListRow(
            'Characteristics read',
            chevron: false,
            value:
                '${r.characteristics.values.whereType<List<int>>().length} / ${r.characteristics.length}',
          ),
        ],
      ),
    );
  }
}
