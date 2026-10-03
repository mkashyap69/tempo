import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/band_link.dart';
import '../core/export.dart';
import '../core/key_store.dart';
import '../core/profile.dart';
import '../core/score_service.dart';
import 'format.dart';
import 'providers.dart';
import 'widgets.dart';

final _syncStateProvider = StreamProvider<List<st.SyncStateData>>(
  (ref) => ref.watch(dbProvider).watchSyncState(),
);

final _settingsProvider = FutureProvider<Map<String, String?>>((ref) async {
  final db = ref.watch(dbProvider);
  return {
    for (final k in [hrMaxKey, deviceIdKey, deviceNameKey, 'last_sync'])
      k: await db.setting(k),
  };
});

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
        padding: const EdgeInsets.all(16),
        children: [
          Section('Band', [
            Kv('Name', settings[deviceNameKey] ?? '–'),
            Kv('ID', settings[deviceIdKey] ?? '–'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                try {
                  final profile = await loadProfile(db);
                  if (profile == null) {
                    return toast('No profile saved. Re-pair.');
                  }
                  final link = await BandLink.open(db);
                  try {
                    final failed = await link.band.configure(profile);
                    toast(
                      failed.isEmpty
                          ? 'Band settings written.'
                          : 'Failed: ${failed.join(', ')}',
                    );
                  } finally {
                    await link.close();
                  }
                } catch (e) {
                  toast('$e');
                }
              },
              child: const Text(
                'Rewrite band settings (time, HR 1 min, sleep assist, stress)',
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
