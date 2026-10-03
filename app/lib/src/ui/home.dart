import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'journal_screen.dart';
import 'pairing_screen.dart';
import 'providers.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'trends_screen.dart';

/// Pairing until a band is paired; then tabs. Syncs on open and on resume
/// (the iOS fallback, since background wakes are not guaranteed).
class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> with WidgetsBindingObserver {
  int _tab = 0;
  bool _syncedOnOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _maybeSync();
  }

  void _maybeSync() {
    final paired = ref.read(pairedProvider).value;
    if (paired != null && paired.isNotEmpty) {
      ref.read(syncProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedProvider);
    return paired.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (id) {
        if (id == null || id.isEmpty) return const PairingScreen();
        if (!_syncedOnOpen) {
          _syncedOnOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSync());
        }
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: const [
              TodayScreen(),
              TrendsScreen(),
              JournalScreen(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
              NavigationDestination(
                icon: Icon(Icons.show_chart),
                label: 'Trends',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_note),
                label: 'Journal',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
