import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net_ledger.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'backups.dart';
import 'data_health.dart';
import 'data_sources.dart';
import 'nav.dart';

final netCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(dbTickProvider);
  return netCountsLastWeek(ref.watch(dbProvider));
});

/// v3 You → Privacy: where your data lives and every network call Tempo
/// made this week, counted on the phone.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final source = ref.watch(dataSourceProvider);
    final counts = ref.watch(netCountsProvider).value;
    final total = counts?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    return TempoPage(
      children: [
        const DetailHeader(title: 'Privacy'),
        Text(
          'Your health data stays on this phone.',
          style: TempoType.titleL.c(c.text1),
        ),
        Text(
          'Scores are worked out here. Tempo has no account and sends no health data anywhere.',
          style: TempoType.body.c(c.text2),
        ),
        Section(
          title: 'Where it lives',
          child: CardList(
            children: [
              ListRow(
                'This phone',
                sub: 'Everything Tempo reads and works out',
                chevron: false,
              ),
              ListRow(
                source.isHealth ? source.label : 'Your band',
                sub: source.isHealth
                    ? 'Read only. Tempo never writes back what it read.'
                    : 'Read over Bluetooth with a key kept in the keychain',
                chevron: false,
              ),
              ListRow(
                'Backups',
                sub: 'A file in a folder you choose, on this phone or a cloud folder you pick',
                onTap: () => push(context, const BackupsScreen()),
              ),
            ],
          ),
        ),
        Section(
          title: 'Network calls · last 7 days',
          child: CardList(
            children: [
              for (final e in netKinds.entries)
                ListRow(
                  e.value.$1,
                  sub: e.value.$2,
                  value: '${counts?[e.key] ?? 0}',
                  chevron: false,
                ),
            ],
          ),
        ),
        Text(
          total == 0 ? 'Tempo made no network calls this week.' : 'Counted on this phone as they happen. Weather is the only call today’s Tempo makes, and only while it’s on.',
          style: TempoType.caption.c(c.text3),
        ),
        CardList(
          children: [
            ListRow(
              'Data sources',
              value: source.label,
              onTap: () => push(context, const DataSourcesScreen()),
            ),
            ListRow(
              'Sync health',
              sub: 'Coverage, gaps, sync log',
              onTap: () => push(context, const DataHealthScreen()),
            ),
          ],
        ),
        const SizedBox(height: TempoSpace.s2),
      ],
    );
  }
}
