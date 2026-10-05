import 'dart:convert';

import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/alarm.dart';
import '../core/band_link.dart' show deviceIdKey;
import '../core/format.dart';
import '../core/home_widgets.dart';
import '../core/profile.dart';
import '../core/stages.dart';
import '../core/today.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'learn.dart';
import 'nav.dart';
import 'night_detail.dart';
import 'settings.dart' show bandAction;

/// Last night for the morning of [day], decoded to stages.
class Night {
  Night({
    required this.morning,
    required this.minutes,
    required this.latency,
    required this.spo2,
    required this.typical,
    required this.bedtimes,
    required this.hrBand,
    this.staged = true,
  });
  final DateTime morning;

  /// False when the band sampled HR too rarely to estimate stages.
  final bool staged;
  final List<sc.Minute> minutes;
  final int latency;
  final List<st.Spo2Sample> spo2;

  /// Typical share (0..1) of awake/rem/light/deep over the last 30 nights.
  final Map<sc.Stage, double> typical;

  /// Bedtimes (minute of day) of recent nights, for consistency.
  final List<int> bedtimes;

  /// Overnight HR normal band (p10, p90) of recent resting HR.
  final (double, double)? hrBand;

  bool get empty => minutes.isEmpty;
  sc.SleepSession get session => sc.SleepSession(minutes);
  DateTime get start => minutes.first.ts;
  DateTime get end => minutes.last.ts.add(const Duration(minutes: 1));
  Duration stage(sc.Stage s) => session.stage(s);
  Duration get awake =>
      Duration(minutes: minutes.where((m) => !m.stage.asleep).length);
  List<sc.WakeUp> get wakeUps => sc.wakeUps(minutes);
}

final nightProvider = FutureProvider.family<Night, DateTime>((
  ref,
  morning,
) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final s = await db.scoreFor(morning);
  if (s?.sleepStart == null) {
    return Night(
      morning: morning,
      minutes: const [],
      latency: 0,
      spo2: const [],
      typical: const {},
      bedtimes: const [],
      hrBand: null,
    );
  }
  final a = st.fromTs(s!.sleepStart!), b = st.fromTs(s.sleepEnd!);
  // Decode the hour before and the night together so the night is staged
  // exactly as scoring staged it.
  final decoded = decodeMinutes(
    await db.minutesBetween(a.subtract(const Duration(minutes: 60)), b),
  );
  final mins = [
    for (final m in decoded.minutes)
      if (!m.ts.isBefore(a)) m,
  ];
  final before = [
    for (final m in decoded.minutes)
      if (m.ts.isBefore(a)) m,
  ];
  final past = await db.scoresBefore(
    morning.add(const Duration(days: 1)),
    limit: 30,
  );
  final typical = <sc.Stage, double>{};
  var n = 0;
  final sessions = await db.watchSleepSessions().first;
  final recentEnds = {
    for (final p in past)
      if (p.sleepEnd != null) p.sleepEnd!,
  };
  for (final ss in sessions.where((x) => recentEnds.contains(x.end))) {
    final j = (jsonDecode(ss.stages) as Map).cast<String, num>();
    final total = j.values.fold<num>(0, (x, y) => x + y);
    if (total == 0) continue;
    n++;
    for (final stg in [
      sc.Stage.wake,
      sc.Stage.rem,
      sc.Stage.light,
      sc.Stage.deep,
    ]) {
      typical[stg] = (typical[stg] ?? 0) + (j[stg.name] ?? 0) / total;
    }
  }
  if (n > 0) typical.updateAll((k, v) => v / n);
  final rhrs = past.map((p) => p.rhr);
  final lo = sc.quantile(rhrs, .1), hi = sc.quantile(rhrs, .9);
  return Night(
    morning: morning,
    minutes: mins,
    latency: sc.sleepLatency(before),
    spo2: await db.spo2Between(a, b),
    typical: typical,
    bedtimes: [
      for (final p in past.take(7))
        if (p.sleepStart != null)
          st.fromTs(p.sleepStart!).hour * 60 + st.fromTs(p.sleepStart!).minute,
    ],
    hrBand: lo == null || hi == null ? null : (lo, hi + 4),
    staged: !decoded.unstaged,
  );
});

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    final night = t == null ? null : ref.watch(nightProvider(t.day)).value;
    if (t == null || night == null) {
      return Scaffold(backgroundColor: context.c.bg);
    }
    final c = context.c, s = context.s;
    final perf = t.sleepPerf;
    final strainYesterday = t.history.isEmpty ? 0.0 : t.history.first.strain;
    final strainPart = t.strain * const sc.SleepParams().strainFactor;
    final debtPart = t.debt * const sc.SleepParams().debtFactor;
    return TempoPage(
      gap: 22,
      children: [
        DetailHeader(
          title: 'Sleep',
          subtitle: nightLabel(t.day),
          trailing: InfoButton(
            label: 'How sleep need works',
            onTap: () => push(context, const LearnCardsScreen(initial: 4)),
          ),
        ),
        if (night.empty)
          const TempoEmpty('No sleep yet — wear your band tonight.')
        else ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${perf?.round() ?? '—'}',
                      style: TempoType.hero.c(c.text1),
                    ),
                    TextSpan(
                      text: '% of need',
                      style: TempoType.titleM.c(c.text3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TargetStrip(
                value: (perf ?? 0),
                max: 100,
                color: s.sleepChannel,
                height: 10,
                track: 10,
                marker: false,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: hmShort(t.slept ?? 0),
                          style: TextStyle(color: c.text1),
                        ),
                        const TextSpan(text: ' asleep'),
                      ],
                    ),
                    style: TempoType.bodyS.c(c.text2).tnum,
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'needed '),
                        TextSpan(
                          text: hmShort(t.need ?? 0),
                          style: TextStyle(
                            color: c.text1,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                            decorationColor: c.text3,
                          ),
                        ),
                      ],
                    ),
                    style: TempoType.bodyS.c(c.text2).tnum,
                  ),
                ],
              ),
              if (t.napHours > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '+ ${hmShort(t.napHours)} nap today · counts against your sleep debt',
                  style: TempoType.caption.c(c.text2).tnum,
                ),
              ],
            ],
          ),
          TempoCard(
            onTap: () => push(context, NightDetailScreen(morning: t.day)),
            label: 'Night detail',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      clockOf(night.start),
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                    Text(
                      'In bed ${hmShort(night.session.inBed.inMinutes / 60)}',
                      style: TempoType.caption.c(c.text3).tnum,
                    ),
                    Text(
                      clockOf(night.end),
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!night.staged) ...[
                  Text(
                    'No stages for this night: the band measured heart rate only every 10–30 minutes. Tempo now asks it for every minute, so the next night will have them.',
                    style: TempoType.caption.c(c.text2),
                  ),
                  const SizedBox(height: 8),
                ],
                Hypnogram(minutes: night.minutes, height: 160),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (i, (name, stg, col)) in [
                      ('Awake', sc.Stage.wake, s.sleepAwake),
                      ('REM', sc.Stage.rem, s.sleepRem),
                      ('Light', sc.Stage.light, s.sleepLight),
                      ('Deep', sc.Stage.deep, s.sleepDeep),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: col,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(name, style: TempoType.caption.c(c.text3)),
                            Text(
                              hmShort(
                                (stg == sc.Stage.wake
                                            ? night.awake
                                            : night.stage(stg))
                                        .inMinutes /
                                    60,
                              ),
                              style: TempoType.label.c(c.text1).tnum,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StatTile(
                      'Sleep debt',
                      hmShort(t.debt),
                      '7-day · naps count',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      'Efficiency',
                      '${(night.session.efficiency * 100).round()}%',
                      'Asleep vs in bed',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StatTile(
                      'Consistency',
                      night.bedtimes.length < 3
                          ? '—'
                          : '${(sc.consistency(night.bedtimes) * 100).round()}%',
                      'Bedtimes within ±25 min',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      'Fell asleep',
                      '${night.latency} min',
                      '${night.wakeUps.length} wake-ups, ${night.awake.inMinutes} min awake',
                      estimate: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        TempoCard(
          color: s.tintSleep,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Overline('Tonight', color: s.sleepChannel),
                  const Spacer(),
                  Text(
                    'Wake ${clockShort(DateTime(2000, 1, 1, t.wakeMinute ~/ 60, t.wakeMinute % 60))}${t.wakeFromUsual ? ' · from your usual' : ''}',
                    style: TempoType.caption.c(c.text2),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    clockShort(
                      DateTime(
                        2000,
                        1,
                        1,
                        t.bedtimeMinute ~/ 60,
                        t.bedtimeMinute % 60,
                      ),
                    ),
                    style: TempoType.scoreL.copyWith(
                      fontSize: 48,
                      height: 50 / 48,
                      color: c.text1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${t.bedtimeMinute < 720 ? 'am' : 'pm'} bedtime',
                    style: TempoType.titleM.c(c.text2),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SegmentBar(
                height: 8,
                parts: [
                  (t.baseNeed, s.sleepChannel),
                  (strainPart, s.strain[1]),
                  (debtPart, c.text2),
                ],
              ),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${hmShort(t.baseNeed)} ${t.baseNeedLearned ? 'your base' : 'starting base'} + ${hmShort(strainPart)} for today’s strain + ${hmShort(debtPart)} toward debt = ',
                    ),
                    TextSpan(
                      text: hmShort(t.needTonight),
                      style: TextStyle(color: c.text1),
                    ),
                    const TextSpan(text: '. Allow ~10 min to fall asleep.'),
                  ],
                ),
                style: TempoType.bodyS.c(c.text2).tnum,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TempoButton(
                      'Remind me at ${clock12((t.bedtimeMinute - 30) % 1440)}',
                      small: true,
                      expand: true,
                      onTap: () async {
                        final db = ref.read(dbProvider);
                        await db.putSetting(Keys.bedtimeNudge, '30');
                        await rescheduleNotifications(db, t);
                        if (context.mounted) {
                          showTempoToast(
                            context,
                            'Reminder set for ${clock12((t.bedtimeMinute - 30) % 1440)}',
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  TempoButton(
                    'Change wake',
                    small: true,
                    kind: ButtonKind.ghost,
                    onTap: () => pickWakeTime(context, ref, t.wakeMinute),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Hair(),
              Pressable(
                label: 'Smart alarm',
                onTap: () => pickSmartAlarm(context, ref, t),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Smart alarm',
                          style: TempoType.body.c(c.text1),
                        ),
                      ),
                      Text(
                        t.smartAlarm == null
                            ? 'Off'
                            : 'By ${clock12(t.smartAlarm!)} · light sleep',
                        style: TempoType.bodyS.c(c.text2).tnum,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          'The band marks when you sleep; Tempo estimates the stages from your heart rate and movement, so treat them as a guide. Need starts at 7 h 30 m; after 14 scored nights it learns from the nights you recover best after, then adjusts to strain and debt.${strainYesterday > 0 ? '' : ''}',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

Future<void> pickWakeTime(
  BuildContext context,
  WidgetRef ref,
  int current,
) async {
  var picked = current;
  final ok = await showTempoSheet<bool>(
    context,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Wake time', style: TempoType.titleM.c(ctx.c.text1)),
        const SizedBox(height: 4),
        Text(
          'Tonight’s bedtime is planned back from this.',
          style: TempoType.bodyS.c(ctx.c.text2),
        ),
        SizedBox(
          height: 180,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: ctx.c.dark ? Brightness.dark : Brightness.light,
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle: TempoType.titleL.c(ctx.c.text1),
              ),
            ),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              minuteInterval: 5,
              initialDateTime: DateTime(
                2000,
                1,
                1,
                current ~/ 60,
                (current % 60) ~/ 5 * 5,
              ),
              onDateTimeChanged: (d) => picked = d.hour * 60 + d.minute,
            ),
          ),
        ),
        TempoButton(
          'Save',
          expand: true,
          onTap: () => Navigator.pop(ctx, true),
        ),
        TempoButton(
          'Use my usual',
          kind: ButtonKind.text,
          expand: true,
          onTap: () => Navigator.pop(ctx, false),
        ),
      ],
    ),
  );
  if (ok == null) return;
  final db = ref.read(dbProvider);
  if (ok) {
    await db.putSetting(Keys.wakeTime, fmtHm(picked));
  } else {
    await db.deleteSetting(Keys.wakeTime);
  }
  await rescheduleNotifications(db, await loadToday(db));
}

/// Band smart alarm: buzzes in light sleep up to 30 min before the time.
Future<void> pickSmartAlarm(
  BuildContext context,
  WidgetRef ref,
  TodayData t,
) async {
  final paired =
      (await ref.read(dbProvider).setting(deviceIdKey) ?? '').isNotEmpty;
  if (!context.mounted) return;
  if (!paired) {
    showTempoToast(context, 'Pair your band to set a smart alarm');
    return;
  }
  const off = -1;
  final base = (t.wakeMinute ~/ 15) * 15;
  final picked = await pickOption<int>(
    context,
    title: 'Smart alarm',
    options: [off, for (var m = base - 60; m <= base + 60; m += 15) m % 1440],
    label: (m) => m == off
        ? 'Off'
        : '${clock12(m)}${m == t.wakeMinute ? ' · your wake time' : ''}',
    selected: t.smartAlarm ?? off,
  );
  if (!context.mounted || picked == null || picked == (t.smartAlarm ?? off)) {
    return;
  }
  await bandAction(
    context,
    () => writeSmartAlarm(ref.read(dbProvider), picked == off ? null : picked),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.k, this.v, this.sub, {this.estimate = false});
  final String k, v, sub;
  final bool estimate;
  @override
  Widget build(BuildContext context) => TempoCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Overline(k),
        const SizedBox(height: 4),
        Text(
          v,
          style: TempoType.scoreS.copyWith(
            color: context.c.text1,
            decoration: estimate ? TextDecoration.underline : null,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: context.c.text3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TempoType.caption.c(context.c.text2),
        ),
      ],
    ),
  );
}

/// TempoHypnogram: row = stage, colour confirms; deeper = lower.
class Hypnogram extends StatelessWidget {
  const Hypnogram({
    super.key,
    required this.minutes,
    this.height = 152,
    this.labels = true,
  });
  final List<sc.Minute> minutes;
  final double height;
  final bool labels;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chart = SvgChart(
      height: 160,
      stretchHeight: height,
      semantics: 'Sleep stages through the night',
      draw: (ink, box) {
        if (minutes.isEmpty) return;
        int row(sc.Stage s) => switch (s) {
          sc.Stage.rem => 1,
          sc.Stage.light => 2,
          sc.Stage.deep => 3,
          _ => 0,
        };
        Color col(sc.Stage s) => switch (s) {
          sc.Stage.rem => ink.s.sleepRem,
          sc.Stage.light => ink.s.sleepLight,
          sc.Stage.deep => ink.s.sleepDeep,
          _ => ink.s.sleepAwake,
        };
        final segs = <(sc.Stage, int, int)>[];
        for (var i = 0; i < minutes.length; i++) {
          final st = row(minutes[i].stage);
          if (segs.isNotEmpty && row(segs.last.$1) == st) {
            segs[segs.length - 1] = (segs.last.$1, segs.last.$2, i + 1);
          } else {
            segs.add((minutes[i].stage, i, i + 1));
          }
        }
        final k = 520 / minutes.length;
        final step = <Offset>[];
        for (final (s, a, b) in segs) {
          final y = 19.0 + row(s) * 40;
          step.addAll([Offset(a * k, y), Offset(b * k, y)]);
        }
        ink.polyline(step, ink.c.lineStrong, w: 1.5);
        for (final (s, a, b) in segs) {
          ink.rect(
            Rect.fromLTWH(
              a * k,
              6 + row(s) * 40.0,
              (b - a) * k < 2 ? 2 : (b - a) * k,
              26,
            ),
            col(s),
            radius: 3,
          );
        }
      },
    );
    if (!labels) return chart;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in ['Awake', 'REM', 'Light', 'Deep'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(l, style: TempoType.caption.c(c.text2)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: chart),
      ],
    );
  }
}
