import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'live_workout_screen.dart';
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
          body: Stack(
            children: [
              IndexedStack(
                index: _tab,
                children: const [
                  TodayScreen(),
                  TrendsScreen(),
                  SettingsScreen(),
                ],
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: _Dock(
                  tab: _tab,
                  onTab: (i) => setState(() => _tab = i),
                  onWorkout: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LiveWorkoutScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.tab,
    required this.onTab,
    required this.onWorkout,
  });
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onWorkout;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData data, {bool on = false, VoidCallback? tap}) =>
        IconButton(
          onPressed: tap,
          icon: Icon(
            data,
            color: on ? const Color(0xFF111113) : const Color(0xFF9C9CA8),
          ),
        );
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            icon(Icons.home_rounded, on: tab == 0, tap: () => onTab(0)),
            icon(Icons.favorite_border, tap: onWorkout),
            icon(Icons.grid_view_rounded, on: tab == 1, tap: () => onTab(1)),
            icon(Icons.more_horiz, on: tab == 2, tap: () => onTab(2)),
          ],
        ),
      ),
    );
  }
}
