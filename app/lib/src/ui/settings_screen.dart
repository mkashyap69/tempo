import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import 'package:band_ble/band_ble.dart';

import '../core/band_link.dart';
import '../core/export.dart';
import '../core/key_store.dart';
import '../core/profile.dart';
import '../core/score_service.dart';
import 'format.dart';
import 'journal_screen.dart';
import 'providers.dart';
import 'widgets.dart';

final _syncStateProvider = StreamProvider<List<st.SyncStateData>>(
  (ref) => ref.watch(dbProvider).watchSyncState(),
);

final _settingsProvider = FutureProvider<Map<String, String?>>((ref) async {
  final db = ref.watch(dbProvider);
  return {
    for (final k in [
      hrMaxKey,
      hrIntervalKey,
      deviceIdKey,
      deviceNameKey,
      'last_sync',
    ])
      k: await db.setting(k),
  };
});

/// Blocks the screen until [body] finishes, then shows the message.
/// A snackbar was easy to miss, so Rewrite looked like a dead button.
Future<void> _showBandResult(
  BuildContext context,
  Future<String> Function() body,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Connecting to the band…')),
          ],
        ),
      ),
    ),
  );
  String message;
  try {
    message = await body();
  } catch (e) {
    message = '$e';
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final settings = ref.watch(_settingsProvider).value ?? {};
    final cursors = ref.watch(_syncStateProvider).value ?? [];
    final sync = ref.watch(syncProvider);
    void toast(String m) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

    Future<bool> confirm(String title, String body) async =>
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 108),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Journal'),
            subtitle: const Text('Morning tags'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const JournalScreen())),
          ),
          Section('Band', [
            Kv('Name', settings[deviceNameKey] ?? '–'),
            Kv('ID', settings[deviceIdKey] ?? '–'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _showBandResult(context, () async {
                final profile = await loadProfile(db);
                if (profile == null) return 'No profile saved. Re-pair.';
                final every = int.tryParse(settings[hrIntervalKey] ?? '') ?? 1;
                final link = await BandLink.open(db);
                try {
                  final failed = await link.band.configure(
                    profile,
                    hrEveryMinutes: every,
                  );
                  return failed.isEmpty
                      ? 'Band settings written.'
                      : 'Not written: ${failed.join(', ')}';
                } finally {
                  await link.close();
                }
              }),
              child: const Text(
                'Rewrite band settings (time, HR interval, sleep assist, stress)',
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                if (!await confirm(
                  'Forget band?',
                  'Removes the paired band and the auth key from this phone. Data stays.',
                )) {
                  return;
                }
                await KeyStore().clear();
                await db.putSetting(deviceIdKey, '');
                ref.invalidate(pairedProvider);
              },
              child: const Text('Forget band and key'),
            ),
          ]),
          Section('Sync', [
            Kv(
              'Last sync',
              settings['last_sync']?.substring(0, 16).replaceFirst('T', ' ') ??
                  'never',
            ),
            for (final c in cursors)
              Kv(
                '  ${c.dataType} up to',
                '${shortDate(st.fromTs(c.lastTs))} ${clock(st.fromTs(c.lastTs))}',
              ),
            if (sync.message != null)
              Text(sync.message!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: sync.running
                  ? null
                  : () => ref.read(syncProvider.notifier).syncNow(),
              child: const Text('Sync now'),
            ),
          ]),
          Section('All-day heart rate', [
            const Text(
              'History stores one heart-rate slot per minute. The band fills '
              'a slot only when it measures. 1 min is the finest that log can '
              'hold. The Workout button is a separate stream, about one '
              'reading per second, and does not fill this log.',
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (final m in SettingsCommands.hrIntervalChoices)
                  ButtonSegment(value: m, label: Text('$m min')),
              ],
              selected: {int.tryParse(settings[hrIntervalKey] ?? '') ?? 1},
              onSelectionChanged: (s) async {
                final minutes = s.first;
                await db.putSetting(hrIntervalKey, '$minutes');
                ref.invalidate(_settingsProvider);
                if (!context.mounted) return;
                await _showBandResult(context, () async {
                  final profile = await loadProfile(db);
                  if (profile == null) {
                    return 'Saved. Re-pair to write it to the band.';
                  }
                  final link = await BandLink.open(db);
                  try {
                    final failed = await link.band.configure(
                      profile,
                      hrEveryMinutes: minutes,
                    );
                    return failed.isEmpty
                        ? 'Measuring every $minutes min.'
                        : 'Saved. Not written: ${failed.join(', ')}';
                  } finally {
                    await link.close();
                  }
                });
              },
            ),
          ]),
          Section('Heart rate max', [
            Text(
              'Starts at 190 and rises automatically when the band records higher. '
              'Current: ${settings[hrMaxKey] ?? '190'} bpm.',
            ),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Set HR max (bpm)'),
              onSubmitted: (v) async {
                final n = int.tryParse(v);
                if (n == null || n < 120 || n > 230) {
                  return toast('Enter 120–230');
                }
                await db.putSetting(hrMaxKey, '$n');
                ref.invalidate(_settingsProvider);
                final first = await db.firstMinute();
                if (first != null) await ScoreService(db).recomputeFrom(first);
                toast('HR max set; scores recomputed.');
              },
            ),
          ]),
          Section('Data', [
            OutlinedButton(
              onPressed: () async {
                final dir = await exportAll(db);
                toast('Exported to ${dir.path}');
              },
              child: const Text('Export all data (CSV)'),
            ),
            OutlinedButton(
              onPressed: () async {
                final first = await db.firstMinute();
                if (first == null) {
                  return toast('No data.');
                }
                final n = await ScoreService(db).recomputeFrom(first);
                toast('Recomputed $n days.');
              },
              child: const Text('Recompute all scores'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                if (!await confirm(
                  'Delete all data?',
                  'Deletes every sample and score on this phone. Export first if you want a copy. The app closes; reopen it to start fresh.',
                )) {
                  return;
                }
                await db.close();
                await deleteDatabaseFiles();
                toast('Deleted. Close and reopen the app.');
              },
              child: const Text('Delete all data'),
            ),
          ]),
        ],
      ),
    );
  }
}
