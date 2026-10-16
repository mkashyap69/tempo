import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_source/health_source.dart';

import '../core/background_guard.dart';
import '../core/band_link.dart' show deviceIdKey, deviceNameKey;
import '../core/data_source.dart';
import '../core/format.dart';
import '../core/health_export.dart';
import '../core/health_sync.dart';
import '../core/profile.dart' show Keys;
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'data_source.dart';
import 'nav.dart';
import 'pairing.dart';

/// What the Data sources screen shows besides plain settings.
final class _SourcesData {
  const _SourcesData(this.found, this.from, this.chosen, this.batteryExempt);
  final Set<HealthKind> found;

  /// Apps that wrote each measure lately, and the app chosen for it.
  final Map<SourceMetric, List<SleepSourceInfo>> from;
  final Map<SourceMetric, String?> chosen;
  final bool batteryExempt;

  List<SleepSourceInfo> get sleepFrom => from[SourceMetric.sleep] ?? const [];
}

final _sourcesProvider = FutureProvider<_SourcesData>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  var exempt = true;
  if (Platform.isAndroid) {
    try {
      exempt = await BackgroundGuard.batteryExempt;
    } catch (_) {}
  }
  return _SourcesData(
    await healthFound(db),
    {for (final m in SourceMetric.values) m: await metricSources(db, m)},
    {for (final m in SourceMetric.values) m: await metricSource(db, m)},
    exempt,
  );
});

/// The data types shown under Health access, in order.
const _accessRows = <(String, List<HealthKind>)>[
  ('Heart rate', [HealthKind.heartRate]),
  ('Heart rate variability', [HealthKind.hrvSdnn, HealthKind.hrvRmssd]),
  ('Resting heart rate', [HealthKind.restingHr]),
  (
    'Sleep',
    [
      HealthKind.sleepAsleep,
      HealthKind.sleepLight,
      HealthKind.sleepDeep,
      HealthKind.sleepRem,
      HealthKind.sleepInBed,
      HealthKind.sleepSession,
    ],
  ),
  ('Steps', [HealthKind.steps]),
  ('Workouts', [HealthKind.workout]),
  ('Blood oxygen', [HealthKind.spo2]),
  ('Respiratory rate', [HealthKind.respiratoryRate]),
  ('Water', [HealthKind.water]),
  ('Caffeine', [HealthKind.caffeine]),
  ('Night temperature', [HealthKind.wristTemp]),
];

/// Profile → Data sources: where Tempo gets its data, how fresh it is,
/// what Health shares, whose sleep counts, and writing back to Health.
/// See decisions.md, 2026-10-16.
class DataSourcesScreen extends ConsumerWidget {
  const DataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final source = ref.watch(dataSourceProvider);
    String? setting(String k) => ref.watch(settingProvider(k)).value;
    final lastSync = DateTime.tryParse(setting(Keys.lastSync) ?? '');
    final paired = (setting(deviceIdKey) ?? '').isNotEmpty;
    final bandName = (setting(deviceNameKey) ?? '').isNotEmpty
        ? setting(deviceNameKey)!
        : 'Mi Smart Band 6';
    final battery = setting(Keys.battery);
    final exportOn = setting(Keys.healthExport) == '1';
    final sleepFrom = setting(Keys.healthSleepSource);
    final data = ref.watch(_sourcesProvider).value;
    final health = DataSource.platformHealth;
    final sync = ref.watch(syncProvider);

    String fresh(DateTime? t, String verb) => t == null
        ? 'not $verb yet'
        : '$verb ${ago(DateTime.now().difference(t))}';

    return TempoPage(
      children: [
        const DetailHeader(title: 'Data sources'),
        Text(
          'Tempo reads one source at a time. Everything stays on this phone.',
          style: TempoType.body.c(c.text2),
        ),
        _SourceCard(
          title: 'Mi Band 6',
          subtitle:
              'Direct Bluetooth · heart rate every minute, sleep, stress, SpO₂',
          active: source == DataSource.band,
          status: source != DataSource.band
              ? (paired ? '$bandName · paired, not in use' : 'Not paired')
              : !paired
              ? 'Not paired yet'
              : '$bandName · ${fresh(lastSync, 'synced')}'
                    '${battery == null ? '' : ' · battery $battery%'}',
          action: source == DataSource.band
              ? (paired
                    ? (sync.running ? 'Syncing…' : 'Sync now')
                    : 'Pair band')
              : 'Use the band',
          onAction: source == DataSource.band
              ? (paired
                    ? (sync.running
                          ? null
                          : () => ref.read(syncProvider.notifier).syncNow())
                    : () => push(context, const PairingScreen()))
              : () => useDataSource(context, ref, DataSource.band),
        ),
        _SourceCard(
          title: health.label,
          subtitle: 'From your watch or ring · read-only, Tempo never changes what it reads',
          active: source.isHealth,
          status: source.isHealth
              ? 'Reading · ${fresh(lastSync, 'read')}'
              : 'Not connected',
          action: source.isHealth
              ? (sync.running ? 'Reading…' : 'Read now')
              : 'Use ${health.label}',
          onAction: source.isHealth
              ? (sync.running
                    ? null
                    : () => ref.read(syncProvider.notifier).syncNow())
              : () => useDataSource(context, ref, health),
        ),
        if (source.isHealth) ...[
          const Overline('Health access'),
          CardList(
            children: [
              for (final (name, kinds) in _accessRows)
                ListRow(
                  name,
                  value: data == null
                      ? '…'
                      : kinds.any(data.found.contains)
                      ? 'Reading'
                      : 'None yet',
                  chevron: false,
                ),
              ListRow(
                'Check access',
                sub: health == DataSource.appleHealth
                    ? 'Apple Health never tells apps what you turned off. If something says “None yet”, check Settings → Health → Data Access & Devices → Tempo.'
                    : 'Opens Health Connect’s permissions for Tempo.',
                onTap: () async {
                  await connectHealth(context, ref);
                  ref.invalidate(_sourcesProvider);
                },
              ),
              if (Platform.isAndroid)
                ListRow(
                  'Background reads',
                  sub: data?.batteryExempt ?? true
                      ? null
                      : 'Battery optimisation can stop background reads',
                  value: data?.batteryExempt ?? true ? 'Allowed' : 'Restricted',
                  onTap: () async {
                    await BackgroundGuard.requestBatteryExemption();
                    ref.invalidate(_sourcesProvider);
                  },
                ),
            ],
          ),
          const Overline('Sleep from'),
          _SleepFrom(options: data?.sleepFrom ?? const [], selected: sleepFrom),
          // Other measures only when two or more apps write them.
          for (final m in const [
            SourceMetric.heartRate,
            SourceMetric.hrv,
            SourceMetric.steps,
          ])
            if ((data?.from[m]?.length ?? 0) >= 2 ||
                data?.chosen[m] != null) ...[
              Overline('${_metricName(m)} from'),
              _MetricFrom(
                metric: m,
                options: data!.from[m] ?? const [],
                selected: data.chosen[m],
              ),
            ],
        ],
        const Overline('Writing to Health'),
        CardList(
          children: [
            ListRow(
              source.isHealth
                  ? 'Save workouts to ${health.label}'
                  : 'Save workouts and sleep to ${health.label}',
              sub: source.isHealth
                  ? 'Workouts you record in Tempo. Tempo never reads its own records back.'
                  : 'Confirmed workouts and nights, from 7 days before you turn it on.',
              chevron: false,
              trailing: TempoSwitch(
                label: 'Write to ${health.label}',
                value: exportOn,
                onChanged: (v) async {
                  final db = ref.read(dbProvider);
                  final h = HealthExport(db);
                  if (!v) {
                    await h.disable();
                    return;
                  }
                  final ok = await h.enable();
                  if (!ok && context.mounted) {
                    showTempoToast(
                      context,
                      Platform.isAndroid
                          ? 'Install Health Connect, then turn this on again.'
                          : 'Tempo needs write access in Health settings.',
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.status,
    required this.action,
    required this.onAction,
  });
  final String title, subtitle, status, action;
  final bool active;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TempoType.label.c(c.text1))),
              if (active) const TempoBadge('In use'),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TempoType.bodyS.c(c.text2)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? c.text1 : c.trackOff,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(status, style: TempoType.caption.c(c.text2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TempoButton(
            action,
            kind: active ? ButtonKind.secondary : ButtonKind.primary,
            small: true,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

/// Which app's sleep counts: every app merged (Health's own view), or one.
class _SleepFrom extends ConsumerStatefulWidget {
  const _SleepFrom({required this.options, required this.selected});
  final List<SleepSourceInfo> options;
  final String? selected;

  @override
  ConsumerState<_SleepFrom> createState() => _SleepFromState();
}

class _SleepFromState extends ConsumerState<_SleepFrom> {
  bool _busy = false;

  Future<void> _choose(String? id) async {
    if (id == widget.selected || _busy) return;
    setState(() => _busy = true);
    try {
      await setSleepSource(ref.read(dbProvider), id);
      if (mounted) {
        showTempoToast(
          context,
          id == null
              ? 'Sleep now comes from every app, merged'
              : 'Sleep now comes from ${widget.options.where((o) => o.id == id).firstOrNull?.label ?? id} only · nights rescored',
        );
      }
    } catch (e) {
      if (mounted) showTempoToast(context, 'Couldn’t change it: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final opts = widget.options;
    final chosenMissing =
        widget.selected != null && !opts.any((o) => o.id == widget.selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardList(
          children: [
            ListRow(
              'Every app, merged',
              sub: 'What Health shows. Two trackers can add up to a longer night.',
              chevron: false,
              trailing: widget.selected == null ? const _Tick() : null,
              onTap: _busy ? null : () => _choose(null),
            ),
            for (final o in opts)
              ListRow(
                o.label,
                sub:
                    '${o.nights} ${o.nights == 1 ? 'night' : 'nights'} in the last 30 days · last ${dayShort(o.last)}',
                chevron: false,
                trailing: widget.selected == o.id ? const _Tick() : null,
                onTap: _busy ? null : () => _choose(o.id),
              ),
            if (chosenMissing)
              ListRow(
                'Chosen app',
                sub: 'No sleep from it in the last 30 days',
                chevron: false,
                trailing: const _Tick(),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _busy
              ? 'Rescoring nights…'
              : opts.isEmpty
              ? 'No sleep in Health from the last 30 days yet.'
              : 'Choose your watch or ring if Tempo’s nights look longer than your tracker’s.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

String _metricName(SourceMetric m) => switch (m) {
  SourceMetric.sleep => 'Sleep',
  SourceMetric.heartRate => 'Heart rate',
  SourceMetric.steps => 'Steps',
  SourceMetric.hrv => 'HRV',
};

/// Which app's heart rate, HRV or steps count: every app (merged as
/// before) or one. Shown when two or more apps write the measure.
class _MetricFrom extends ConsumerStatefulWidget {
  const _MetricFrom({
    required this.metric,
    required this.options,
    required this.selected,
  });
  final SourceMetric metric;
  final List<SleepSourceInfo> options;
  final String? selected;

  @override
  ConsumerState<_MetricFrom> createState() => _MetricFromState();
}

class _MetricFromState extends ConsumerState<_MetricFrom> {
  bool _busy = false;

  Future<void> _choose(String? id) async {
    if (id == widget.selected || _busy) return;
    setState(() => _busy = true);
    final name = _metricName(widget.metric);
    try {
      await setMetricSource(ref.read(dbProvider), widget.metric, id);
      if (mounted) {
        showTempoToast(
          context,
          id == null
              ? '$name now comes from every app'
              : '$name now comes from ${widget.options.where((o) => o.id == id).firstOrNull?.label ?? id} only · days rescored',
        );
      }
    } catch (e) {
      if (mounted) showTempoToast(context, 'Couldn’t change it: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardList(
          children: [
            ListRow(
              'Every app',
              sub: widget.metric == SourceMetric.steps
                  ? 'The busiest app each minute, so a phone and a watch don’t double up.'
                  : 'Readings in the same minute are averaged.',
              chevron: false,
              trailing: widget.selected == null ? const _Tick() : null,
              onTap: _busy ? null : () => _choose(null),
            ),
            for (final o in widget.options)
              ListRow(
                o.label,
                sub:
                    '${o.nights} ${o.nights == 1 ? 'day' : 'days'} in the last 30 · last ${dayShort(o.last)}',
                chevron: false,
                trailing: widget.selected == o.id ? const _Tick() : null,
                onTap: _busy ? null : () => _choose(o.id),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _busy
              ? 'Rescoring days…'
              : 'Pick the device you trust most for ${_metricName(widget.metric).toLowerCase()}.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick();
  @override
  Widget build(BuildContext context) =>
      Text('✓', style: TempoType.label.c(context.c.text1));
}
