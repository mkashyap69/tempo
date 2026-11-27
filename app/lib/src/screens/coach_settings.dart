import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_notifier.dart';
import '../core/home_widgets.dart' show rescheduleNotifications;
import '../core/notifications.dart';
import '../core/profile.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import '../core/build_info.dart';
import '../billing/pro.dart';
import 'paywall.dart';

class _State {
  _State(
    this.kinds,
    this.cap,
    this.slot,
    this.am,
    this.pm,
    this.precise, {
    this.paused = const {},
  });
  final Set<sc.NudgeKind> kinds;

  /// Kinds paused because they changed nothing (V7): (posted, followed).
  final Map<sc.NudgeKind, (int, int)> paused;
  final int cap;
  final String slot;
  final int am, pm;
  final bool precise;
}

final _stateProvider = FutureProvider<_State>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final slots = await loadSlots(db);
  return _State(
    await CoachNotifier.kinds(db),
    int.tryParse(await db.setting(Keys.notifCap) ?? '') ?? 1,
    await db.setting(Keys.coachSlot) ?? '',
    slots.am,
    slots.pm,
    await db.setting(Keys.notifPrecise) == '1',
    paused: _paused(await db.setting(Keys.notifEffectPaused)),
  );
});

Map<sc.NudgeKind, (int, int)> _paused(String? raw) {
  try {
    final m = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (sc.NudgeKind.values.asNameMap()[e.key] case final k?)
          if ('${e.value}'.split('|') case [_, final n, final f])
            k: (int.parse(n), int.parse(f)),
    };
  } catch (_) {
    return {};
  }
}

String pausedWhy(sc.NudgeKind k, (int, int) c) => switch (k) {
  sc.NudgeKind.winddown =>
    'Paused: you were asleep by its bedtime after ${c.$2} of ${c.$1} in the '
        'last 4 weeks. Turn it back on and it stays on for 4 weeks.',
  _ =>
    'Paused: a workout followed ${c.$2} of ${c.$1} in the last 4 weeks. '
        'Turn it back on and it stays on for 4 weeks.',
};

String kindName(sc.NudgeKind k) => switch (k) {
  sc.NudgeKind.brief => 'Morning brief',
  sc.NudgeKind.session => 'Session reminder',
  sc.NudgeKind.missed => 'Missed-session check',
  sc.NudgeKind.lever => 'Daily focus nudge',
  sc.NudgeKind.winddown => 'Wind-down',
  sc.NudgeKind.rpe => 'Rate a detected workout',
  sc.NudgeKind.health => 'Health alert',
  sc.NudgeKind.weekly => 'Weekly look-back',
  sc.NudgeKind.journal => 'Journal reminder',
  sc.NudgeKind.win => 'Wins',
  sc.NudgeKind.weekGoal => 'Week goal check-in',
  sc.NudgeKind.insight => 'Insights',
  sc.NudgeKind.comeback => 'Catch-up after days away',
};

String kindWhen(sc.NudgeKind k) => switch (k) {
  sc.NudgeKind.brief => 'At your morning time, quietly',
  sc.NudgeKind.session => '15 minutes before your slot',
  sc.NudgeKind.missed =>
    'When a morning session wasn’t seen, with an evening option',
  sc.NudgeKind.lever => 'Mid-afternoon, only if you’re behind',
  sc.NudgeKind.winddown => 'Before tonight’s bedtime',
  sc.NudgeKind.rpe => 'After a walk, run or ride Tempo spots',
  sc.NudgeKind.health =>
    'Once, when night heart rate runs high or 2+ body signals are off',
  sc.NudgeKind.weekly => 'Sunday 18:00',
  sc.NudgeKind.journal => '2 h after waking, while yesterday is open',
  sc.NudgeKind.win =>
    'Personal bests and streaks, at most one a day, each kind weekly',
  sc.NudgeKind.weekGoal => 'Wednesday lunch: sessions done and the next one',
  sc.NudgeKind.insight =>
    'Something new in your data, quietly, if you haven’t opened Tempo',
  sc.NudgeKind.comeback => 'After 3 and 7 days away, then never',
};

/// Tempo Coach notifications: which kinds, how many, and your slots.
class CoachSettingsScreen extends ConsumerWidget {
  const CoachSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(_stateProvider).value;
    final pro = ref.watch(proProvider);
    final c = context.c;
    if (st == null) return Scaffold(backgroundColor: c.bg);
    final db = ref.read(dbProvider);
    Future<void> apply() async {
      ref.invalidate(_stateProvider);
      await rescheduleNotifications(db);
    }

    Future<int?> pickTime(String title, int current) => pickOption<int>(
      context,
      title: title,
      options: [for (var m = 5 * 60; m <= 21 * 60; m += 30) m],
      label: fmtHm,
      selected: current,
    );

    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Coach notifications'),
        Text(
          'At most ${st.cap == 0 ? 'no' : st.cap} coach nudge${st.cap == 1 ? '' : 's'} a day on top of the ones you ask for. Nothing between bedtime and waking, and a kind you keep ignoring backs off on its own.',
          style: TempoType.bodyS.c(c.text2),
        ),
        Section(
          title: 'Training time',
          child: CardList(
            children: [
              ListRow(
                'Usual slot',
                value: switch (st.slot) {
                  'am' => 'Morning',
                  'pm' => 'Evening',
                  'flex' => 'Any time',
                  _ => 'From your workouts',
                },
                onTap: () async {
                  final v = await pickOption<String>(
                    context,
                    title: 'When do you usually train?',
                    options: const ['', 'am', 'pm', 'flex'],
                    label: (o) => switch (o) {
                      'am' => 'Morning',
                      'pm' => 'Evening',
                      'flex' => 'Any time (no session reminder)',
                      _ => 'Work it out from my workouts',
                    },
                    selected: st.slot,
                  );
                  if (v == null) return;
                  v.isEmpty
                      ? await db.deleteSetting(Keys.coachSlot)
                      : await db.putSetting(Keys.coachSlot, v);
                  await apply();
                },
              ),
              ListRow(
                'Morning slot',
                value: fmtHm(st.am),
                onTap: () async {
                  final v = await pickTime('Morning slot', st.am);
                  if (v == null) return;
                  await db.putSetting(Keys.coachSlotAm, fmtHm(v));
                  await apply();
                },
              ),
              ListRow(
                'Evening slot',
                value: fmtHm(st.pm),
                onTap: () async {
                  final v = await pickTime('Evening slot', st.pm);
                  if (v == null) return;
                  await db.putSetting(Keys.coachSlotPm, fmtHm(v));
                  await apply();
                },
              ),
            ],
          ),
        ),
        Section(
          title: 'How many',
          child: CardList(
            children: [
              ListRow(
                'Coach nudges a day',
                value: '${st.cap}',
                onTap: () async {
                  final v = await pickOption<int>(
                    context,
                    title: 'Coach nudges a day',
                    options: const [0, 1, 2],
                    label: (o) => switch (o) {
                      0 => 'None — only the ones I ask for',
                      1 => '1 (recommended)',
                      _ => '2',
                    },
                    selected: st.cap,
                  );
                  if (v == null) return;
                  await db.putSetting(Keys.notifCap, '$v');
                  await apply();
                },
              ),
            ],
          ),
        ),
        Section(
          title: 'Kinds',
          child: CardList(
            children: [
              for (final k in sc.NudgeKind.values)
                if (!pro && proNudgeKinds.contains(k))
                  ListRow(
                    kindName(k),
                    sub: '${kindWhen(k)} · Tempo Pro',
                    onTap: () => showPaywall(context, PaywallEntry.coach),
                  )
                else
                  ListRow(
                    kindName(k),
                    sub: st.paused[k] == null
                        ? kindWhen(k)
                        : pausedWhy(k, st.paused[k]!),
                    chevron: false,
                    trailing: TempoSwitch(
                      label: kindName(k),
                      value: st.kinds.contains(k),
                      onChanged: (v) async {
                        if (v) {
                          await TempoNotifications.instance.requestPermission();
                        }
                        if (k == sc.NudgeKind.brief && v) {
                          if (await db.setting(Keys.morningCall) == 'off') {
                            await db.putSetting(Keys.morningCall, '07:00');
                          }
                        }
                        if (k == sc.NudgeKind.winddown && v) {
                          if (await db.setting(Keys.bedtimeNudge) == 'off') {
                            await db.putSetting(Keys.bedtimeNudge, '45');
                          }
                        }
                        await CoachNotifier.setKind(db, k, v);
                        await apply();
                      },
                    ),
                  ),
            ],
          ),
        ),
        if (Platform.isAndroid)
          Section(
            title: 'Android',
            child: CardList(
              children: [
                if (BuildInfo.restrictedAndroidPermissions)
                  ListRow(
                    'Precise reminders',
                    sub: 'Fire on the minute. Android may otherwise delay a reminder by a few minutes to save battery.',
                    chevron: false,
                    trailing: TempoSwitch(
                      label: 'Precise reminders',
                      value: st.precise,
                      onChanged: (v) async {
                        if (v &&
                            !await TempoNotifications.instance
                                .canScheduleExact()) {
                          await TempoNotifications.instance.requestExact();
                        }
                        await db.putSetting(Keys.notifPrecise, v ? '1' : '0');
                        await apply();
                      },
                    ),
                  ),
                ListRow(
                  'Not getting notifications?',
                  sub: 'On Xiaomi, Redmi and POCO phones, turn on Autostart for Tempo and set Battery saver to “No restrictions”.',
                  chevron: false,
                ),
              ],
            ),
          ),
        TempoButton(
          'Send a test notification',
          kind: ButtonKind.secondary,
          expand: true,
          onTap: () async {
            await TempoNotifications.instance.requestPermission();
            await TempoNotifications.instance.test();
          },
        ),
      ],
    );
  }
}
