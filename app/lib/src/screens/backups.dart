import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/backup.dart';
import '../core/format.dart';
import '../core/profile.dart' show Keys;
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// Builds the backup service; tests override it with a temp folder.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(dbProvider)),
);

final _folderProvider = FutureProvider<BackupLocation>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(backupServiceProvider).current();
});

String _when(DateTime t) => DateFormat('EEE d MMM, h:mm a').format(t);
String _size(int? b) => b == null
    ? ''
    : b < 1024 * 1024
    ? '${(b / 1024).round()} KB'
    : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

/// Restores [bytes] and says what came back, for a toast.
Future<String> restoreMessage(WidgetRef ref, List<int> bytes) async {
  try {
    final r = await restoreBackup(ref.read(dbProvider), bytes);
    final days = (r.minutes / 1440).toStringAsFixed(r.minutes < 14400 ? 1 : 0);
    return 'Restored ~$days days of data, ${r.workouts} workouts'
        '${r.settings > 0 ? ' and your settings' : ''}';
  } on FormatException catch (e) {
    return '${e.message}. Choose a Tempo backup (.json.gz) or JSON export.';
  } catch (e) {
    return 'Restore failed: $e';
  }
}

/// Backups Tempo can see, with "another folder" and "a file" to look
/// further. Used during onboarding and in Settings → Backups.
class RestorePanel extends ConsumerStatefulWidget {
  const RestorePanel({super.key, this.onboarding = false, this.onRestored});

  /// In onboarding a folder picked to restore from also becomes the
  /// backup folder (that's where this person keeps them).
  final bool onboarding;
  final VoidCallback? onRestored;

  @override
  ConsumerState<RestorePanel> createState() => _RestorePanelState();
}

class _RestorePanelState extends ConsumerState<RestorePanel> {
  List<FoundBackup>? _found;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    List<FoundBackup> f;
    try {
      f = await ref.read(backupServiceProvider).discover();
    } catch (_) {
      f = const [];
    }
    if (mounted) setState(() => _found = f);
  }

  Future<void> _restore(Future<List<int>> Function() bytes) async {
    setState(() => _busy = true);
    String msg;
    try {
      msg = await restoreMessage(ref, await bytes());
    } catch (e) {
      msg = 'Couldn’t read the backup: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showTempoToast(context, msg);
    if (msg.startsWith('Restored')) widget.onRestored?.call();
  }

  Future<void> _pickFolder() async {
    PickedFolderLocation? f;
    try {
      f = await PickedFolderLocation.pick();
    } catch (e) {
      if (mounted) showTempoToast(context, 'Couldn’t open the folder: $e');
      return;
    }
    if (f == null || !mounted) return;
    final more = await BackupService.findIn(f);
    if (widget.onboarding && more.isNotEmpty) {
      await ref.read(backupServiceProvider).folders.save(f);
    }
    if (!mounted) return;
    setState(() {
      final have = {for (final x in _found ?? <FoundBackup>[]) x.entry.name};
      _found = [...more.where((x) => !have.contains(x.entry.name)), ...?_found];
    });
    if (more.isEmpty) showTempoToast(context, 'No Tempo backups in ${f.name}');
  }

  Future<void> _pickFile() async {
    PlatformFile? f;
    try {
      f = await FilePicker.pickFile(type: FileType.any);
    } catch (_) {}
    if (f == null || !mounted) return;
    final file = f;
    await _restore(() => file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final found = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (found == null)
          Text('Looking for backups…', style: TempoType.bodyS.c(c.text2))
        else if (found.isEmpty)
          Text(
            widget.onboarding
                ? 'No backup found on this phone. If you have one in iCloud Drive or another folder, choose it below.'
                : 'No backups found yet.',
            style: TempoType.bodyS.c(c.text2),
          )
        else
          CardList(
            children: [
              for (final b in found.take(5))
                ListRow(
                  b.entry.madeAt == null
                      ? b.entry.name
                      : _when(b.entry.madeAt!),
                  sub:
                      '${b.location.label}'
                      '${b.entry.size == null ? '' : ' · ${_size(b.entry.size)}'}',
                  value: 'Restore',
                  onTap: _busy
                      ? null
                      : () async {
                          final ok = await confirmSheet(
                            context,
                            title: 'Restore this backup?',
                            body: 'Adds its samples, workouts, journal, plan and settings. Anything already on this phone stays; scores are recomputed.',
                            action: 'Restore',
                          );
                          if (ok) {
                            await _restore(() => b.location.read(b.entry.name));
                          }
                        },
                ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TempoButton(
                'Another folder',
                kind: ButtonKind.secondary,
                onTap: _busy ? null : _pickFolder,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TempoButton(
                'A file',
                kind: ButtonKind.secondary,
                onTap: _busy ? null : _pickFile,
              ),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 10),
          Text('Restoring…', style: TempoType.bodyS.c(c.text2)),
        ],
      ],
    );
  }
}

/// Settings → Backups: where backups go, when the last one ran, and
/// restoring.
class BackupsScreen extends ConsumerWidget {
  const BackupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final folder = ref.watch(_folderProvider).value;
    final lastRaw = ref.watch(settingProvider(Keys.lastBackup)).value;
    final last = DateTime.tryParse((lastRaw ?? '').split('|').first);
    final service = ref.read(backupServiceProvider);
    return TempoPage(
      children: [
        const DetailHeader(title: 'Backups'),
        Text(
          'Tempo saves a backup after a sync, at most every 12 hours, and keeps the last $keepBackups. Nothing leaves the phone unless the folder you choose syncs (iCloud Drive does).',
          style: TempoType.body.c(c.text2),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Backup folder', style: TempoType.caption.c(c.text3)),
              const SizedBox(height: 4),
              Text(folder?.label ?? '…', style: TempoType.label.c(c.text1)),
              if (folder?.goesWithApp ?? false) ...[
                const SizedBox(height: 6),
                Text(
                  'Kept through updates, but deleted with Tempo. To keep backups through a reinstall, choose a folder outside Tempo, such as iCloud Drive.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                last == null ? 'No backup yet' : 'Last backup ${_when(last)}',
                style: TempoType.bodyS.c(c.text2).tnum,
              ),
              const SizedBox(height: 14),
              TempoButton(
                'Back up now',
                expand: true,
                onTap: () async {
                  String msg;
                  try {
                    final e = await service.backupNow();
                    msg = 'Backup saved · ${_size(e.size)}';
                  } catch (e) {
                    msg = 'Backup failed: $e';
                  }
                  if (context.mounted) showTempoToast(context, msg);
                },
              ),
              const SizedBox(height: 8),
              TempoButton(
                'Change folder',
                kind: ButtonKind.secondary,
                expand: true,
                onTap: () async {
                  PickedFolderLocation? f;
                  try {
                    f = await PickedFolderLocation.pick();
                  } catch (e) {
                    if (context.mounted) {
                      showTempoToast(context, 'Couldn’t open the folder: $e');
                    }
                    return;
                  }
                  if (f == null) return;
                  await service.folders.save(f);
                  ref.invalidate(_folderProvider);
                  if (context.mounted) {
                    showTempoToast(context, 'Backups now go to ${f.name}');
                  }
                },
              ),
              if (folder != null && !folder.goesWithApp)
                TempoButton(
                  'Use Tempo’s own folder',
                  kind: ButtonKind.text,
                  expand: true,
                  onTap: () async {
                    await service.folders.clear();
                    ref.invalidate(_folderProvider);
                  },
                ),
            ],
          ),
        ),
        const Overline('Restore'),
        const RestorePanel(),
        Text(
          'Restoring adds to what is here: samples already on this phone are kept, and scores are recomputed.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

/// One-line summary for the Settings row.
String backupSummary(String? lastBackup) {
  final t = DateTime.tryParse((lastBackup ?? '').split('|').first);
  return t == null ? 'Not yet' : ago(DateTime.now().difference(t));
}
