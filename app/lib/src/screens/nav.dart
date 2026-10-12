import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/live_session.dart';
import '../state/providers.dart';
import 'live_workout.dart';
import 'pairing.dart';

/// The selected tab (0 Today, 1 Coach, 2 Trends, 3 Longevity, 4 Profile).
/// The shell follows it, so any screen can switch tabs.
final shellTab = ValueNotifier<int>(0);

/// True while the tab shell is on screen (tests render screens alone).
var shellMounted = false;

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => page));

/// Full-screen modal (m-slow, slides up).
Future<T?> present<T>(BuildContext context, Widget page) =>
    Navigator.of(context, rootNavigator: true).push<T>(
      PageRouteBuilder<T>(
        fullscreenDialog: true,
        transitionDuration: TempoMotion.slow,
        reverseTransitionDuration: TempoMotion.base,
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: TempoMotion.easeInOut)),
          child: child,
        ),
      ),
    );

/// Starts (or reopens) a workout. Handles no band / no permission first.
Future<void> openLive(
  BuildContext context,
  WidgetRef ref, {
  sc.Session? plan,
  sc.Sport? sport,
  bool ask = false,
}) async {
  final live = ref.read(liveSessionProvider);
  if (live != null && live.phase != LivePhase.failed) {
    await present(context, const LiveWorkoutScreen());
    return;
  }
  final paired = ref.read(pairedProvider).value;
  if (paired == null) {
    final go = await confirmSheet(
      context,
      title: 'Pair your band first',
      body: 'Live heart rate comes straight from your Mi Band 6. Pairing takes about 45 seconds.',
      action: 'Pair band',
    );
    if (go && context.mounted) await push(context, const PairingScreen());
    return;
  }
  // A Health source has no band: the session is timed (LiveSession).
  final adapter = ref.read(dataSourceProvider).isHealth
      ? null
      : ref.read(adapterProvider).value;
  if (adapter == BluetoothAdapterState.unauthorized ||
      adapter == BluetoothAdapterState.off) {
    await showTempoSheet<void>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            adapter == BluetoothAdapterState.off
                ? 'Turn on Bluetooth'
                : 'Bluetooth access needed',
            style: TempoType.titleL.c(ctx.c.text1),
          ),
          const SizedBox(height: 8),
          Text(
            'Tempo reads your band directly over Bluetooth. All data stays on this phone.',
            style: TempoType.body.c(ctx.c.text2),
          ),
          const SizedBox(height: 20),
          TempoButton(
            'Allow',
            expand: true,
            onTap: () async {
              Navigator.pop(ctx);
              await requestBluetooth();
            },
          ),
        ],
      ),
    );
    return;
  }
  if (plan == null && sport == null && ask) {
    if (!context.mounted) return;
    final pick = await pickWorkout(context, ref);
    if (pick == null) return;
    plan = pick.$1;
    sport = pick.$2;
  }
  if (!context.mounted) return;
  ref.read(liveSessionProvider.notifier).start(plan: plan, sport: sport);
  await present(context, const LiveWorkoutScreen());
}

/// Triggers the OS Bluetooth prompt: a short scan on Android (it requests
/// SCAN + CONNECT), reading the adapter state on iOS.
Future<void> requestBluetooth() async {
  try {
    await FlutterBluePlus.adapterState.first;
    if (await FlutterBluePlus.isSupported) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 1));
    }
  } catch (_) {}
}

/// FAB sheet: today's suggested session or an open session by sport.
Future<(sc.Session?, sc.Sport?)?> pickWorkout(
  BuildContext context,
  WidgetRef ref,
) async {
  final t = await ref.read(todayProvider.future);
  final likes = t.profile.likes.isEmpty ? sportOrder.toSet() : t.profile.likes;
  if (!context.mounted) return null;
  return showTempoSheet<(sc.Session?, sc.Sport?)>(
    context,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Start a workout', style: TempoType.titleL.c(ctx.c.text1)),
        const SizedBox(height: 16),
        if (t.plan != null && !t.plan!.isRest) ...[
          TempoCard(
            color: ctx.c.surface1,
            onTap: () => Navigator.pop(ctx, (t.plan, t.plan!.sport)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Suggested for today'),
                const SizedBox(height: 6),
                Text(t.plan!.title, style: TempoType.titleM.c(ctx.c.text1)),
                Text(
                  '${t.plan!.minutes} min · ${t.plan!.zones} · guided',
                  style: TempoType.bodyS.c(ctx.c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Overline('Open session'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in sportOrder.where(likes.contains))
              TempoChip(
                sportLabel(s),
                selected: false,
                onTap: () => Navigator.pop(ctx, (null, s)),
              ),
            TempoChip(
              'Other',
              selected: false,
              onTap: () => Navigator.pop(ctx, (null, null)),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// Info button that opens an explainer sheet.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TempoIconButton(
    TempoIcons.info,
    label: label,
    onTap: onTap,
    stroke: 1.75,
  );
}
