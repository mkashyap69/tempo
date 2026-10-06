import 'dart:io';

import 'package:band_ble/band_ble.dart' show SettingsCommands;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:share_plus/share_plus.dart';

import '../core/band_link.dart';
import '../core/battery.dart';
import '../core/export.dart';
import '../core/format.dart';
import '../core/health_export.dart';
import '../core/home_widgets.dart';
import '../core/background_guard.dart';
import '../core/key_store.dart';
import '../core/notifications.dart';
import '../core/pause.dart';
import '../core/profile.dart';
import '../core/score_service.dart';
import '../core/sync_service.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'backups.dart';
import 'band_explorer.dart';
import 'coach_settings.dart';
import 'data_health.dart';
import 'nav.dart';
import 'onboarding.dart' show AvailabilityEditor, WorkoutsEditor;
import 'pairing.dart';
import 'weekly_report.dart';

final _bandInfoProvider = FutureProvider<Map<String, String?>>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  return {
    for (final k in [
      Keys.battery,
      Keys.firmware,
      Keys.lastSync,
      Keys.morningCall,
      Keys.bedtimeNudge,
      Keys.buzzCues,
      hrIntervalKey,
      deviceNameKey,
      deviceIdKey,
      Keys.sleepAssist,
      Keys.stressMonitor,
      Keys.healthExport,
    ])
      k: await db.setting(k),
  };
});

/// Things Profile shows that aren't plain settings.
final _profileExtrasProvider =
    FutureProvider<({double? batteryDays, bool batteryExempt, Pause? pause})>((
      ref,
    ) async {
      ref.watch(dbTickProvider);
      final db = ref.watch(dbProvider);
      return (
        batteryDays: batteryDaysLeft(await batteryLog(db)),
        batteryExempt: await BackgroundGuard.batteryExempt,
        pause: activePause(await loadPauses(db)),
      );
    });

/// Runs a band write behind a blocking dialog, then shows the result.
/// A snackbar was easy to miss, so writes looked like dead buttons.
Future<void> bandAction(
  BuildContext context,
  Future<String> Function() body,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Connecting to the band…',
                style: TempoType.body.c(c.c.text1),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  String message;
  try {
    message = await body();
  } catch (e) {
    message = e is BandBusyException
        ? 'The band is busy with a sync. Try again in a moment.'
        : 'Couldn’t reach the band: $e';
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();
  showTempoToast(context, message);
}

Future<String> writeBandSettings(WidgetRef ref) async {
  final db = ref.read(dbProvider);
  final profile = await loadAppProfile(db);
  if (profile == null) return 'No profile saved yet.';
  final every = int.tryParse(await db.setting(hrIntervalKey) ?? '') ?? 1;
  final link = await BandLink.open(db);
  try {
    final failed = await link.band.configure(
      profile.band,
      hrEveryMinutes: every,
      sleepAssist: await db.setting(Keys.sleepAssist) != '0',
      stress: await db.setting(Keys.stressMonitor) != '0',
      wornLeft: profile.wornLeft,
    );
    return failed.isEmpty
        ? 'Band settings written.'
        : 'Not written: ${failed.join(', ')}';
  } finally {
    await link.close();
  }
}

/// One band write behind [bandAction]; [what] names it in the result.
Future<String> writeBandSetting(
  WidgetRef ref,
  String what,
  Future<void> Function(BandLink link) write,
) async {
  final link = await BandLink.open(ref.read(dbProvider));
  try {
    await write(link);
    return '$what written to the band.';
  } finally {
    await link.close();
  }
}

Future<int?> editNumber(
  BuildContext context, {
  required String title,
  required int initial,
  required String suffix,
  required int min,
  required int max,
  String? note,
}) async {
  final ctl = TextEditingController(text: '$initial');
  final r = await showTempoSheet<int>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final v = int.tryParse(ctl.text);
        final ok = v != null && v >= min && v <= max;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TempoType.titleM.c(ctx.c.text1)),
            const SizedBox(height: 12),
            TempoField(
              controller: ctl,
              suffix: suffix,
              autofocus: true,
              keyboardType: TextInputType.number,
              error: !ok,
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              ok ? (note ?? '') : '⚠ Enter $min–$max.',
              style: TempoType.caption.c(ok ? ctx.c.text2 : ctx.s.recLow),
            ),
            const SizedBox(height: 16),
            TempoButton(
              'Save',
              expand: true,
              onTap: ok ? () => Navigator.pop(ctx, v) : null,
            ),
          ],
        );
      },
    ),
  );
  ctl.dispose();
  return r;
}

/// Profile → Advanced and Data health: replace stored band history with a
/// fresh download (see SyncService.redownload).
Future<void> redownloadHistory(BuildContext context, WidgetRef ref) async {
  final ok = await confirmSheet(
    context,
    title: 'Re-download band history?',
    body: 'Tempo fetches everything your band still holds and replaces what’s stored from that point on. Use it if sleep or activity times look shifted. Older days the band no longer has stay as they are.',
    action: 'Re-download',
  );
  if (!ok || !context.mounted) return;
  await bandAction(
    context,
    () => SyncService(ref.read(dbProvider)).redownload(),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    final info = ref.watch(_bandInfoProvider).value;
    final extras = ref.watch(_profileExtrasProvider).value;
    final sync = ref.watch(syncProvider);
    final mode = ref.watch(settingProvider(Keys.theme)).value ?? 'dark';
    final c = context.c;
    if (p == null || info == null) return Scaffold(backgroundColor: c.bg);
    final db = ref.read(dbProvider);
    final paired = (info[deviceIdKey] ?? '').isNotEmpty;
    final lastSync = info[Keys.lastSync] == null
        ? null
        : DateTime.tryParse(info[Keys.lastSync]!);
    final connected =
        paired &&
        sync.problem == SyncProblem.none &&
        lastSync != null &&
        DateTime.now().difference(lastSync).inHours < 12;
    final hrEvery = int.tryParse(info[hrIntervalKey] ?? '') ?? 1;
    final buzz = (info[Keys.buzzCues] ?? '1') == '1';
    final morning = info[Keys.morningCall] ?? '07:00';
    final nudge = info[Keys.bedtimeNudge] ?? '45';
    final sleepAssist = info[Keys.sleepAssist] != '0';
    final stressOn = info[Keys.stressMonitor] != '0';
    final healthOn = info[Keys.healthExport] == '1';
    final healthName = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    final pause = extras?.pause;

    Future<void> save(Profile next) async {
      await saveAppProfile(db, next);
      ref.invalidate(profileProvider);
    }

    String height() => p.metric
        ? '${p.heightCm} cm'
        : '${(p.heightCm / 30.48).floor()}′${((p.heightCm / 2.54) % 12).round()}″';
    String weight() => p.metric
        ? '${p.weightKg.round()} kg'
        : '${(p.weightKg * 2.2046).round()} lb';

    Widget group(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Overline(title),
        ),
        const SizedBox(height: 8),
        CardList(children: rows),
      ],
    );

    return TempoPage(
      gap: 22,
      bottom: 100,
      children: [
        SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Profile', style: TempoType.pageTitle.c(c.text1)),
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.lineStrong, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.text1,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          paired
                              ? (info[deviceNameKey]?.isNotEmpty == true
                                    ? info[deviceNameKey]!
                                    : 'Mi Smart Band 6')
                              : 'No band paired',
                          style: TempoType.label.copyWith(
                            fontSize: 15,
                            color: c.text1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: connected ? c.text1 : c.trackOff,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                !paired
                                    ? 'Pair to start'
                                    : connected
                                    ? 'Connected'
                                    : 'Not connected${lastSync == null ? '' : ' · since ${clockOf(lastSync)}'}',
                                style: TempoType.caption.c(c.text2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TempoButton(
                    !paired
                        ? 'Pair'
                        : sync.running
                        ? 'Syncing…'
                        : connected
                        ? 'Sync now'
                        : 'Reconnect',
                    small: true,
                    kind: ButtonKind.secondary,
                    onTap: !paired
                        ? () => push(context, const PairingScreen())
                        : sync.running
                        ? null
                        : () => ref.read(syncProvider.notifier).syncNow(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Hair(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _mini(
                      context,
                      'Battery',
                      info[Keys.battery] == null
                          ? '—'
                          : '${info[Keys.battery]}%',
                      sub: info[Keys.battery] == null
                          ? null
                          : batteryLeftLabel(extras?.batteryDays),
                    ),
                  ),
                  Expanded(
                    child: _mini(
                      context,
                      'Firmware',
                      (info[Keys.firmware] ?? '—')
                          .split(' / ')
                          .last
                          .replaceFirst('V', ''),
                    ),
                  ),
                  Expanded(
                    child: _mini(
                      context,
                      'Last sync',
                      lastSync == null ? '—' : clockOf(lastSync),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Hair(),
              Pressable(
                onTap: () => push(context, const DataHealthScreen()),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sync health',
                          style: TempoType.body.c(c.text1),
                        ),
                      ),
                      Text(
                        'Coverage, gaps, sync log ›',
                        style: TempoType.bodyS.c(c.text2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const PrivacyNote(
          'All data stays on this phone',
          sub: 'No account, no cloud, no analytics. Your auth key is stored in the device keychain.',
        ),
        group('About you', [
          ListRow(
            'Age',
            value: '${p.age}',
            onTap: () async {
              final v = await editNumber(
                context,
                title: 'Age',
                initial: p.age,
                suffix: 'yrs',
                min: 13,
                max: 100,
              );
              if (v != null) await save(p.copyWith(age: v));
            },
          ),
          ListRow(
            'Height · weight',
            value: '${height()} · ${weight()}',
            onTap: () async {
              final h = await editNumber(
                context,
                title: 'Height',
                initial: p.heightCm,
                suffix: 'cm',
                min: 120,
                max: 230,
              );
              if (h == null || !context.mounted) return;
              final w = await editNumber(
                context,
                title: 'Weight',
                initial: p.weightKg.round(),
                suffix: 'kg',
                min: 30,
                max: 250,
              );
              if (w != null) {
                await save(p.copyWith(heightCm: h, weightKg: w.toDouble()));
              }
            },
          ),
          ListRow(
            'Max heart rate',
            value:
                '${p.effectiveMaxHr} bpm${p.maxHrEstimated ? ' · est.' : ''}',
            onTap: () async {
              final v = await editNumber(
                context,
                title: 'Max heart rate',
                initial: p.effectiveMaxHr,
                suffix: 'bpm',
                min: 120,
                max: 230,
                note:
                    'Estimated from age is ${sc.maxHrFromAge(p.age)}. If you’ve seen higher in a hard effort, use that.',
              );
              if (v == null) return;
              await save(
                p.copyWith(maxHr: () => v == sc.maxHrFromAge(p.age) ? null : v),
              );
              final first = await db.firstMinute();
              if (first != null) await ScoreService(db).recomputeFrom(first);
              if (context.mounted) {
                showTempoToast(context, 'Max HR set; zones and scores updated');
              }
            },
          ),
          ListRow(
            'Units',
            value: p.metric ? 'Metric' : 'Imperial',
            onTap: () => save(p.copyWith(metric: !p.metric)),
          ),
        ]),
        group('Training', [
          ListRow(
            'Priority',
            sub: 'What workouts lean toward. Race goals are on Weekly plan.',
            value: goalLabel(p.goal),
            onTap: () async {
              final g = await pickOption<sc.Goal>(
                context,
                title: 'What matters most?',
                options: sc.Goal.values,
                label: goalLabel,
                selected: p.goal,
              );
              if (g != null) await save(p.copyWith(goal: g));
            },
          ),
          ListRow(
            'Preferred workouts',
            value:
                [
                      for (final s in sportOrder)
                        if (p.likes.contains(s)) sportLabel(s).toLowerCase(),
                    ]
                    .join(', ')
                    .replaceFirstMapped(
                      RegExp('^.'),
                      (m) => m[0]!.toUpperCase(),
                    ),
            onTap: () async {
              final next = await showTempoSheet<Profile>(
                context,
                builder: (ctx) => WorkoutsEditor(profile: p, sheet: true),
              );
              if (next != null) await save(next);
            },
          ),
          ListRow(
            'Availability',
            value: '${p.days.length} days · up to ${p.maxMinutes} min',
            onTap: () async {
              final next = await showTempoSheet<Profile>(
                context,
                builder: (ctx) => AvailabilityEditor(profile: p, sheet: true),
              );
              if (next != null) await save(next);
            },
          ),
          ListRow(
            'Pause',
            sub: pause == null
                ? 'Ill or travelling? Baselines and the plan hold still.'
                : 'Baselines and plan on hold',
            value: pause == null
                ? 'Off'
                : '${pauseLabel(pause.reason)} since ${dm(pause.from)}',
            onTap: () async {
              final v = await pickOption<String>(
                context,
                title: 'Pause training',
                options: ['ill', 'travel', if (pause != null) 'resume'],
                label: (o) => switch (o) {
                  'ill' => 'Ill · rest, no plan changes',
                  'travel' => 'Travelling · jet lag and odd sleep',
                  _ => 'Resume · back to normal from today',
                },
                selected: pause?.reason.name,
              );
              if (v == null) return;
              if (v == 'resume') {
                await endPause(db);
              } else {
                await startPause(db, PauseReason.values.byName(v));
              }
              ref.invalidate(todayProvider);
              if (context.mounted) {
                showTempoToast(
                  context,
                  v == 'resume'
                      ? 'Welcome back. Baselines pick up from today.'
                      : 'Paused. Scores still show; baselines and the plan hold.',
                );
              }
            },
          ),
        ]),
        group('Band settings', [
          ListRow(
            'Heart rate',
            value: hrEvery == 1 ? 'Every minute' : 'Every $hrEvery min',
            onTap: !paired
                ? null
                : () async {
                    final m = await pickOption<int>(
                      context,
                      title: 'All-day heart rate',
                      options: SettingsCommands.hrIntervalChoices,
                      label: (m) => m == 1
                          ? 'Every minute (best scores)'
                          : 'Every $m min (longer battery)',
                      selected: hrEvery,
                    );
                    if (m == null || !context.mounted) return;
                    await db.putSetting(hrIntervalKey, '$m');
                    if (context.mounted) {
                      await bandAction(context, () => writeBandSettings(ref));
                    }
                  },
          ),
          ListRow(
            'Sleep detection',
            value: sleepAssist ? 'On · HR-assisted' : 'Motion only',
            onTap: !paired
                ? null
                : () async {
                    final on = await pickOption<bool>(
                      context,
                      title: 'Sleep detection',
                      options: const [true, false],
                      label: (v) => v
                          ? 'HR-assisted · stages incl. REM (best)'
                          : 'Motion only · a little more battery',
                      selected: sleepAssist,
                    );
                    if (on == null || on == sleepAssist || !context.mounted) {
                      return;
                    }
                    await bandAction(context, () async {
                      final r = await writeBandSetting(
                        ref,
                        'Sleep detection',
                        (l) => l.band.setSleepAssist(on),
                      );
                      await db.putSetting(Keys.sleepAssist, on ? '1' : '0');
                      return r;
                    });
                  },
          ),
          ListRow(
            'Stress monitoring',
            chevron: false,
            trailing: TempoSwitch(
              label: 'Stress monitoring',
              value: stressOn,
              onChanged: !paired
                  ? null
                  : (v) => bandAction(context, () async {
                      final r = await writeBandSetting(
                        ref,
                        'Stress monitoring',
                        (l) => l.band.setStressMonitoring(v),
                      );
                      await db.putSetting(Keys.stressMonitor, v ? '1' : '0');
                      return r;
                    }),
            ),
          ),
          ListRow(
            'Worn on',
            value: p.wornOn,
            onTap: () async {
              final w = await pickOption<String>(
                context,
                title: 'Worn on',
                options: const ['Left wrist', 'Right wrist'],
                label: (s) => s,
                selected: p.wornOn,
              );
              if (w == null || w == p.wornOn) return;
              await save(p.copyWith(wornOn: w));
              if (paired && context.mounted) {
                await bandAction(
                  context,
                  () => writeBandSetting(
                    ref,
                    'Wrist',
                    (l) => l.band.setWearLocation(left: w != 'Right wrist'),
                  ),
                );
              }
            },
          ),
          if (Platform.isAndroid)
            ListRow(
              'Background sync',
              sub: extras?.batteryExempt ?? true
                  ? null
                  : 'Battery optimisation can stop overnight syncs',
              value: extras?.batteryExempt ?? true ? 'Allowed' : 'Restricted',
              onTap: () async {
                await BackgroundGuard.requestBatteryExemption();
                ref.invalidate(_profileExtrasProvider);
              },
            ),
          ListRow(
            'Workout buzz cues',
            chevron: false,
            trailing: TempoSwitch(
              label: 'Workout buzz cues',
              value: buzz,
              onChanged: (v) => db.putSetting(Keys.buzzCues, v ? '1' : '0'),
            ),
          ),
        ]),
        group('Notifications', [
          ListRow(
            'Tempo Coach',
            value: 'Nudges, slots',
            onTap: () => push(context, const CoachSettingsScreen()),
          ),
          ListRow(
            'Morning call',
            value: morning == 'off' ? 'Off' : clock12(parseHm(morning)!),
            onTap: () async {
              final opts = [
                'off',
                '06:00',
                '06:30',
                '07:00',
                '07:30',
                '08:00',
                '08:30',
                '09:00',
              ];
              final v = await pickOption<String>(
                context,
                title: 'Morning call',
                options: opts,
                label: (o) => o == 'off' ? 'Off' : clock12(parseHm(o)!),
                selected: morning,
              );
              if (v == null) return;
              if (v != 'off') {
                await TempoNotifications.instance.requestPermission();
              }
              await db.putSetting(Keys.morningCall, v);
              await rescheduleNotifications(db, await loadToday(db));
            },
          ),
          ListRow(
            'Bedtime nudge',
            value: nudge == 'off' ? 'Off' : '$nudge min before target',
            onTap: () async {
              final v = await pickOption<String>(
                context,
                title: 'Bedtime nudge',
                options: const ['off', '15', '30', '45', '60'],
                label: (o) => o == 'off' ? 'Off' : '$o min before target',
                selected: nudge,
              );
              if (v == null) return;
              if (v != 'off') {
                await TempoNotifications.instance.requestPermission();
              }
              await db.putSetting(Keys.bedtimeNudge, v);
              await rescheduleNotifications(db, await loadToday(db));
            },
          ),
        ]),
        group('Your data', [
          ListRow(
            'Weekly report',
            value: 'Share card',
            onTap: () => push(context, const WeeklyReportScreen()),
          ),
          ListRow(
            'Export',
            value: 'CSV or JSON',
            onTap: () async {
              final f = await pickOption<String>(
                context,
                title: 'Export all data',
                options: const ['csv', 'json'],
                label: (o) =>
                    o == 'csv' ? 'CSV · one file per table' : 'JSON · one file',
              );
              if (f == null) return;
              final files = <XFile>[];
              if (f == 'csv') {
                final dir = await exportAll(db);
                files.addAll([
                  for (final e in dir.listSync().whereType<File>())
                    XFile(e.path, mimeType: 'text/csv'),
                ]);
              } else {
                files.add(
                  XFile(
                    (await exportAllJson(db)).path,
                    mimeType: 'application/json',
                  ),
                );
              }
              await SharePlus.instance.share(
                ShareParams(files: files, subject: 'Tempo export'),
              );
            },
          ),
          ListRow(
            'Backups',
            value: backupSummary(
              ref.watch(settingProvider(Keys.lastBackup)).value,
            ),
            onTap: () => push(context, const BackupsScreen()),
          ),
          ListRow(
            healthName,
            sub: 'Write workouts and sleep · never reads',
            chevron: false,
            trailing: TempoSwitch(
              label: healthName,
              value: healthOn,
              onChanged: (v) async {
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
          ListRow(
            'Re-pair or change band',
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'Re-pair band?',
                body: 'Removes the paired band and its auth key from this phone, then starts pairing. Your data stays.',
                action: 'Continue',
              );
              if (!ok) return;
              await KeyStore().clear();
              await db.putSetting(deviceIdKey, '');
              if (context.mounted) await push(context, const PairingScreen());
            },
          ),
          ListRow(
            'Delete all data',
            color: context.s.recLow,
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'Delete all data?',
                body: 'Deletes every sample, score and workout on this phone. Backups in your backup folder are kept. Tempo closes; reopen it to start fresh.',
                action: 'Delete everything',
                danger: true,
              );
              if (!ok) return;
              await KeyStore().clear();
              await db.close();
              await deleteDatabaseFiles();
              if (!context.mounted) return;
              // Android closes the app; iOS can't, so say what to do.
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (c) => PopScope(
                  canPop: false,
                  child: AlertDialog(
                    title: const Text('All data deleted'),
                    content: const Text(
                      'Close Tempo from the app switcher and reopen it to start fresh.',
                    ),
                  ),
                ),
              );
              await SystemNavigator.pop();
            },
          ),
        ]),
        group('Advanced', [
          ListRow(
            'Rewrite band settings',
            sub: 'Time, profile, wrist, HR interval, sleep, stress',
            onTap: !paired
                ? null
                : () => bandAction(context, () => writeBandSettings(ref)),
          ),
          ListRow(
            'Re-download band history',
            sub: 'Fixes sleep and activity stored at the wrong time',
            onTap: !paired ? null : () => redownloadHistory(context, ref),
          ),
          ListRow(
            'Band explorer',
            sub: 'Read-only survey of what your band can share',
            onTap: !paired
                ? null
                : () => push(context, const BandExplorerScreen()),
          ),
          ListRow(
            'Recompute all scores',
            onTap: () async {
              final first = await db.firstMinute();
              if (first == null) {
                if (context.mounted) showTempoToast(context, 'No data yet.');
                return;
              }
              final n = await ScoreService(db).recomputeFrom(first);
              if (context.mounted) {
                showTempoToast(context, 'Recomputed $n days');
              }
            },
          ),
        ]),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Overline('Appearance'),
            ),
            const SizedBox(height: 8),
            TempoSegmented<String>(
              values: const ['system', 'dark', 'light'],
              labels: const ['System', 'Dark', 'Light'],
              selected: mode,
              onChanged: (v) => db.putSetting(Keys.theme, v),
            ),
          ],
        ),
        Text(
          'Tempo 1.0 · A wellness tool, not a medical device.',
          textAlign: TextAlign.center,
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  static Widget _mini(
    BuildContext context,
    String k,
    String v, {
    String? sub,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TempoType.caption.c(context.c.text3)),
      const SizedBox(height: 2),
      Text(
        v,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TempoType.label
            .copyWith(fontSize: 15, color: context.c.text1)
            .tnum,
      ),
      if (sub != null)
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TempoType.caption.c(context.c.text2),
        ),
    ],
  );
}
