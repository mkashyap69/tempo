import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/background_guard.dart';
import 'core/band_link.dart' show deviceIdKey;
import 'core/home_widgets.dart';
import 'core/profile.dart';
import 'design/components.dart';
import 'design/icons.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'design/type.dart';
import 'screens/coach.dart';
import 'screens/journal.dart';
import 'screens/live_workout.dart';
import 'screens/nav.dart';
import 'screens/onboarding.dart';
import 'screens/recovery.dart';
import 'screens/settings.dart';
import 'screens/sleep.dart';
import 'screens/strain.dart';
import 'screens/today.dart';
import 'screens/longevity.dart';
import 'state/live_session.dart';
import 'state/providers.dart';

class TempoApp extends ConsumerWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Tempo',
    debugShowCheckedModeBanner: false,
    theme: tempoTheme(Brightness.light),
    darkTheme: tempoTheme(Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    // Body text follows the system scale up to 1.35×.
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          textScaler: mq.textScaler.clamp(maxScaleFactor: 1.35),
        ),
        child: child!,
      );
    },
    home: const Root(),
  );
}

/// Splash count-in → onboarding (first run) → tabs.
class Root extends ConsumerStatefulWidget {
  const Root({super.key});
  @override
  ConsumerState<Root> createState() => _RootState();
}

class _RootState extends ConsumerState<Root> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final onboarded = ref.watch(settingProvider(Keys.onboarded));
    final paired = ref.watch(settingProvider(deviceIdKey));
    final ready = onboarded.hasValue && paired.hasValue;
    Widget body;
    if (!_splashDone || !ready) {
      body = Splash(
        ready: ready,
        onDone: () => setState(() => _splashDone = true),
      );
    } else if (onboarded.value != '1' && (paired.value ?? '').isEmpty) {
      body = const OnboardingScreen();
    } else {
      body = const Shell();
    }
    return AnimatedSwitcher(
      duration: TempoMotion.base,
      child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
    );
  }
}

/// motion.splashCountIn: the four strokes light in sequence at 100 bpm
/// (600 ms a beat). Light haptic on beat 1 only. Once data is ready by
/// beat 4 it hands over; otherwise the bar loops quietly.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.ready, required this.onDone});
  final bool ready;
  final VoidCallback onDone;
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  int _beat = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
    _t = Timer.periodic(TempoMotion.splashBeat, (_) {
      if (!mounted) return;
      setState(() => _beat = (_beat + 1) % 4);
      if (_beat == 3 && widget.ready) {
        _t?.cancel();
        Future.delayed(TempoMotion.splashBeat, widget.onDone);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.reduceMotion && widget.ready) {
        _t?.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final o = [
      for (var i = 0; i < 4; i++)
        i <= _beat ? 1.0 : (i == _beat + 1 ? .55 : .22),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Center(child: TempoMark(size: 72, opacities: o)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 58 + MediaQuery.of(context).padding.bottom / 2,
            child: Text(
              'tempo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TempoType.family,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -1,
                color: c.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.fab);
  final String label, icon;
  final bool fab;
}

const _tabs = [
  _Tab('Today', TempoIcons.today, true),
  _Tab('Coach', TempoIcons.coach, true),
  _Tab('Longevity', TempoIcons.longevity, false),
  _Tab('Journal', TempoIcons.journal, true),
  _Tab('Profile', TempoIcons.profile, false),
];

/// Five tabs + start button. Syncs on open and on resume (the iOS fallback,
/// since background wakes are not guaranteed).
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<Uri?>? _widgetTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
    _widgetTaps = listenWidgetTaps(_openFromWidget);
  }

  @override
  void dispose() {
    _widgetTaps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Home-screen widget tap: Today tab, then the matching detail screen.
  void _openFromWidget(String target) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    select(0);
    final Widget? screen = switch (target) {
      'recovery' => const RecoveryScreen(),
      'strain' => const StrainScreen(),
      'sleep' => const SleepScreen(),
      _ => null,
    };
    if (screen != null) push(context, screen);
  }

  /// Android: ask once to be left out of battery optimisation, which can
  /// stop overnight syncs. Profile → Background sync asks again any time.
  Future<void> _askBatteryOnce() async {
    final db = ref.read(dbProvider);
    if (await db.setting(Keys.batteryPrompted) == '1') return;
    if ((await db.setting(deviceIdKey) ?? '').isEmpty) return;
    if (await BackgroundGuard.batteryExempt) return;
    await db.putSetting(Keys.batteryPrompted, '1');
    if (!mounted) return;
    final ok = await confirmSheet(
      context,
      title: 'Keep syncing overnight?',
      body: 'Android’s battery optimisation can stop Tempo syncing in the background, so mornings start with old data. Allow Tempo to run in the background?',
      action: 'Allow',
    );
    if (ok) await BackgroundGuard.requestBatteryExemption();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _sync();
  }

  Future<void> _onOpen() async {
    final db = ref.read(dbProvider);
    // Keep widgets, the plan and notifications current even before a sync.
    unawaited(
      ref
          .read(todayProvider.future)
          .then((t) async {
            await updateHomeWidgets(t);
            await rescheduleNotifications(db, t);
          })
          .catchError((Object _) {}),
    );
    _sync();
    unawaited(_askBatteryOnce());
  }

  void _sync() {
    if (ref.read(liveSessionProvider) != null) {
      return; // the workout holds the band
    }
    ref.read(syncProvider.notifier).syncNow();
  }

  void select(int i) {
    if (i != _tab) TempoHaptics.selection();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottom = MediaQuery.of(context).padding.bottom;
    final live = ref.watch(liveSessionProvider);
    // Success haptic once a day when strain enters today's target range.
    ref.listen(todayProvider, (prev, next) {
      final t = next.value;
      if (t == null || t.target.cap || t.target.general) return;
      if (!t.target.contains(t.strain)) return;
      final db = ref.read(dbProvider);
      final key = '${t.day.year}-${t.day.month}-${t.day.day}';
      db.setting(Keys.rangeHaptic).then((last) {
        if (last == key) return;
        TempoHaptics.success();
        db.putSetting(Keys.rangeHaptic, key);
      });
    });
    ref.listen(syncProvider, (prev, next) {
      if (next.message != null && prev?.message != next.message) {
        showTempoToast(
          context,
          next.message!,
          action: _tab == 0 ? null : 'View',
          onAction: () => select(0),
        );
        ref.read(syncProvider.notifier).clearMessage();
      }
    });
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: 49 + bottom,
            child: IndexedStack(
              index: _tab,
              children: [
                TodayScreen(onTab: select),
                const CoachScreen(),
                const LongevityScreen(),
                const JournalScreen(),
                const SettingsScreen(),
              ],
            ),
          ),
          if (live != null && live.phase != LivePhase.ended)
            Positioned(
              left: 20,
              right: 92,
              bottom: 49 + bottom + 16,
              child: _LivePill(state: live),
            ),
          if (_tabs[_tab].fab)
            Positioned(
              right: 20,
              bottom: 49 + bottom + 16,
              child: Pressable(
                label: 'Start a workout',
                onTap: () {
                  TempoHaptics.light();
                  openLive(context, ref, ask: true);
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.text1,
                    shape: BoxShape.circle,
                    boxShadow: c.shadowFloat,
                  ),
                  alignment: Alignment.center,
                  child: TempoIcon(
                    TempoIcons.play,
                    size: 20,
                    color: c.textInverse,
                    fill: true,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NavBar(tab: _tab, onTab: select),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.tab, required this.onTab});
  final int tab;
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 49 + MediaQuery.of(context).padding.bottom,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      alignment: Alignment.topCenter,
      child: Row(
        children: [
          for (final (i, t) in _tabs.indexed)
            Expanded(
              child: Pressable(
                label: t.label,
                selected: i == tab,
                onTap: () => onTab(i),
                child: SizedBox(
                  height: 43,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 3),
                      TempoIcon(
                        t.icon,
                        size: 24,
                        color: i == tab ? c.text1 : c.text3,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.label,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: TempoType.family,
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .1,
                          color: i == tab ? c.text1 : c.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A running workout, minimised: tap to reopen.
class _LivePill extends ConsumerWidget {
  const _LivePill({required this.state});
  final LiveState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final z = state.zone;
    return Pressable(
      label: 'Return to workout',
      onTap: () => present(context, const LiveWorkoutScreen()),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface3,
          borderRadius: BorderRadius.circular(TempoRadii.pill),
          boxShadow: c.shadowFloat,
        ),
        child: Row(
          children: [
            if (z > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.s.zoneColor(z),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Z$z',
                  style: TempoType.label.c(const Color(0xFF0A0B0D)),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.phase == LivePhase.paused
                    ? 'Paused · ${state.title}'
                    : '${state.bpm ?? '—'} bpm · ${state.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TempoType.label.c(c.text1).tnum,
              ),
            ),
            TempoIcon(TempoIcons.chevron, size: 16, color: c.text3, stroke: 2),
          ],
        ),
      ),
    );
  }
}
