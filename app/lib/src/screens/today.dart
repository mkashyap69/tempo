import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/data_source.dart';
import '../core/feel.dart';
import '../core/health_reader.dart';
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
        AlsoToday,
        RealignCard,
        RescueCard,
        SessionActions,
        SwapNote,
        coachExtrasProvider;
import 'goal.dart' show TodayGoalLine;
import 'highlight.dart';
import 'journal.dart' show journalProvider;
import 'sleep.dart' show TonightCard;
import 'today_parts.dart';
import 'nav.dart';
import 'pairing.dart';
import 'picks.dart';
import 'recovery.dart';
import 'shared.dart';
import 'strain.dart';
import 'workout_detail.dart';
import 'today_charts.dart';
import 'workouts.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, this.onTab});
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return TempoPage(
      bottom: 140, // clear the start button over the last row
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
  }
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
    final dim = sync.running || (t.stale && !noData);
    final adds = planAdds(t);
    final done =
        t.plan != null &&
        !t.plan!.isRest &&
        (t.status == sc.DayStatus.done || t.status == sc.DayStatus.doneEasier);
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
          await PluginHealthReader().connect();
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

    final call = CallLine(
      t: t,
      noData: noData,
      health: source.isHealth,
      onWhy: noData || t.firstDay ? null : () => showWhySheet(context, t),
    );
    final rings = TodayRings(t: t, noData: noData, dim: dim);

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
        general: t.planRow?.general ?? t.calibrating,
        adds: adds,
        overline: 'Today’s plan',
        chip: statusLabel(t),
        chipColor: statusColor(context, t.status),
        onStart: () => openLive(context, ref, plan: t.plan),
        onWhy: () => push(context, const WorkoutDetailScreen()),
        footer: t.pause != null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SessionActions(t),
                  const Hair(),
                  const PicksEntry(inline: true),
                ],
              ),
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
        if (!restLike && t.plan != null && t.status == sc.DayStatus.missedSlot)
          RescueCard(t),
        if (x != null && x.realign) const RealignCard(),
      ],
    ];
    final insight = now.weekday == DateTime.monday
        ? const WeekReviewCard()
        : const TodayInsightCard();
    final latest = t.workouts.isEmpty ? null : t.workouts.last;

    final List<Widget> body;
    if (noData) {
      body = [call, rings];
    } else {
      switch (phase) {
        case sc.DayPhase.newcomer:
          body = [
            if (checkIn)
              MorningCheckIn(day: t.day, askFeel: askFeel, showDone: morning),
            call,
            rings,
            LearningCard(t: t, checkins: checkins),
            if (!t.firstDay) LessonCard(t: t),
            ?session,
            if (!t.firstDay) LastNightStrip(t: t),
          ];
        case sc.DayPhase.rest:
          body = [
            if (checkIn && !evening)
              MorningCheckIn(day: t.day, askFeel: askFeel, showDone: morning),
            // Evening: tonight is what's left to do; one box, not three.
            if (evening) TonightCard(t: t),
            call,
            if (!evening) ?session,
            rings,
            if (!evening) LastNightStrip(t: t),
          ];
        case sc.DayPhase.morning:
          body = [
            if (showGraduation) const GraduationCard(),
            if (away != null) WelcomeBackCard(days: away),
            if (checkIn)
              MorningCheckIn(day: t.day, askFeel: askFeel, showDone: morning),
            call,
            rings,
            ?session,
            ...coachNotes,
            insight,
            const TodayGoalLine(),
            const WeekRow(),
            LastNightStrip(t: t),
          ];
        case sc.DayPhase.day:
          body = [
            if (checkIn)
              MorningCheckIn(day: t.day, askFeel: askFeel, showDone: morning),
            call,
            ?session,
            ...coachNotes,
            DayProgress(t: t),
            rings,
            insight,
            if (x != null && t.pause == null) AlsoToday(x),
            const TodayGoalLine(),
            const WeekRow(),
          ];
        case sc.DayPhase.done:
          body = [
            call,
            ?session,
            if (latest != null) RecoveryHrCard(workoutId: latest.id),
            ...coachNotes,
            TonightLine(t: t),
            rings,
            insight,
            TomorrowRow(t: t),
          ];
        case sc.DayPhase.evening:
          body = [
            TonightCard(t: t),
            TodayInOneLine(t: t),
            if (!done) ?session,
            ...coachNotes,
            rings,
            TomorrowRow(t: t),
          ];
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
                  Text(
                    phase == sc.DayPhase.evening ? 'Tonight' : 'Today',
                    style: TempoType.titleM.c(c.text1),
                  ),
                ],
              ),
            ),
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
      if (t.workouts.isNotEmpty && phase != sc.DayPhase.evening)
        Section(
          title: 'Today’s workouts',
          trailing: Pressable(
            label: 'All workouts',
            onTap: () => push(context, const WorkoutsScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('All ›', style: TempoType.bodyS.c(c.text2)),
            ),
          ),
          child: CardList(
            children: [
              for (final (i, w) in t.workouts.indexed) ...[
                if (i > 0) const Hair(),
                ActivityRow(w: w),
              ],
            ],
          ),
        ),
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
  });
  final sc.Session session;

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
                const SizedBox(width: 6),
              ],
              TempoBadge(general ? 'General' : 'Personal'),
            ],
          ),
          const SizedBox(height: 14),
          Text(session.title, style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            why != null
                ? '$lead${session.minutes} min$zones · +${session.strainLo > 0 ? (adds - 1).clamp(1, 21).round() : 1} to +${(adds + 1).round()} strain'
                : '$lead${session.minutes} min$zones · adds ~${adds.round()} strain',
            style: TempoType.bodyS.c(c.text2).tnum,
          ),
          const SizedBox(height: 14),
          if (strength)
            Text(strengthLine, style: TempoType.bodyS.c(c.text1))
          else
            IntervalBars(segments: segs),
          if (why == null) ...[
            if (!strength) ...[
              const SizedBox(height: 6),
              Text(session.structure, style: TempoType.caption.c(c.text3).tnum),
            ],
            const SizedBox(height: 14),
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
                TempoButton('Why this?', kind: ButtonKind.ghost, onTap: onWhy),
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
        final title = t.calibrating
            ? 'Why no score yet?'
            : t.recovery == null
            ? 'Today'
            : 'Why ${t.recovery!.round()}%?';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TempoType.titleM.c(c.text1)),
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
  return t.status == sc.DayStatus.doneEasier
      ? '${t.plan!.title} · done, easier'
      : '${t.plan!.title} · done';
}

String doneSub(TodayData t) => _coveredBy(t) != null
    ? 'Counted as today’s ${t.plan!.title.toLowerCase()}. Keep the rest of the day easy.'
    : 'Nice work. Keep the rest of the day easy.';
