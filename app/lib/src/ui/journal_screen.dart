import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import 'providers.dart';

const journalTags = {
  'alcohol': 'Alcohol',
  'late_meal': 'Late meal',
  'caffeine_late': 'Caffeine after 2 pm',
  'screens_in_bed': 'Screens in bed',
  'ill': 'Feeling ill',
  'stressed': 'Stressful day',
};

final _journalProvider = FutureProvider.family<List<st.JournalData>, DateTime>(
  (ref, day) => ref.watch(dbProvider).journalFor(day),
);

/// Yes/no tags each morning, about yesterday.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yesterday = dayOf(DateTime.now()).subtract(const Duration(days: 1));
    final entries = ref.watch(_journalProvider(yesterday));
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          final values = {for (final r in rows) r.tag: r.value};
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Yesterday, did you…'),
              ),
              for (final e in journalTags.entries)
                SwitchListTile(
                  title: Text(e.value),
                  value: values[e.key] ?? false,
                  onChanged: (v) async {
                    await ref.read(dbProvider).setJournal(yesterday, e.key, v);
                    ref.invalidate(_journalProvider(yesterday));
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
