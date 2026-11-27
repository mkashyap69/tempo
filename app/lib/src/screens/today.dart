import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/data_source.dart';
import '../core/demo.dart' show demoMode, healthReader;
import '../core/feel.dart';
import '../core/format.dart';
import '../core/profile.dart' show Keys;
import '../core/pause.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach_parts.dart' show statusLabel, statusColor;
import 'everyday_cards.dart';
import 'coach_parts.dart'
    show
        RealignCard,
        RescueCard,
        SessionActions,
        planRescue,
        rescueFolds,
        SlotHintCard,
        SwapNote,
        coachExtrasProvider;
import 'highlight.dart';
import 'journal.dart' show journalProvider;
import 'sleep.dart' show SleepScreen, TonightCard;
import 'strain.dart' show StrainScreen;
import 'today_parts.dart';
import 'today_v3.dart';
import 'move_skip.dart' show showMoveOrSkipSheet;
import 'nav.dart';
import 'notes.dart' show ReflectFollowUpCard;
import 'pairing.dart';
import 'picks.dart';
import 'recovery.dart';
import 'shared.dart';
import 'weather_backdrop.dart';
import 'workout_detail.dart';
import 'today_charts.dart';
import 'today_more.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, this.onTab});
  final ValueChanged<int>? onTab;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// P9: the big rings are scrolled away, so the mini rings show.
  final _away = ValueNotifier(false);

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _away.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final sync = ref.watch(syncProvider);
    final paired = ref.watch(pairedProvider).value != null;
    final source = ref.watch(dataSourceProvider);
    final adapter = source.isHealth ? null : ref.watch(adapterProvider).value;
    ref.watch(minuteClockProvider);
    final noPermission =
        adapter == BluetoothAdapterState.unauthorized ||
        sync.problem == SyncProblem.noPermission;
    final back = ref.watch(todayBackProvider);
    if (back > 0) {
      return TempoPage(
        bottom: 140,
        children: pastDayChildren(context, ref, back),
      );
    }
    final page = TempoPage(
      gap: 14, // v3: the canvas's tighter rhythm between cards
      bottom: 140, // clear the start button over the last row
      backdrop: const WeatherBackdrop(), // D3: nothing when weather is off
      overlay: Positioned(
        top: MediaQuery.paddingOf(context).top,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<bool>(
          valueListenable: _away,
          // Out of the tree while hidden, not just transparent.
          builder: (context, away, _) => AnimatedSwitcher(
            duration: TempoMotion.base,
            child: away
                ? MiniRingsBar(t: t, onTap: _toTop)
                : const SizedBox.shrink(),
          ),
        ),
      ),
      onRefresh: paired
          ? () {
              TempoHaptics.light(); // pull-to-sync threshold reached
              return ref.read(syncProvider.notifier).syncNow();
            }
          : null,
      children: TodayBody.build(
        context,
        ref,
        t,
        sync: sync,
        paired: paired,
        noPermission: noPermission,
        source: source,
      ),
    );
    return MiniRingsScope(report: _report, child: page);
  }

  ScrollPosition? _position;
  double? _awayAt;

  void _report(ScrollPosition p, double awayAt) {
    if (p != _position) {
      _position?.removeListener(_onScroll);
      _position = p..addListener(_onScroll);
    }
    _awayAt = awayAt;
    _onScroll();
  }

  void _onScroll() {
    final p = _position, at = _awayAt;
    if (p == null || at == null || !p.hasPixels) return;
    _away.value = p.pixels > at;
  }

  void _toTop() => _position?.animateTo(
    0,
    duration: TempoMotion.base,
    curve: TempoMotion.easeOut,
  );
}

/// Today's content, also used by tests and the light/dark variants.
abstract final class TodayBody {
  static List<Widget> build(
    BuildContext context,
    WidgetRef ref,
    TodayData t, {
    required SyncStatus sync,
    required bool paired,
    required bool noPermission,
    DataSource source = DataSource.band,
  }) {
    final c = context.c;
    final noData = !paired || noPermission;
    final failed =
        !sync.running &&
        (sync.problem == SyncProblem.failed ||
            sync.problem == SyncProblem.healthUnreadable);
    final dim = sync.running || ((t.stale || failed) && !noData);
    final adds = planAdds(t);
    final done =
        t.plan != null &&
        !t.plan!.isRest &&
        (t.status == sc.DayStatus.done ||
            t.status == sc.DayStatus.doneEasier ||
            t.status == sc.DayStatus.doneHarder);
    // Asked before the call and the rings, so the score can't sway it.
    final now = appNow();
    final felt = ref.watch(feelProvider(st.dateKey(t.day)));
    final askFeel =
        !noData &&
        felt.hasValue &&
        felt.value == null &&
        now.hour < feelAskUntilHour &&
        st.dateKey(now) == st.dateKey(t.day);

    String syncText;
    if (!paired) {
      syncText = 'Not paired';
    } else if (noPermission) {
      syncText = 'No access';
    } else if (sync.running) {
      syncText = 'Syncing…';
    } else if (failed && t.lastSync != null) {
      // The numbers stay; say when they're from.
      syncText = 'As of ${clockOf(t.lastSync!)}';
    } else if (sync.problem == SyncProblem.failed) {
      syncText = 'Sync failed';
    } else if (sync.problem == SyncProblem.healthUnreadable) {
      syncText = 'Health locked';
    } else if (sync.problem == SyncProblem.disconnected ||
        sync.problem == SyncProblem.busy) {
      syncText = 'Not connected';
    } else if (t.lastSync == null) {
      syncText = 'Never synced';
    } else if (t.stale) {
      syncText = ago(t.syncAge!);
    } else {
      syncText = 'Synced ${ago(t.syncAge!)}';
    }

    Widget? banner;
    // Minutes another app cleared from the band, from the last sync.
    final clearedRaw = source.isHealth
        ? null
        : ref.watch(settingProvider(Keys.bandCleared)).value;
    final cleared = clearedRaw == null
        ? null
        : int.tryParse(clearedRaw.split('|').last);
    final asOf = t.lastSync == null
        ? ''
        : ' Showing data from ${clockOf(t.lastSync!)}.';
    if (source.isHealth && noPermission) {
      banner = StatusBanner(
        icon: TempoIcons.alert,
        title: '${source.label} access needed',
        body: source == DataSource.appleHealth
            ? 'Tempo reads heart rate, sleep and steps from Apple Health. Turn them on in Settings → Health → Data Access & Devices → Tempo.'
            : 'Tempo reads heart rate, sleep and steps from Health Connect. Allow them, and Tempo reads again.',
        action: 'Allow',
        onAction: () async {
          await healthReader().connect();
          await ref.read(syncProvider.notifier).syncNow();
        },
      );
    } else if (source.isHealth &&
        sync.problem == SyncProblem.healthUnreadable &&
        !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.alert,
        title: '${source.label} couldn’t be read',
        body: source == DataSource.appleHealth
            ? 'iPhone keeps Health data locked while the phone is locked.$asOf'
            : 'Health Connect didn’t answer.$asOf',
        action: 'Retry',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    } else if (source.isHealth &&
        (sync.problem == SyncProblem.failed ||
            sync.problem == SyncProblem.busy) &&
        !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.alert,
        title: sync.problem == SyncProblem.busy
            ? 'Already reading ${source.label}'
            : 'Couldn’t read ${source.label}',
        body: sync.problem == SyncProblem.busy
            ? 'Another read is running. Try again in a moment.'
            : 'Something went wrong reading Health.$asOf',
        action: 'Retry',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    } else if (source.isHealth && t.stale && !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.clock,
        title: 'Scores are ${t.syncAge!.inHours} hours old',
        body:
            'Last read ${clockOf(t.lastSync!)} ${_dayWord(t.lastSync!)}. Make sure your watch has synced to ${source.label}.',
        action: 'Read now',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    } else if (source.isHealth) {
      // Bluetooth and pairing banners are for the band.
    } else if (!paired) {
      banner = StatusBanner(
        icon: TempoIcons.bluetooth,
        title: 'No band paired',
        body: 'Pair your Mi Band 6 to see recovery, strain and sleep. All data stays on this phone.',
        action: 'Pair',
        onAction: () => push(context, const PairingScreen()),
      );
    } else if (noPermission) {
      banner = StatusBanner(
        icon: TempoIcons.bluetooth,
        title: 'Bluetooth access needed',
        body: 'Tempo reads your band directly over Bluetooth. All data stays on this phone.',
        action: 'Allow',
        onAction: requestBluetooth,
      );
    } else if (sync.problem == SyncProblem.failed && !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.alert,
        title: 'Sync didn’t finish',
        body:
            'The band stopped responding${sync.failedPct == null ? '' : ' at ${sync.failedPct}%'}.$asOf',
        action: 'Retry',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    } else if ((sync.problem == SyncProblem.disconnected ||
            sync.problem == SyncProblem.busy) &&
        !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.bluetooth,
        title: sync.problem == SyncProblem.busy
            ? 'Band busy'
            : 'Band not connected',
        body: sync.problem == SyncProblem.busy
            ? 'Another sync is holding the band. Try again in a moment.'
            : '${asOf.trim()} Check Bluetooth and keep the band nearby.'.trim(),
        action: 'Reconnect',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    } else if (cleared != null && !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.alert,
        title: 'Another app is clearing your band',
        body:
            'An app such as Mi Fitness or Zepp Life read the band and erased its history, so Tempo missed ${hmSpaced(cleared / 60)}. Close it and turn off its Bluetooth access (iPhone: Settings → Mi Fitness → Bluetooth). Don’t remove the band inside it: that changes the auth key.',
        action: 'Got it',
        onAction: () => ref.read(dbProvider).deleteSetting(Keys.bandCleared),
      );
    } else if (t.stale && !sync.running) {
      banner = StatusBanner(
        icon: TempoIcons.clock,
        title: 'Scores are ${t.syncAge!.inHours} hours old',
        body:
            'Last sync ${clockOf(t.lastSync!)} ${_dayWord(t.lastSync!)}. Open Tempo near your band to refresh.',
        action: 'Sync',
        onAction: () => ref.read(syncProvider.notifier).syncNow(),
      );
    }
    final pause = t.pause;
    if (banner == null && pause != null) {
      banner = StatusBanner(
        icon: TempoIcons.clock,
        title: 'Paused · ${pauseLabel(pause.reason).toLowerCase()}',
        body: 'Scores still show. Baselines and the plan hold still until you resume.',
        action: 'Resume',
        onAction: () async {
          await endPause(ref.read(dbProvider));
          ref.invalidate(todayProvider);
        },
      );
    }

    // What Today leads with: the first weeks, a rest day, or the clock.
    final restLike = t.restDay || t.state == sc.DayState.rest;
    final phase = noData
        ? sc.DayPhase.morning
        : sc.dayPhase(
            nowMinute: now.hour * 60 + now.minute,
            bedtimeMinute: t.bedtimeMinute,
            firstDay: t.firstDay,
            calibrating: t.calibrating,
            restDay: restLike,
            sessionDone: done,
          );
    final evening =
        phase == sc.DayPhase.evening ||
        (restLike &&
            sc.dayPhase(
                  nowMinute: now.hour * 60 + now.minute,
                  bedtimeMinute: t.bedtimeMinute,
                ) ==
                sc.DayPhase.evening);
    final morning = now.hour < feelAskUntilHour;
    final checkIn = !noData && !t.firstDay;
    final graduated = ref.watch(settingProvider(Keys.graduated));
    final showGraduation =
        !noData &&
        !t.calibrating &&
        t.nights >= 14 &&
        graduated.hasValue &&
        graduated.value != '1' &&
        t.history.where((d) => !d.calibrating).length < 7;
    final away = noData ? null : daysAway(t);
    final checkins = ref.watch(journalProvider).value?.count ?? 0;
    final x = ref.watch(coachExtrasProvider).value;

    // v3: the call is a card under the rings (word, sentence, signals).
    final call = CallCard(
      t: t,
      noData: noData,
      health: source.isHealth,
      onWhy: noData || t.firstDay ? null : () => showWhySheet(context, t),
    );
    // Rating the morning (and Replay) draws the rings in again.
    // P9: the anchor shows the mini rings once these scroll away.
    final rings = RingsAnchor(
      child: TodayRings(
        key: ValueKey('rings-${felt.value}-${ref.watch(ringsReplayProvider)}'),
        t: t,
        noData: noData,
        dim: dim,
      ),
    );

    // D4: when the planned session simply moves later today, the plan card
    // says so itself instead of a second "Still time today" card.
    final fold = !noData && t.pause == null && rescueFolds(t) ? t.rescue : null;
    // Today's session: done, a rest day, or the plan with its actions and
    // the alternatives inside the card.
    Widget? session;
    if (!noData && !t.firstDay && done) {
      session = _DoneCard(
        title: doneTitle(t),
        sub: doneSub(t),
        onTap: () => push(context, const WorkoutDetailScreen()),
      );
    } else if (!noData && restLike) {
      session = RestCard(
        why: t.rhrFlag == sc.RhrFlag.illness
            ? 'Your night signals point to rest. Light movement only — strain under ${t.target.hi.round()}.'
            : null,
        onStart: () =>
            openLive(context, ref, plan: sc.sessionTemplate('easy_walk')),
      );
    } else if (!noData && !t.firstDay && t.plan != null && !t.plan!.isRest) {
      session = WorkoutCard(
        session: t.plan!,
        plain: true,
        when: fold == null
            ? null
            : 'Still time today · best around ${fmtHm(fold.start!)}',
        onWatch: source.isHealth,
        paces: t.profile.vdot == null
            ? null
            : sc.sessionPaces(
                t.plan!,
                t.profile.vdot!,
                miles: !t.profile.metric,
              ),
        general: t.planRow?.general ?? t.calibrating,
        adds: adds,
        overline: 'Today’s plan',
        chip: statusLabel(t),
        chipColor: statusColor(context, t.status),
        onStart: () => openLive(context, ref, plan: t.plan),
        onWhy: () => push(context, const WorkoutDetailScreen()),
        // D2: why and move-or-skip sit under Start, not behind More.
        footer: WhyMoveRow(
          onWhy: () => push(context, const WorkoutDetailScreen()),
          onMove:
              t.pause == null &&
                  (t.status == sc.DayStatus.pending ||
                      t.status == sc.DayStatus.moved ||
                      fold != null)
              ? () => showMoveOrSkipSheet(context, ref, t.day)
              : null,
          planLabel: fold == null ? null : 'Plan for ${fmtHm(fold.start!)}',
          onPlan: fold == null ? null : () => planRescue(ref, t),
        ),
        more: t.pause == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SessionActions(t, moveOrSkip: false),
                  const SizedBox(height: 14),
                  const Hair(),
                  const PicksEntry(inline: true),
                ],
              )
            : null,
      );
    }
    // A planned rest day has no plan card; the picks stand on their own.
    if (session == null &&
        !noData &&
        !t.firstDay &&
        !done &&
        t.pause == null &&
        (phase == sc.DayPhase.morning || phase == sc.DayPhase.day)) {
      session = const PicksEntry();
    }
    // What the coach did to today: a counted swap, a rescue, a realign.
    final coachNotes = <Widget>[
      if (!noData && t.pause == null && !t.firstDay) ...[
        SwapNote(t),
        if (!restLike &&
            t.plan != null &&
            t.status == sc.DayStatus.missedSlot &&
            fold == null)
          RescueCard(t),
        if (x != null && x.realign) const RealignCard(),
        if (x?.slotHint case final h?) SlotHintCard(h),
      ],
    ];
    final insight = now.weekday == DateTime.monday
        ? const WeekReviewCard()
        : const TodayInsightCard();
    final latest = t.workouts.isEmpty ? null : t.workouts.last;
    // D3: after a workout marked sore or painful, what the plan can do.
    const followUp = ReflectFollowUpCard();

    // Rings first, then the day's one line, then the session (31 Oct
    // layout: no repeated numbers, no "Your day so far", no "Also today").
    // v3 (canvas "Today"): rings, the call, today's move, what the coach
    // changed, one insight, the week. The day-so-far timeline and
    // yesterday's questions are off Today (owner, 0.6.1: too crowded); the
    // journal is under (+) → Check in. Streaks and moments,
    // last time, tiles, the sleep plan and last night live on Health; the
    // goal on Train.
    // 0.7.0: where Your day so far was, one card that changes with the
    // day: effort left (taps through to Strain), then tonight (to Sleep).
    final nextUp = NextUpCard(
      t: t,
      onTap: () => push(
        context,
        now.hour * 60 + now.minute >= sc.nextUpTonightFrom
            ? const SleepScreen()
            : const StrainScreen(),
      ),
    );
    final List<Widget> body;
    if (noData) {
      body = [rings, call];
    } else {
      switch (phase) {
        case sc.DayPhase.newcomer:
          body = [
            if (checkIn)
              MorningCheckIn(
                journal: false,
                day: t.day,
                askFeel: askFeel,
                showDone: morning,
                recovery: t.stale ? null : t.recovery,
              ),
            rings,
            call,
            LearningCard(t: t, checkins: checkins),
            if (!t.firstDay) LessonCard(t: t),
            ?session,
          ];
        case sc.DayPhase.rest:
          body = [
            if (checkIn && !evening)
              MorningCheckIn(
                journal: false,
                day: t.day,
                askFeel: askFeel,
                showDone: morning,
                recovery: t.stale ? null : t.recovery,
              ),
            rings,
            if (evening) TonightCard(t: t) else call,
            if (!evening) ?session,
            if (!evening) nextUp,
            if (!evening) insight,
            if (!evening) const WeekRow(),
          ];
        case sc.DayPhase.morning:
        case sc.DayPhase.day:
          body = [
            if (phase == sc.DayPhase.morning && showGraduation)
              const GraduationCard(),
            if (phase == sc.DayPhase.morning && away != null)
              WelcomeBackCard(days: away),
            if (checkIn)
              MorningCheckIn(
                journal: false,
                day: t.day,
                askFeel: askFeel,
                showDone: morning,
                recovery: t.stale ? null : t.recovery,
              ),
            rings,
            call,
            ?session,
            ...coachNotes,
            followUp,
            nextUp,
            insight,
            const WeekRow(),
          ];
        case sc.DayPhase.done:
          body = [
            rings,
            call,
            ?session,
            if (latest != null) RecoveryHrCard(workoutId: latest.id),
            ...coachNotes,
            followUp,
            nextUp,
            insight,
            const WeekRow(),
          ];
        case sc.DayPhase.evening:
          body = [rings, TonightCard(t: t), if (!done) ?session, ...coachNotes];
      }
    }

    return [
      // Header
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Overline(dayLong(t.day)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Today',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TempoType.titleM.c(c.text1),
                        ),
                      ),
                      // P7: never mistaken for real data.
                      if (demoMode) ...[
                        const SizedBox(width: 8),
                        const TempoBadge('Demo', small: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!noData) const DayStepper(),
            const SizedBox(width: 4),
            Pressable(
              label: 'Sync now',
              onTap: paired
                  ? () => ref.read(syncProvider.notifier).syncNow()
                  : null,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(TempoRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TempoIcon(
                      source.isHealth
                          ? TempoIcons.heartRate
                          : TempoIcons.bandPill,
                      size: 14,
                      color: c.text2,
                      stroke: 2,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      syncText,
                      style: TextStyle(
                        fontFamily: TempoType.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.text2,
                      ).tnum,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (sync.running) _SyncProgress(sync: sync, source: source),
      ?banner,
      // Quiet unless several overnight signals are off together.
      BodySignalsAlert(onOpen: () => push(context, const RecoveryScreen())),
      ...body,
      // v3: today's activities are in Your day so far; all of them are
      // under Train → Workouts.
    ];
  }

  static String _dayWord(DateTime t) {
    final d = DateTime.now()
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    return d == 0
        ? 'today'
        : d == 1
        ? 'yesterday'
        : dayShort(t);
  }
}

class _SyncProgress extends StatelessWidget {
  const _SyncProgress({required this.sync, required this.source});
  final SyncStatus sync;
  final DataSource source;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.translate(
      offset: const Offset(0, -8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                // A Health read reports percent done, not minutes.
                source.isHealth
                    ? 'Reading ${source.label}${sync.total == 0 ? '…' : ' · ${(sync.fraction * 100).round()}%'}'
                    : sync.connecting || sync.total == 0
                    ? 'Connecting to band…'
                    : 'Reading band · ${sync.read} of ${sync.total} min',
                style: TempoType.bodyS.c(c.text2).tnum,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: sync.total == 0 ? null : sync.fraction,
              backgroundColor: c.trackOff,
              color: c.text1,
            ),
          ),
        ],
      ),
    );
  }
}

/// TempoWorkoutCard.
class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.session,
    required this.general,
    required this.adds,
    required this.overline,
    this.onStart,
    this.onWhy,
    this.onTap,
    this.why,
    this.chip,
    this.chipColor,
    this.footer,
    this.more,
    this.onWatch = false,
    this.paces,
    this.plain = false,
    this.when,
  });

  /// Today's card in plain words (D4): no "Personal" badge, no strain
  /// estimate, and a steady session gets a pace word instead of a one-block
  /// zone bar.
  final bool plain;

  /// When it still fits today ("Still time today · best around 18:00"),
  /// folded in from the rescue card.
  final String? when;

  /// Pace per zone for a run, from your race time (U5).
  final String? paces;
  final sc.Session session;

  /// The source is Apple Health / Health Connect: Tempo can't show live
  /// heart rate, so the watch records the session (U1).
  final bool onWatch;

  /// Folded under a "More" button next to Start, in place of "Why this?":
  /// Today keeps the card to the session and one action (31 Oct).
  final Widget? more;

  /// Status chip (Planned 18:00, Done ✓, …) and actions under the card.
  final String? chip;
  final Color? chipColor;
  final Widget? footer;
  final bool general;
  final double adds;
  final String overline;
  final VoidCallback? onStart, onWhy, onTap;

  /// Compact "why" line + chevron instead of buttons (Coach).
  final String? why;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final segs = [for (final g in session.segments) (g.minutes, g.zone)];
    // Strength has no heart-rate zones to aim for: name the focus and the
    // exercises instead of drawing a zone bar.
    final strength = session.sport == sc.Sport.strength;
    final detail = session.detail;
    final focus = detail is sc.StrengthDetail
        ? sc.focusName(detail.focus)
        : session.note.isEmpty
        ? null
        : '${session.note[0].toUpperCase()}${session.note.substring(1)}';
    final names = detail is sc.StrengthDetail
        ? [for (final e in detail.exercises) e.name]
        : const <String>[];
    final strengthLine = names.isEmpty
        ? 'Log sets as you go; Tempo suggests weights from your last session.'
        : '${names.take(4).join(' · ')}${names.length > 4 ? ' · +${names.length - 4} more' : ''}';
    final sport = strength || session.sport == null
        ? ''
        : '${session.sport!.name[0].toUpperCase()}${session.sport!.name.substring(1)} · ';
    final lead = strength && focus != null ? '$focus · ' : sport;
    final zones = strength ? '' : ' · ${session.zones}';
    // One steady block: the bar would be a single grey slab (D4).
    final steady = plain && !strength && segs.length == 1;
    return TempoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Overline(overline)),
              if (chip != null) ...[
                TempoBadge(chip!, color: chipColor),
                if (!plain || general) const SizedBox(width: 6),
              ],
              if (!plain || general)
                TempoBadge(general ? 'General' : 'Personal'),
            ],
          ),
          const SizedBox(height: 14),
          Text(session.title, style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            plain
                ? '$lead${session.minutes} min'
                : why != null
                ? '$lead${session.minutes} min$zones · +${session.strainLo > 0 ? (adds - 1).clamp(1, 21).round() : 1} to +${(adds + 1).round()} strain'
                : '$lead${session.minutes} min$zones · adds ~${adds.round()} strain',
            style: TempoType.bodyS.c(c.text2).tnum,
          ),
          if (when != null) ...[
            const SizedBox(height: 4),
            Text(when!, style: TempoType.bodyS.c(context.s.recMid)),
          ],
          const SizedBox(height: 14),
          if (strength)
            Text(strengthLine, style: TempoType.bodyS.c(c.text1))
          else if (steady)
            Text(paceWord(segs.first.$2), style: TempoType.bodyS.c(c.text1))
          else
            IntervalBars(segments: segs),
          if (why == null) ...[
            if (!strength) ...[
              if (!steady) ...[
                const SizedBox(height: 6),
                Text(
                  session.structure,
                  style: TempoType.caption.c(c.text3).tnum,
                ),
              ],
              if (paces != null) ...[
                const SizedBox(height: 4),
                Text(paces!, style: TempoType.caption.c(c.text2).tnum),
              ],
              if (onWatch) ...[
                const SizedBox(height: 10),
                Text(
                  'Record it on your watch. Tempo reads it from Health afterwards and ticks it off.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (more != null)
              _StartMore(onStart: onStart, more: more!)
            else
              Row(
                children: [
                  Expanded(
                    child: TempoButton(
                      'Start',
                      icon: TempoIcons.play,
                      expand: true,
                      onTap: onStart,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TempoButton(
                    'Why this?',
                    kind: ButtonKind.ghost,
                    onTap: onWhy,
                  ),
                ],
              ),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text(why!, style: TempoType.bodyS.c(c.text2))),
                TempoIcon(
                  TempoIcons.chevron,
                  size: 18,
                  color: c.text3,
                  stroke: 2,
                ),
              ],
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

/// Start, and "More" that unfolds the rest of the card's actions.
class _StartMore extends StatefulWidget {
  const _StartMore({required this.onStart, required this.more});
  final VoidCallback? onStart;
  final Widget more;

  @override
  State<_StartMore> createState() => _StartMoreState();
}

class _StartMoreState extends State<_StartMore> {
  var _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: TempoButton(
              'Start',
              icon: TempoIcons.play,
              expand: true,
              onTap: widget.onStart,
            ),
          ),
          const SizedBox(width: 10),
          TempoButton(
            _open ? 'Less' : 'More',
            kind: ButtonKind.ghost,
            onTap: () => setState(() => _open = !_open),
          ),
        ],
      ),
      if (_open) ...[const SizedBox(height: 4), widget.more],
    ],
  );
}

class RestCard extends StatelessWidget {
  const RestCard({super.key, required this.onStart, this.why});
  final VoidCallback onStart;

  /// Why today rests, when it isn't low recovery or load.
  final String? why;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    Widget row(String a, String b) => Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(a, style: TempoType.label.c(c.text1))),
          Flexible(
            child: Text(
              b,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TempoType.bodyS.c(c.text2).tnum,
            ),
          ),
        ],
      ),
    );
    return TempoCard(
      color: s.tintRecLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline('▼ Rest day recommended', color: s.recLow),
          const SizedBox(height: 14),
          Text('Let today be easy', style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            why ?? 'Recovery is low or your cardio load is overreaching. Light movement only — strain under 8.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 14),
          CardList(
            radius: TempoRadii.md,
            children: [
              row('Easy walk', '20–30 min · Z1'),
              row('Mobility flow', '15 min · Yoga'),
            ],
          ),
          const SizedBox(height: 14),
          TempoButton(
            'Start easy walk',
            kind: ButtonKind.secondary,
            expand: true,
            onTap: onStart,
          ),
        ],
      ),
    );
  }
}

/// "Why 78%?" — plain answer with the person's own numbers, then evidence.
Future<void> showWhySheet(BuildContext context, TodayData t) =>
    showTempoSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.c;
        final cs = contributors(ctx, t);
        final input = callInput(t);
        final word = sc.callWord(input);
        final shift = sc.callShift(input);
        final title = t.calibrating
            ? 'Why no score yet?'
            : t.recovery == null
            ? 'Today'
            : word != null
            ? 'Why ${sc.callWordLabel(word)} today'
            : 'Why ${t.recovery!.round()}%?';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TempoType.titleM.c(c.text1)),
            if (word != null) ...[
              const SizedBox(height: 14),
              CallLadder(word: word),
            ],
            const SizedBox(height: 14),
            Text(recoveryWhy(t, cs), style: TempoType.body.c(c.text2)),
            const SizedBox(height: 14),
            for (final x in cs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        x.name.replaceAll(', overnight', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TempoType.bodyS.c(c.text1),
                      ),
                    ),
                    if (x.proxy) ...[
                      const SizedBox(width: 6),
                      const TempoBadge('≈ proxy', small: true),
                    ],
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${x.glyph} ${x.verdict.split(' · ').last}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TempoType.bodyS.c(x.color),
                      ),
                    ),
                  ],
                ),
              ),
            if (shift != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(TempoRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What would change it',
                      style: TempoType.caption.c(c.text2),
                    ),
                    const SizedBox(height: 4),
                    Text(shift, style: TempoType.bodyS.c(c.text1)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Recovery uses only body signals. How you feel and your notes shape the advice, never the score.',
                style: TempoType.caption.c(c.text3),
              ),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 4),
            TempoButton(
              'See full breakdown',
              kind: ButtonKind.secondary,
              expand: true,
              onTap: () {
                Navigator.pop(ctx);
                push(context, const RecoveryScreen());
              },
            ),
          ],
        );
      },
    );

/// A steady session's zone in words people use (D4).
String paceWord(int zone) => switch (zone) {
  <= 1 => 'Easy pace you can talk at',
  2 => 'Steady, still able to talk',
  3 => 'Comfortably hard, short sentences only',
  4 => 'Hard, a few words at a time',
  _ => 'All out',
};

/// "Why this session" and "Move or skip" side by side under Start (D2).
class WhyMoveRow extends StatelessWidget {
  const WhyMoveRow({
    super.key,
    required this.onWhy,
    this.onMove,
    this.planLabel,
    this.onPlan,
  });
  final VoidCallback onWhy;
  final VoidCallback? onMove;

  /// "Plan for 18:00", when the session was missed in its slot but still
  /// fits today (folded in from the rescue card, D4).
  final String? planLabel;
  final VoidCallback? onPlan;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (planLabel != null && onPlan != null) ...[
        const SizedBox(height: 2),
        TempoButton(
          planLabel!,
          small: true,
          fontSize: 14,
          kind: ButtonKind.secondary,
          expand: true,
          onTap: onPlan,
        ),
      ],
      // Two outlined buttons under Start: lighter than Start, but clearly
      // tappable (D5).
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: TempoButton(
                'Why this session',
                small: true,
                fontSize: 14,
                kind: ButtonKind.ghost,
                expand: true,
                onTap: onWhy,
              ),
            ),
            if (onMove != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: TempoButton(
                  'Move or skip',
                  small: true,
                  fontSize: 14,
                  kind: ButtonKind.ghost,
                  expand: true,
                  onTap: onMove,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Today's session once it's done: one line instead of the full card.
class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    return TempoCard(
      label: '$title done',
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: s.recHigh.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: TempoIcon(TempoIcons.check, size: 18, color: s.recHigh),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TempoType.label.c(c.text1)),
                const SizedBox(height: 2),
                Text(sub, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}

/// The workout that covered today's plan when it was a different one
/// (a game counted for an easy run), else null.
st.Workout? _coveredBy(TodayData t) {
  final by = t.swap.by;
  if (t.swap.kind != sc.SwapKind.counted || by == null) return null;
  if (by.sport == t.plan?.sport) return null;
  for (final w in t.workouts) {
    if (st.fromTs(w.start) == by.start) return w;
  }
  return null;
}

/// "Easy run · done", or what you actually did: "Sport · 1 h 19 · done".
String doneTitle(TodayData t) {
  final w = _coveredBy(t);
  if (w != null) {
    return '${w.title} · ${hmShort((w.end - w.start) / 3600)} · done';
  }
  return switch (t.status) {
    sc.DayStatus.doneEasier => '${t.plan!.title} · done, easier',
    sc.DayStatus.doneHarder => '${t.plan!.title} · done, harder',
    _ => '${t.plan!.title} · done',
  };
}

String doneSub(TodayData t) => _coveredBy(t) != null
    ? 'Counted as today’s ${t.plan!.title.toLowerCase()}. Keep the rest of the day easy.'
    : 'Nice work. Keep the rest of the day easy.';

/// Rest → Push as five steps, today's lit (v3 Why sheet).
class CallLadder extends StatelessWidget {
  const CallLadder({super.key, required this.word});
  final sc.CallWord word;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    const order = [
      sc.CallWord.rest,
      sc.CallWord.ease,
      sc.CallWord.steady,
      sc.CallWord.build,
      sc.CallWord.push,
    ];
    final lit = switch (word) {
      sc.CallWord.rest => s.recLow,
      sc.CallWord.ease || sc.CallWord.steady => s.recMid,
      _ => s.recHigh,
    };
    return Semantics(
      label: 'Today is ${sc.callWordLabel(word)}, on a scale from Rest to Push',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, w) in order.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: w == word ? lit : c.surface3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sc.callWordLabel(w),
                    maxLines: 1,
                    style: TempoType.caption.c(w == word ? c.text1 : c.text3),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
