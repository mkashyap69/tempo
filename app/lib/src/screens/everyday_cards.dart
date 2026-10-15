import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart' show dayOf;
import '../core/everyday.dart';
import '../core/format.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// Cards for the everyday metrics (decisions.md, 2026-10-15). Each shows
/// one number, what it means for you, and stays a quiet "learning" line
/// until there is enough data to trust it.

final rhythmProvider = dbQuery((db, _) => loadRhythm(db));
final bodySignalsProvider = dbQuery((db, _) => loadBodySignals(db));
final movementProvider = dbQuery((db, _) => loadMovement(db));

String _hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? '$m min' : '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// A minute-of-day that may be negative or past 1440, as a clock.
String _mid(int m) => clock12(((m % 1440) + 1440) % 1440);

/// Sleep screen: how regular your sleep is, and how much weekends shift it.
class RhythmCard extends ConsumerWidget {
  const RhythmCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rhythmProvider).value;
    if (r == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final sri = r.sri;
    final (word, color) = switch (r.band) {
      sc.Regularity.regular => ('Regular', s.recHigh),
      sc.Regularity.fair => ('Fairly regular', s.recMid),
      sc.Regularity.irregular => ('Irregular', s.recLow),
      null => ('Learning', c.text3),
    };
    final j = r.jetlag;
    final jet = j == null
        ? null
        : switch (sc.jetlagBand(j.minutes)) {
            sc.JetlagBand.small =>
              'Weekends barely shift your sleep (${_hm(j.minutes.abs())}).',
            _ =>
              'Weekends shift your sleep ${_hm(j.minutes.abs())} ${j.minutes > 0 ? 'later' : 'earlier'} (mid-sleep ${_mid(j.workMid)} → ${_mid(j.freeMid)}). ${sc.jetlagBand(j.minutes) == sc.JetlagBand.large ? 'Like flying a time zone every weekend; a closer wake time on Saturday narrows it.' : 'Keeping wake time within an hour narrows it.'}',
          };
    return TempoCard(
      label: 'Sleep rhythm',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Rhythm', style: TempoType.label.c(c.text1)),
              ),
              Text(word, style: TempoType.label.c(color)),
            ],
          ),
          const SizedBox(height: 10),
          if (sri == null)
            Text(
              'Regularity needs a week with your band or watch worn day and night · ${r.days} of $rhythmDays days so far.',
              style: TempoType.bodyS.c(c.text2),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${sri.round().clamp(0, 100)}',
                  style: TempoType.titleL.c(c.text1).tnum,
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/100 regularity',
                    style: TempoType.caption.c(c.text3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(switch (r.band!) {
              sc.Regularity.regular => 'You sleep and wake at much the same times each day. People this regular live longer on average, more than sleep length alone predicts.',
              sc.Regularity.fair => 'Mostly steady, with some days off pattern. The same wake time every day, weekends too, is the quickest way up.',
              sc.Regularity.irregular => 'Your sleep times vary a lot from day to day. Pick one wake time and keep it for a week; bedtime follows.',
            }, style: TempoType.bodyS.c(c.text2)),
          ],
          if (jet != null) ...[
            const SizedBox(height: 10),
            const Hair(),
            const SizedBox(height: 10),
            Text(jet, style: TempoType.bodyS.c(c.text2)),
          ],
        ],
      ),
    );
  }
}

/// Recovery screen: each overnight signal against your own normal.
class BodySignalsSection extends ConsumerWidget {
  const BodySignalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bodySignalsProvider).value;
    if (b == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final summary = switch (b.level) {
      sc.BodyLevel.learning =>
        'Tempo needs $signalNights nights to know your normal for each signal.',
      sc.BodyLevel.normal =>
        'Everything Tempo measures overnight was in your normal range.',
      sc.BodyLevel.watch => 'One signal is outside your normal. Alone it’s often a late meal, a drink or a hot room.',
      sc.BodyLevel.rest => 'Several signals moved the wrong way together. That often comes a day or two before feeling ill: go easy and sleep early.',
    };
    return Section(
      title: 'Body signals · last night',
      child: CardList(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(summary, style: TempoType.bodyS.c(c.text2)),
          ),
          for (final r in b.readings)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      signalName(r.key),
                      style: TempoType.body.c(c.text1),
                    ),
                  ),
                  Text(
                    switch (r.state) {
                      sc.SignalState.learning => 'Learning',
                      sc.SignalState.missing => 'No reading',
                      _ =>
                        '${signalValue(r.key, r.value!)} · usual ${signalValue(r.key, r.mean!)}',
                    },
                    style: TempoType.bodyS
                        .c(
                          r.state == sc.SignalState.off
                              ? s.recLow
                              : r.state == sc.SignalState.normal
                              ? c.text2
                              : c.text3,
                        )
                        .tnum,
                  ),
                  if (r.state == sc.SignalState.off) ...[
                    const SizedBox(width: 6),
                    Text('▲', style: TempoType.caption.c(s.recLow)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Nights each signal needs before it's judged.
const signalNights = sc.signalMinNights;

/// Today: shown only when two or more signals are off, so a normal
/// morning stays quiet.
class BodySignalsAlert extends ConsumerWidget {
  const BodySignalsAlert({super.key, this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bodySignalsProvider).value;
    if (b == null || b.level != sc.BodyLevel.rest) {
      return const SizedBox.shrink();
    }
    final names = b.off.map((r) => signalName(r.key).toLowerCase()).join(', ');
    return StatusBanner(
      icon: TempoIcons.alert,
      title: 'Body signals are off',
      body:
          'Last night your $names moved the wrong way together. Take it easy today and get to bed early.',
      action: onOpen == null ? null : 'See signals',
      onAction: onOpen,
    );
  }
}

/// Strain screen: brisk minutes and the longest still stretch today.
class MovementCard extends ConsumerWidget {
  const MovementCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(movementProvider).value;
    if (m == null) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final still = m.still;
    return TempoCard(
      label: 'Movement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Movement today', style: TempoType.label.c(c.text1)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stat(
                  'Brisk minutes',
                  '${m.brisk}',
                  unit: '/ ${sc.briskTarget}',
                  color: m.brisk >= sc.briskTarget ? s.recHigh : null,
                  sub: m.briskAvg == null
                      ? '100+ steps a minute'
                      : 'usual ${m.briskAvg!.round()} a day',
                ),
              ),
              Expanded(
                child: Stat(
                  'Longest still',
                  still == null ? '—' : _hm(still.minutes),
                  color: still != null && still.minutes >= 120
                      ? s.recMid
                      : null,
                  sub: still == null
                      ? (m.watchOnly ? 'needs heart rate' : 'not enough yet')
                      : '${clockOf(still.start)}–${clockOf(still.end)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            m.brisk >= sc.briskTarget
                ? 'Brisk walking target met: that pace is what counts most for long-term health.'
                : still != null && still.minutes >= 90
                ? 'A few minutes of walking every hour breaks up long sitting, which matters even on active days.'
                : 'Brisk means 100+ steps a minute, a purposeful walk. ${sc.briskTarget} minutes a day is the aim.',
            style: TempoType.bodyS.c(c.text2),
          ),
        ],
      ),
    );
  }
}

final _recoveryProvider = FutureProvider.family<(int?, double?), int>((
  ref,
  id,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final w = await db.workout(id);
  if (w == null) return (null, null);
  final s = await db.scoreFor(dayOf(st.fromTs(w.start)));
  final hrMax = s?.hrMax ?? 190;
  return (
    await workoutRecovery(db, w, hrMax),
    await usualRecovery(db, hrMax, before: st.fromTs(w.start)),
  );
});

/// Activity detail: how fast heart rate fell after the workout.
class RecoveryHrCard extends ConsumerWidget {
  const RecoveryHrCard({super.key, required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(_recoveryProvider(workoutId)).value;
    final drop = v?.$1;
    if (drop == null) return const SizedBox.shrink();
    final usual = v!.$2;
    final c = context.c, s = context.s;
    final good = drop > sc.recoveryTypicalDrop;
    return TempoCard(
      label: 'Heart-rate recovery',
      child: Row(
        children: [
          Expanded(
            child: Stat(
              'Recovery, 2 min',
              '−$drop',
              unit: 'bpm',
              color: good ? s.recHigh : s.recMid,
              sub: usual == null
                  ? (good ? 'a typical drop' : 'slower than typical')
                  : 'usual −${usual.round()}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              'How far heart rate fell in the 2 minutes after you stopped. It grows as fitness does; a slower drop than usual can mean you’re tired. Stand or walk easy at the end for a fair reading.',
              style: TempoType.caption.c(c.text2),
            ),
          ),
        ],
      ),
    );
  }
}
