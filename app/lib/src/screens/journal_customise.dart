import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/journal.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

final _configProvider = FutureProvider<JournalConfig>((ref) async {
  ref.watch(dbTickProvider);
  return loadJournalConfig(ref.watch(dbProvider));
});

String entryGroupName(sc.EntryGroup g) => switch (g) {
  sc.EntryGroup.lifestyle => 'Lifestyle',
  sc.EntryGroup.health => 'Health',
  sc.EntryGroup.supplements => 'Supplements',
  sc.EntryGroup.sleep => 'Sleep',
  sc.EntryGroup.automatic => 'Automatic',
};

/// Journal → Customise: switch entries on or off, search, add your own.
class JournalCustomiseScreen extends ConsumerStatefulWidget {
  const JournalCustomiseScreen({super.key});

  @override
  ConsumerState<JournalCustomiseScreen> createState() => _State();
}

class _State extends ConsumerState<JournalCustomiseScreen> {
  sc.EntryGroup? _group;
  final _search = TextEditingController();
  final _on = <String, bool>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(_configProvider).value;
    final q = _search.text.trim().toLowerCase();
    final entries = cfg == null
        ? const <sc.JournalEntryDef>[]
        : [
            for (final d in cfg.all)
              if ((_group == null || d.group == _group) &&
                  (q.isEmpty ||
                      d.name.toLowerCase().contains(q) ||
                      d.question.toLowerCase().contains(q)))
                d,
          ];
    bool isOn(String k) => _on[k] ?? cfg!.enabled.contains(k);
    return TempoPage(
      gap: 14,
      children: [
        DetailHeader(
          title: 'Customise journal',
          trailing: cfg == null
              ? null
              : TempoBadge('${cfg.all.where((d) => isOn(d.key)).length} on'),
        ),
        TempoField(
          controller: _search,
          label: 'Search',
          onChanged: (_) => setState(() {}),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final g in [null, ...sc.EntryGroup.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TempoChip(
                    g == null ? 'All' : entryGroupName(g),
                    selected: _group == g,
                    height: 36,
                    onTap: () => setState(() => _group = g),
                  ),
                ),
            ],
          ),
        ),
        if (cfg == null)
          const SizedBox(height: 300)
        else if (entries.isEmpty)
          TempoEmpty('Nothing matches “${_search.text}”.')
        else
          CardList(
            children: [
              for (final d in entries)
                ListRow(
                  d.name,
                  sub: d.automatic ? '${d.question} · automatic' : d.question,
                  chevron: false,
                  trailing: TempoSwitch(
                    label: d.name,
                    value: isOn(d.key),
                    onChanged: (v) async {
                      setState(() => _on[d.key] = v);
                      await setEntryEnabled(ref.read(dbProvider), d.key, v);
                    },
                  ),
                ),
            ],
          ),
        TempoButton(
          'Add your own',
          kind: ButtonKind.secondary,
          expand: true,
          onTap: () => _add(context),
        ),
        Text(
          'Automatic entries come from your data and are never asked. Only switched-on entries appear in the morning check-in.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final ctl = TextEditingController();
    final name = await showTempoSheet<String>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your own entry', style: TempoType.titleM.c(ctx.c.text1)),
            const SizedBox(height: 12),
            TempoField(
              controller: ctl,
              label: 'Name, e.g. Hot yoga',
              autofocus: true,
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              'Asked as a yes or no each morning.',
              style: TempoType.caption.c(ctx.c.text2),
            ),
            const SizedBox(height: 16),
            TempoButton(
              'Add',
              expand: true,
              onTap: ctl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctl.text.trim()),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty) return;
    await addCustomEntry(ref.read(dbProvider), name);
    if (context.mounted) showTempoToast(context, '“$name” added');
  }
}
