import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/stages.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'activity_detail.dart';
import 'nav.dart';

class _Day {
  _Day(this.minutes, this.stress, this.workouts, this.plan);
  final List<st.MinuteSample> minutes;
  final List<st.StressSample> stress;
  final List<st.Workout> workouts;
  final sc.Session? plan;
}

final _dayProvider = FutureProvider.family<_Day, DateTime>((ref, day) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final end = day.add(const Duration(days: 1));
  final p = await db.planDay(day);
  return _Day(
    await db.minutesBetween(day, end),
    await db.stressBetween(day, end),
    await db.workoutsBetween(day, end),
    p == null
        ? null
        : sc.Session.fromJson(jsonDecode(p.session) as Map<String, dynamic>),
  );
});

/// 24 hours top to bottom: sleep stages, activities, HR, stress, steps.
class DayTimelineScreen extends ConsumerStatefulWidget {
  const DayTimelineScreen({super.key, this.day});
  final DateTime? day;
  @override
  ConsumerState<DayTimelineScreen> createState() => _DayTimelineState();
}

class _DayTimelineState extends ConsumerState<DayTimelineScreen> {
  late DateTime _day = dayOf(widget.day ?? DateTime.now());
  static const k = 56 / 60; // px per minute

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final d = ref.watch(_dayProvider(_day)).value;
    final today = dayOf(DateTime.now());
    final isToday = _day == today;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    double y(int m) => m * k;
    int mod(int ts) {
      final t = st.fromTs(ts);
      return t.hour * 60 + t.minute;
    }

    return TempoPage(
      gap: 14,
      bottom: 40,
      children: [
        DetailHeader(
          title: '',
          center: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TempoIconButton(
                TempoIcons.back,
                label: 'Previous day',
                size: 18,
                color: c.text2,
                onTap: () => setState(
                  () => _day = _day.subtract(const Duration(days: 1)),
                ),
              ),
              Text(dayShort(_day), style: TempoType.label.c(c.text1)),
              TempoIconButton(
                TempoIcons.chevron,
                label: 'Next day',
                size: 18,
                color: c.text2,
                onTap: isToday
                    ? null
                    : () => setState(
                        () => _day = _day.add(const Duration(days: 1)),
                      ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 42),
              SizedBox(
                width: 38,
                child: Text('Sleep', style: TempoType.caption.c(c.text3)),
              ),
              Expanded(
                child: Text('Activity', style: TempoType.caption.c(c.text3)),
              ),
              SizedBox(
                width: 96,
                child: Text('Heart rate', style: TempoType.caption.c(c.text3)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 26,
                child: Text('Str.', style: TempoType.caption.c(c.text3)),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  'Steps',
                  textAlign: TextAlign.right,
                  style: TempoType.caption.c(c.text3),
                ),
              ),
            ],
          ),
        ),
        if (d == null)
          const SizedBox(height: 1344)
        else
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final actLeft = 80.0,
                  hrLeft = w - 96 - 8 - 26 - 46,
                  stressLeft = w - 46 - 26;
              final actW = hrLeft - actLeft - 8;
              // Stages per minute.
              final sleep = <Widget>[];
              for (final m in d.minutes) {
                final stg = stageForKind(m.kind);
                if (!stg.asleep && stg != sc.Stage.wake) continue;
                if (!stg.asleep) continue;
                final (wd, col) = switch (stg) {
                  sc.Stage.rem => (16.0, s.sleepRem),
                  sc.Stage.light => (22.0, s.sleepLight),
                  sc.Stage.deep => (30.0, s.sleepDeep),
                  _ => (8.0, s.sleepAwake),
                };
                sleep.add(
                  Positioned(
                    left: 42,
                    width: wd,
                    top: y(mod(m.ts)),
                    height: k + .5,
                    child: ColoredBox(color: col),
                  ),
                );
              }
              // HR path.
              final hrPts = <Offset?>[];
              int? prev;
              for (final m in d.minutes) {
                if (m.hr == null) continue;
                final mm = mod(m.ts);
                if (prev != null && mm - prev > 20) hrPts.add(null);
                hrPts.add(
                  Offset(((m.hr! - 40) / 120).clamp(0, 1) * 92 + 2, y(mm)),
                );
                prev = mm;
              }
              // Stress and steps per 30 min.
              final stressB = List<List<int>>.generate(48, (_) => []);
              for (final x in d.stress) {
                if (x.value > 0) stressB[mod(x.ts) ~/ 30].add(x.value);
              }
              final stepsB = List<int>.filled(48, 0);
              for (final m in d.minutes) {
                stepsB[mod(m.ts) ~/ 30] += m.steps;
              }
              final maxSteps = math.max(1, stepsB.reduce(math.max));
              return SizedBox(
                height: 1344,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var h = 0; h < 24; h++) ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        top: y(h * 60),
                        height: 1,
                        child: ColoredBox(color: c.line),
                      ),
                      Positioned(
                        left: 0,
                        top: y(h * 60) + 2,
                        child: Text(
                          h == 0
                              ? '12a'
                              : h < 12
                              ? '${h}a'
                              : h == 12
                              ? '12p'
                              : '${h - 12}p',
                          style: TempoType.caption.c(c.text3).tnum,
                        ),
                      ),
                    ],
                    ...sleep,
                    for (final wk in d.workouts)
                      Positioned(
                        left: actLeft,
                        width: actW,
                        top: y(mod(wk.start)),
                        height: math.max(30, (wk.end - wk.start) / 60 * k),
                        child: Pressable(
                          label: wk.title,
                          onTap: () =>
                              push(context, ActivityDetailScreen(id: wk.id)),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                left: BorderSide(
                                  color: s.zoneColor(_topZone(wk)),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${wk.title}\n',
                                    style: TextStyle(
                                      color: c.text1,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '+${n1(wk.strain)}',
                                    style: TextStyle(color: s.strain[1]),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.clip,
                              style: TempoType.caption.tnum,
                            ),
                          ),
                        ),
                      ),
                    if (isToday &&
                        d.plan != null &&
                        !d.plan!.isRest &&
                        d.workouts.every((wk) => wk.source != 'live'))
                      Positioned(
                        left: actLeft,
                        width: actW,
                        top: y(math.min(1380, nowMin + 20)),
                        height: 40,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.lineStrong),
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Planned\n',
                                  style: TextStyle(color: c.text2),
                                ),
                                TextSpan(
                                  text: d.plan!.title,
                                  style: TextStyle(color: c.text3),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TempoType.caption,
                          ),
                        ),
                      ),
                    Positioned(
                      left: hrLeft,
                      top: 0,
                      width: 96,
                      height: 1344,
                      child: CustomPaint(painter: _LinePainter(hrPts, c.text1)),
                    ),
                    for (var i = 0; i < 48; i++)
                      if (stressB[i].isNotEmpty)
                        Positioned(
                          left: stressLeft,
                          width: 22,
                          top: y(i * 30) + 1,
                          height: 27,
                          child: Opacity(
                            opacity:
                                (stressB[i].reduce((a, b) => a + b) /
                                        stressB[i].length /
                                        80)
                                    .clamp(.08, .9),
                            child: ColoredBox(color: c.text2),
                          ),
                        ),
                    for (var i = 0; i < 48; i++)
                      if (stepsB[i] > 0)
                        Positioned(
                          right: 0,
                          width: math.max(2, stepsB[i] / maxSteps * 44),
                          top: y(i * 30) + 3,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.text3,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    if (isToday) ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        top: y(nowMin) + 2,
                        bottom: 0,
                        child: ColoredBox(color: c.bg.withValues(alpha: .6)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: y(nowMin),
                        height: 2,
                        child: ColoredBox(color: c.text1),
                      ),
                      Positioned(
                        right: 0,
                        top: y(nowMin) - 26,
                        child: TempoBadge(
                          'Now ${clockOf(now)}',
                          background: c.bg,
                          color: c.text1,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        Text(
          'Stress lane: darker = higher index (≈ proxy). Steps per 30 min. Tap any block for detail.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  static int _topZone(st.Workout w) {
    final z = (jsonDecode(w.zones) as List).cast<num>();
    var top = 1;
    for (var i = 0; i < z.length; i++) {
      if (z[i] > 0 && z[i] >= z[top - 1]) top = i + 1;
    }
    return top;
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.color);
  final List<Offset?> pts;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (final o in pts) {
      if (o == null) {
        if (path != null) canvas.drawPath(path, p);
        path = null;
        continue;
      }
      path == null
          ? path = (Path()..moveTo(o.dx, o.dy))
          : path.lineTo(o.dx, o.dy);
    }
    if (path != null) canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}
