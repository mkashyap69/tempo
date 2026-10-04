import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../core/pause.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'cardio_load.dart';
import 'nav.dart';
import 'pairing.dart';
import 'recovery.dart';
import 'shared.dart';
import 'sleep.dart';
import 'strain.dart';
import 'workout_detail.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, this.onTab});
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final sync = ref.watch(syncProvider);
    final paired = ref.watch(pairedProvider).value != null;
    final adapter = ref.watch(adapterProvider).value;
    ref.watch(minuteClockProvider);
    final noPermission =
        adapter == BluetoothAdapterState.unauthorized ||
        sync.problem == SyncProblem.noPermission;
    return TempoPage(
      bottom: 100,
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
  }) {
    final c = context.c, s = context.s;
    final noData = !paired || noPermission;
    final dim = sync.running || (t.stale && !noData);
    final (lead, leadColor, rest) = coachLine(
      context,
      t,
      noBand: !paired,
      noPermission: noPermission,
    );
    final adds = planAdds(t);
    final (stripStatus, stripBody) = strainStatus(t, planAdds: adds);

    String syncText;
    if (!paired) {
      syncText = 'Not paired';
    } else if (noPermission) {
      syncText = 'No access';
    } else if (sync.running) {
      syncText = 'Syncing…';
    } else if (sync.problem == SyncProblem.failed) {
      syncText = 'Sync failed';
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
    final asOf = t.lastSync == null
        ? ''
        : ' Showing data from ${clockOf(t.lastSync!)}.';
    if (!paired) {
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

    final meters = _meters(context, t, noData: noData, dim: dim);
    final stack = MediaQuery.textScalerOf(context).scale(1) >= 1.3;

    return [
      // Header
      SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Overline(dayLong(t.day)),
                  const SizedBox(height: 2),
                  Text('Today', style: TempoType.titleM.c(c.text1)),
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
                      TempoIcons.bandPill,
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
      if (sync.running) _SyncProgress(sync: sync),
      ?banner,
      Pressable(
        label: 'Why today’s call',
        onTap: noData || t.firstDay ? null : () => showWhySheet(context, t),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: lead,
                style: TextStyle(color: leadColor),
              ),
              TextSpan(text: rest),
            ],
          ),
          style: TempoType.titleL.c(c.text1),
        ),
      ),
      if (stack)
        Column(
          children: [
            for (final m in meters)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: m),
          ],
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, m) in meters.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: m),
            ],
          ],
        ),
      if (!noData && !t.firstDay)
        TempoCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () => push(context, const StrainScreen()),
          label: 'Strain target',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.target.cap ? 'Strain cap' : 'Strain target',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  TempoBadge(stripStatus),
                ],
              ),
              const SizedBox(height: 10),
              TargetStrip(
                value: t.strain,
                max: 21,
                lo: t.target.lo,
                hi: t.target.hi,
                color: s.strain[1],
              ),
              const SizedBox(height: 10),
              Text(stripBody, style: TempoType.bodyS.c(c.text2)),
            ],
          ),
        ),
      if (!noData && t.restDay)
        RestCard(
          onStart: () =>
              openLive(context, ref, plan: sc.sessionTemplate('easy_walk')),
        )
      else if (!noData && !t.firstDay && t.plan != null && !t.plan!.isRest)
        WorkoutCard(
          session: t.plan!,
          general: t.planRow?.general ?? t.calibrating,
          adds: adds,
          overline: 'Suggested for today',
          onStart: () => openLive(context, ref, plan: t.plan),
          onWhy: () => push(context, const WorkoutDetailScreen()),
        ),
      if (!noData && t.firstDay) const FirstWeekCard(),
      if (!noData)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TempoCard(
                padding: const EdgeInsets.all(14),
                onTap: () => push(context, const CardioLoadScreen()),
                label: 'Cardio load',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('Cardio load'),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${loadGlyph(t.load.status)} ',
                            style: const TextStyle(fontSize: 13),
                          ),
                          TextSpan(text: loadWord(t.load.status)),
                        ],
                      ),
                      style: TempoType.titleM.c(
                        loadColor(context, t.load.status),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.firstDay ? 'Needs 7 days of data' : loadSub(t.load),
                      style: TempoType.caption.c(c.text3),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TempoCard(
                padding: const EdgeInsets.all(14),
                onTap: () => push(context, const SleepScreen()),
                label: 'Bedtime tonight',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('Bedtime tonight'),
                    const SizedBox(height: 6),
                    Text(
                      clock12(t.bedtimeMinute),
                      style: TempoType.titleM.c(c.text1).tnum,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.calibrating || t.firstDay
                          ? 'General target · personalises night 14'
                          : 'For ${hmShort(t.needTonight - t.debt * .5)} need${t.debt > 0.05 ? ' + ${hmShort(t.debt * .5)} debt' : ''}',
                      style: TempoType.caption.c(c.text3),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

  static List<Widget> _meters(
    BuildContext context,
    TodayData t, {
    required bool noData,
    required bool dim,
  }) {
    final c = context.c, s = context.s;
    final numColor = dim ? c.text2 : c.text1;
    final r = t.recovery;
    final Widget rec;
    if (noData || (r == null && !t.calibrating)) {
      rec = ScoreMeter(
        label: 'Recovery',
        value: 0,
        decimals: 0,
        placeholder: '—',
        state: noData ? 'No data' : 'After tonight',
        stateColor: c.text3,
        ticks: 20,
        filled: 0,
        fillColor: c.trackOff,
        caption: '—',
        numColor: c.text3,
        dim: dim,
        onTap: noData ? null : () => push(context, const RecoveryScreen()),
      );
    } else if (t.calibrating) {
      rec = ScoreMeter(
        label: 'Recovery',
        value: t.nights.toDouble(),
        decimals: 0,
        unit: '/14',
        state: 'Calibrating',
        stateColor: c.text2,
        ticks: 14,
        filled: t.nights,
        fillColor: c.text2,
        caption: '${14 - t.nights} nights to baseline',
        numColor: numColor,
        dim: dim,
        onTap: () => push(context, const RecoveryScreen()),
      );
    } else {
      final rhr = t.rhrDelta, st = t.stressDelta;
      final cap = [
        if (rhr != null)
          'RHR ${rhr.round() == 0
              ? '±'
              : rhr > 0
              ? '+'
              : '−'}${rhr.abs().round()}',
        if (st != null)
          'stress ${st > 1
              ? '↑'
              : st < -1
              ? '↓'
              : '→'}',
      ].join(' · ');
      rec = ScoreMeter(
        label: 'Recovery',
        value: r!,
        decimals: 0,
        unit: '%',
        state: recoveryWord(r),
        glyph: recoveryGlyph(r),
        stateColor: s.recoveryFor(r),
        ticks: 20,
        filled: (r / 5).round(),
        fillColor: s.recoveryFor(r),
        caption: cap,
        numColor: numColor,
        dim: dim,
        onTap: () => push(context, const RecoveryScreen()),
        onSettled: TempoHaptics.light,
      );
    }
    final tg = t.target;
    final strain = noData
        ? ScoreMeter(
            label: 'Strain',
            value: 0,
            decimals: 1,
            placeholder: '—',
            state: 'No data',
            stateColor: c.text3,
            ticks: 21,
            filled: 0,
            fillColor: c.trackOff,
            caption: '—',
            numColor: c.text3,
          )
        : TargetMeter(
            label: 'Strain',
            value: t.strain,
            decimals: 1,
            unit: '/21',
            state: 'Live',
            glyph: '●',
            stateColor: s.strain[1],
            ticks: 21,
            filled: t.strain.floor(),
            fillColor: s.strain[1],
            tickColor: (i) => s.strainFor(i.toDouble()),
            targetRange: (tg.lo.round(), tg.hi.round()),
            caption: tg.cap
                ? 'Cap ${tg.hi.round()}'
                : 'Target ${tg.lo.round()}–${tg.hi.round()}',
            numColor: numColor,
            dim: dim,
            liveGrow: true,
            onTap: () => push(context, const StrainScreen()),
          );
    final sp = t.sleepPerf;
    final sleep = noData || sp == null
        ? ScoreMeter(
            label: 'Sleep',
            value: 0,
            decimals: 0,
            placeholder: '—',
            state: noData ? 'No data' : 'No data yet',
            stateColor: c.text3,
            ticks: 20,
            filled: 0,
            fillColor: c.trackOff,
            caption: noData ? '' : 'Wear band tonight',
            numColor: c.text3,
            dim: dim,
            onTap: noData ? null : () => push(context, const SleepScreen()),
          )
        : ScoreMeter(
            label: 'Sleep',
            value: sp,
            decimals: 0,
            unit: '%',
            state: hmShort(t.slept!),
            stateColor: s.sleepChannel,
            ticks: 20,
            filled: (sp / 5).round(),
            fillColor: s.sleepChannel,
            caption:
                'Need ${hmShort(t.need!)}${t.calibrating ? ' (est.)' : ''}',
            numColor: numColor,
            dim: dim,
            onTap: () => push(context, const SleepScreen()),
          );
    return [rec, strain, sleep];
  }
}

class _SyncProgress extends StatelessWidget {
  const _SyncProgress({required this.sync});
  final SyncStatus sync;
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
                sync.connecting || sync.total == 0
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
  });
  final sc.Session session;
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
    final sport = session.sport == null
        ? ''
        : '${session.sport!.name[0].toUpperCase()}${session.sport!.name.substring(1)} · ';
    return TempoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Overline(overline)),
              TempoBadge(general ? 'General' : 'Personal'),
            ],
          ),
          const SizedBox(height: 14),
          Text(session.title, style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            why != null
                ? '$sport${session.minutes} min · ${session.zones} · +${session.strainLo > 0 ? (adds - 1).clamp(1, 21).round() : 1} to +${(adds + 1).round()} strain'
                : '$sport${session.minutes} min · ${session.zones} · adds ~${adds.round()} strain',
            style: TempoType.bodyS.c(c.text2).tnum,
          ),
          const SizedBox(height: 14),
          IntervalBars(segments: segs),
          if (why == null) ...[
            const SizedBox(height: 6),
            Text(session.structure, style: TempoType.caption.c(c.text3).tnum),
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
        ],
      ),
    );
  }
}

class RestCard extends StatelessWidget {
  const RestCard({super.key, required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    Widget row(String a, String b) => Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(a, style: TempoType.label.c(c.text1))),
          Text(b, style: TempoType.bodyS.c(c.text2).tnum),
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
            'Recovery is low or your cardio load is overreaching. Light movement only — strain under 8.',
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

class FirstWeekCard extends StatelessWidget {
  const FirstWeekCard({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget item(String t, bool done) => SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done ? c.text1 : null,
              shape: BoxShape.circle,
              border: done ? null : Border.all(color: c.lineStrong, width: 1.5),
            ),
            alignment: Alignment.center,
            child: done
                ? TempoIcon(
                    TempoIcons.check,
                    size: 12,
                    color: c.textInverse,
                    stroke: 3,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Text(t, style: TempoType.body.c(c.text1)),
        ],
      ),
    );
    return TempoCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            height: 56,
            child: CustomPaint(painter: _FirstWeekPainter(c.text3, c.text1)),
          ),
          const SizedBox(height: 16),
          Text('Your first week', style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            'Tempo learns your normal over 14 nights. Until then, guidance is marked “general”.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 16),
          item('Pair your band', true),
          item('Wear it to bed tonight', false),
          item('Morning check-in tomorrow', false),
        ],
      ),
    );
  }
}

class _FirstWeekPainter extends CustomPainter {
  _FirstWeekPainter(this.muted, this.strong);
  final Color muted, strong;
  @override
  void paint(Canvas canvas, Size size) {
    Paint p(Color c) => Paint()
      ..color = c
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(6, 52), const Offset(6, 8), p(muted));
    for (final x in const <double>[20, 34, 48]) {
      canvas.drawLine(Offset(x, 52), Offset(x, 38), p(muted));
    }
    canvas.drawLine(const Offset(62, 52), const Offset(62, 8), p(strong));
    for (final x in const <double>[76, 90, 104]) {
      for (var y = 52.0; y > 38; y -= 7) {
        canvas.drawLine(Offset(x, y), Offset(x, y - 2), p(muted));
      }
    }
  }

  @override
  bool shouldRepaint(_FirstWeekPainter o) => o.muted != muted;
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
                    Text(
                      x.name.replaceAll(', overnight', ''),
                      style: TempoType.bodyS.c(c.text1),
                    ),
                    if (x.proxy) ...[
                      const SizedBox(width: 6),
                      const TempoBadge('≈ proxy', small: true),
                    ],
                    const Spacer(),
                    Text(
                      '${x.glyph} ${x.verdict.split(' · ').last}',
                      style: TempoType.bodyS.c(x.color),
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
