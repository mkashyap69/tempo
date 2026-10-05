import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:store/store.dart' as st;

import '../core/background_guard.dart';
import '../core/battery.dart';
import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/profile.dart';

import 'package:band_ble/band_ble.dart' show kindNotWorn;

import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'settings.dart' show redownloadHistory;

/// Per-day wear: (minutes, kind) runs. kind: 0 worn, 1 not worn, 2 gap.
class _Health {
  _Health(
    this.days,
    this.log,
    this.battery,
    this.batteryAt,
    this.lastSync,
    this.coverage,
    this.dbBytes,
    this.daysStored,
    this.notWornMin,
    this.gaps,
    this.batteryDays,
    this.batteryExempt,
  );
  final List<(DateTime, List<(int, int)>)> days;
  final List<st.SyncLogData> log;
  final int? battery;
  final DateTime? batteryAt, lastSync;
  final double coverage;
  final int dbBytes, daysStored, notWornMin;
  final List<(DateTime, int)> gaps;
  final double? batteryDays;
  final bool batteryExempt;
}

final _healthProvider = FutureProvider<_Health>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final today = dayOf(DateTime.now());
  final now = DateTime.now();
  final days = <(DateTime, List<(int, int)>)>[];
  var worn = 0, expected = 0, notWorn = 0;
  final gaps = <(DateTime, int)>[];
  final last = await db.lastMinute();
  for (var i = 0; i < 7; i++) {
    final d = today.subtract(Duration(days: i));
    final mins = await db.minutesBetween(d, d.add(const Duration(days: 1)));
    final byMin = List<int>.filled(1440, 2); // default: gap (no record)
    for (final m in mins) {
      final t = st.fromTs(m.ts);
      byMin[t.hour * 60 + t.minute] = kindNotWorn(m.kind) ? 1 : 0;
    }
    final end = i == 0
        ? (last != null && DateUtils.isSameDay(last, d)
              ? last.hour * 60 + last.minute + 1
              : now.hour * 60 + now.minute)
        : 1440;
    final runs = <(int, int)>[];
    for (var m = 0; m < end; m++) {
      if (runs.isNotEmpty && runs.last.$2 == byMin[m]) {
        runs[runs.length - 1] = (runs.last.$1 + 1, byMin[m]);
      } else {
        runs.add((1, byMin[m]));
      }
    }
    if (end < 1440) runs.add((1440 - end, -1));
    for (var m = 0, k = 0; k < runs.length; m += runs[k].$1, k++) {
      if (runs[k].$2 == 2 && runs[k].$1 >= 15 && mins.isNotEmpty) {
        gaps.add((d.add(Duration(minutes: m)), runs[k].$1));
      }
    }
    worn += byMin.take(end).where((v) => v == 0).length;
    notWorn += byMin.take(end).where((v) => v == 1).length;
    expected += end;
    days.add((d, runs));
  }
  var size = 0;
  try {
    final f = File(
      '${(await getApplicationDocumentsDirectory()).path}/tempo.sqlite',
    );
    if (await f.exists()) size = await f.length();
  } catch (_) {}
  final first = await db.firstMinute();
  final bat = await db.setting(Keys.battery),
      batAt = await db.setting(Keys.batteryAt),
      ls = await db.setting(Keys.lastSync);
  return _Health(
    days,
    await db.watchSyncLog(limit: 8).first,
    int.tryParse(bat ?? ''),
    batAt == null ? null : DateTime.tryParse(batAt),
    ls == null ? null : DateTime.tryParse(ls),
    expected == 0 ? 0 : worn / expected,
    size,
    first == null ? 0 : today.difference(dayOf(first)).inDays + 1,
    notWorn,
    gaps,
    batteryDaysLeft(await batteryLog(db)),
    await BackgroundGuard.batteryExempt,
  );
});

class DataHealthScreen extends ConsumerWidget {
  const DataHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(_healthProvider).value;
    final c = context.c;
    if (h == null) return Scaffold(backgroundColor: c.bg);
    final lastOk = h.log.where((l) => l.result == 'ok').firstOrNull;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Data health'),
        TempoCard(
          child: Row(
            children: [
              Expanded(
                child: Stat(
                  'Battery',
                  h.battery == null ? '—' : '${h.battery}%',
                  sub: h.battery == null
                      ? 'not read yet'
                      : batteryLeftLabel(h.batteryDays),
                ),
              ),
              Expanded(
                child: Stat(
                  'Last sync',
                  h.lastSync == null ? '—' : clockShort(h.lastSync!),
                  sub: h.lastSync == null
                      ? 'never'
                      : '${ampm(h.lastSync!)} · ${lastOk == null ? 'pending' : 'OK'}',
                ),
              ),
              Expanded(
                child: Stat(
                  'Coverage',
                  '${(h.coverage * 100).round()}%',
                  sub: 'last 7 days',
                ),
              ),
            ],
          ),
        ),
        if (!h.batteryExempt)
          StatusBanner(
            icon: TempoIcons.alert,
            title: 'Background sync is restricted',
            body: 'Battery optimisation can stop overnight syncs, which leaves gaps when the band’s memory fills.',
            action: 'Allow',
            onAction: () async {
              await BackgroundGuard.requestBatteryExemption();
              ref.invalidate(_healthProvider);
            },
          ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Wear and gaps',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  Text('24 h per row', style: TempoType.caption.c(c.text3)),
                ],
              ),
              const SizedBox(height: 10),
              for (final (d, runs) in h.days)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          dayShort(d).substring(0, 3),
                          style: TempoType.caption.c(c.text2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 14,
                            child: Row(
                              children: [
                                for (final (m, k) in runs)
                                  Expanded(
                                    flex: m,
                                    child: Container(
                                      margin: const EdgeInsets.only(right: .5),
                                      color: switch (k) {
                                        0 => c.text2,
                                        1 => c.trackOff,
                                        2 => c.text3.withValues(alpha: .45),
                                        _ => Colors.transparent,
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 14,
                children: [
                  Legend(c.text2, 'Worn', width: 12, height: 8),
                  Legend(
                    c.lineStrong,
                    'Not worn',
                    width: 12,
                    height: 8,
                    outline: true,
                  ),
                  Legend(
                    c.text3.withValues(alpha: .45),
                    'Data gap',
                    width: 12,
                    height: 8,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Not worn: ${hmSpaced(h.notWornMin / 60)} this week.${h.gaps.isEmpty ? ' No data gaps.' : ' ${h.gaps.length} ${h.gaps.length == 1 ? 'gap' : 'gaps'} — e.g. ${dayShort(h.gaps.first.$1).substring(0, 3)} ${clockOf(h.gaps.first.$1)}, ${h.gaps.first.$2} min.'} Tempo fills nothing in; affected scores say so.',
                style: TempoType.bodyS.c(c.text2),
              ),
            ],
          ),
        ),
        Section(
          title: 'Sync log',
          child: h.log.isEmpty
              ? const TempoEmpty('No syncs yet.')
              : CardList(
                  children: [
                    for (final l in h.log)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(
                                _when(st.fromTs(l.ts)),
                                style: TempoType.caption.c(c.text2).tnum,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.summary,
                                style: TempoType.bodyS.c(c.text1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              switch (l.result) {
                                'ok' =>
                                  l.durationMs == null
                                      ? 'OK'
                                      : 'OK · ${(l.durationMs! / 1000).round()} s',
                                'retried' => 'Retried',
                                'failed' => 'Failed',
                                'settings' => 'Settings',
                                'repair' => 'Repair',
                                _ => 'Gap',
                              },
                              style: TempoType.caption.c(
                                l.result == 'ok' ? c.text2 : c.text1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (h.lastSync != null)
          Center(
            child: TempoButton(
              'Re-download band history',
              small: true,
              kind: ButtonKind.ghost,
              onTap: () => redownloadHistory(context, ref),
            ),
          ),
        PrivacyNote(
          'All data stays on this phone · ${(h.dbBytes / 1e6).toStringAsFixed(h.dbBytes < 1e7 ? 1 : 0)} MB · ${h.daysStored} days',
        ),
      ],
    );
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(dayOf(t)).inDays;
    final day = d == 0
        ? 'Today'
        : d == 1
        ? 'Yest.'
        : dayShort(t).substring(0, 3);
    return '$day ${clockShort(t)}';
  }
}
