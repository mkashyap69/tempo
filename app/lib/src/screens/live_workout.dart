import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/live_session.dart';
import 'activity_detail.dart' show effectProvider, EffectQuery;
import 'nav.dart' show push;
import 'strength_log.dart';

/// Reads at arm's length: 132 px HR, 72 px controls.
class LiveWorkoutScreen extends ConsumerWidget {
  const LiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveSessionProvider);
    final c = context.c;
    if (s == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return Scaffold(backgroundColor: c.bg);
    }
    if (s.phase == LivePhase.ended) return _Summary(s: s);
    return Scaffold(
      backgroundColor: c.bg,
      body: _Live(s: s),
    );
  }
}

class _Live extends ConsumerWidget {
  const _Live({required this.s});
  final LiveState s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c, sc0 = context.s;
    final n = ref.read(liveSessionProvider.notifier);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final z = s.zone;
    final zc = z == 0 ? c.trackOff : sc0.zoneColor(z);
    final paused = s.phase == LivePhase.paused;
    final connecting = s.phase == LivePhase.connecting;
    final failed = s.phase == LivePhase.failed;
    final (seg, left) = s.segment;
    final plan = s.plan;
    String pill;
    var inTarget = false;
    if (connecting) {
      pill = 'Connecting to band…';
    } else if (s.timerOnly) {
      pill = 'Timing · HR from Health later';
    } else if (s.signalLost) {
      pill = 'Signal lost — timer keeps running';
    } else if (z == 0) {
      pill = 'Below Z1 · warming up';
    } else if (s.guided && seg < plan!.segments.length) {
      final want = plan.segments[seg].zone;
      final r = sc.zoneRange(want, s.hrMax);
      inTarget = z == want;
      pill = z == want
          ? 'In target · Z$want ${r.lo}–${r.hi}'
          : z < want
          ? 'Push a little · Z$want ${r.lo}–${r.hi}'
          : 'Ease off · Z$want ${r.lo}–${r.hi}';
    } else {
      // Open session: no target to be in, so say where the next zone starts.
      final r = sc.zoneRange(z, s.hrMax);
      pill = z == 5
          ? 'Z5 · ${r.lo}+ bpm'
          : 'Z$z ${r.lo}–${r.hi} · Z${z + 1} at ${r.hi + 1}';
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(10, top + 12, 10, 0),
          height: top + 56,
          child: Row(
            children: [
              TempoIconButton(
                TempoIcons.down,
                label: 'Minimise',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TempoType.label.c(c.text1),
                    ),
                    Text(
                      '${mmss(s.elapsed)} elapsed',
                      style: TempoType.caption.c(c.text3).tnum,
                    ),
                  ],
                ),
              ),
              _BandStatus(s: s),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: TempoMotion.base,
                opacity: paused ? .35 : 1,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    if (failed)
                      StatusBanner(
                        icon: TempoIcons.alert,
                        title: 'Couldn’t reach the band',
                        body: 'Keep it close and make sure no other app is connected.',
                        action: 'Retry',
                        onAction: () => n.start(plan: s.plan, sport: s.sport),
                      )
                    else
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: c.surface1,
                          borderRadius: BorderRadius.circular(TempoRadii.xl),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                20,
                                16,
                                20,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (z > 0)
                                        Container(
                                          constraints: const BoxConstraints(
                                            minWidth: 48,
                                          ),
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: zc,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Z$z',
                                            style: TextStyle(
                                              fontFamily: TempoType.family,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: sc0.onZone(z),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 10),
                                      Text(
                                        z == 0
                                            ? (connecting ? 'Starting' : 'Easy')
                                            : sc.zoneNames[z - 1],
                                        style: TempoType.titleM.c(c.text1),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        s.bpm?.toString() ?? '—',
                                        textScaler: TextScaler.noScaling,
                                        style: TextStyle(
                                          fontFamily: TempoType.family,
                                          fontSize: 132,
                                          height: 128 / 132,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: -6.6,
                                          color: c.text1,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'bpm',
                                        style: TempoType.titleM.c(c.text3),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.surface2,
                                      borderRadius: BorderRadius.circular(
                                        TempoRadii.pill,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (inTarget) ...[
                                          TempoIcon(
                                            TempoIcons.check,
                                            size: 16,
                                            color: c.text1,
                                            stroke: 2.5,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          pill,
                                          style: TempoType.label
                                              .copyWith(
                                                fontSize: 15,
                                                color: c.text1,
                                              )
                                              .tnum,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (s.guided && seg < plan!.segments.length)
                      TempoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Expanded(
                                  child: Text(
                                    _segLabel(plan, seg),
                                    style: TempoType.titleM.c(c.text1),
                                  ),
                                ),
                                Text(
                                  mmss(Duration(seconds: left)),
                                  style: TempoType.scoreS.c(c.text1),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            IntervalBars(
                              segments: [
                                for (final g in plan.segments)
                                  (g.minutes, g.zone),
                              ],
                              height: 40,
                              base: 10,
                              step: 7,
                              doneMinutes: s.elapsed.inSeconds / 60,
                              playhead:
                                  s.elapsed.inSeconds / (plan.minutes * 60),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _next(plan, seg),
                              style: TempoType.bodyS.c(c.text2),
                            ),
                          ],
                        ),
                      )
                    else if (!s.timerOnly)
                      _ZoneSplit(s: s),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            label: 'Session strain',
                            value: '+${n1(s.sessionStrain)}',
                            color: sc0.strain[1],
                            fill: s.sessionStrain,
                            max: plan == null
                                ? 10
                                : (plan.strainHi - s.dayStrainBefore).clamp(
                                        4,
                                        21,
                                      ) *
                                      1.4,
                            lo: plan == null
                                ? null
                                : (plan.strainLo - s.dayStrainBefore).clamp(
                                    0,
                                    21,
                                  ),
                            hi: plan == null
                                ? null
                                : (plan.strainHi - s.dayStrainBefore).clamp(
                                    1,
                                    21,
                                  ),
                            caption: plan == null
                                ? _rateNote(s)
                                : 'target +${(plan.strainLo - s.dayStrainBefore).clamp(0, 21).round()} to +${(plan.strainHi - s.dayStrainBefore).clamp(1, 21).round()}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Tile(
                            label: 'Day strain',
                            value: n1(s.dayStrain),
                            fill: s.dayStrain,
                            max: 21,
                            lo: s.target?.cap == true ? null : s.target?.lo,
                            hi: s.target?.hi,
                            caption: s.target == null
                                ? ''
                                : s.target!.cap
                                ? 'cap ${s.target!.hi.round()}'
                                : 'target ${s.target!.lo.round()}–${s.target!.hi.round()}',
                            note: _dayNote(s),
                            shaded: true,
                          ),
                        ),
                      ],
                    ),
                    if (!s.timerOnly && !failed && !connecting) ...[
                      const SizedBox(height: 16),
                      _HeartCard(s: s),
                    ],
                  ],
                ),
              ),
              if (paused)
                Positioned(
                  left: 20,
                  right: 20,
                  top: 280,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.surface3,
                      borderRadius: BorderRadius.circular(TempoRadii.lg),
                      boxShadow: c.shadowFloat,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Paused · ${mmss(s.elapsed)}',
                          style: TempoType.titleM.c(c.text1).tnum,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Strain and the interval clock are on hold.',
                          style: TempoType.bodyS.c(c.text2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (s.sport == sc.Sport.strength && !failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TempoButton(
              'Log sets',
              kind: ButtonKind.secondary,
              expand: true,
              onTap: () => push(context, StrengthLogScreen(plan: s.plan)),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
          child: Row(
            children: [
              Expanded(
                child: TempoButton(
                  paused ? 'Resume' : 'Pause',
                  kind: ButtonKind.secondary,
                  height: 72,
                  radius: 24,
                  fontSize: 18,
                  expand: true,
                  onTap: connecting || failed
                      ? null
                      : (paused ? n.resume : n.pause),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: failed || connecting
                    ? TempoButton(
                        failed ? 'Close' : 'End',
                        height: 72,
                        radius: 24,
                        fontSize: 18,
                        expand: true,
                        onTap: () async {
                          await n.end();
                          n.close();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                      )
                    // Hold to end: one stray tap mid-run can't end it.
                    // Screen readers get the confirm sheet instead.
                    : _HoldToEnd(
                        onEnd: n.end,
                        onConfirm: () async {
                          final ok = await confirmSheet(
                            context,
                            title: 'End workout?',
                            body: 'Tempo saves the session and asks how hard it felt.',
                            action: 'End and save',
                          );
                          if (ok) await n.end();
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _segLabel(sc.Session p, int i) {
    final seg = p.segments[i];
    if (i == 0) return 'Warm-up';
    if (i == p.segments.length - 1) return 'Cool-down';
    final work = [
      for (var k = 1; k < p.segments.length - 1; k++)
        if (p.segments[k].zone >= 3) k,
    ];
    if (seg.zone >= 3 && work.length > 1) {
      return 'Rep ${work.indexOf(i) + 1} of ${work.length}';
    }
    return seg.zone >= 3 ? 'Main set' : 'Recover';
  }

  static String _next(sc.Session p, int i) {
    if (i + 1 >= p.segments.length) return 'Last block — finish easy.';
    final n = p.segments[i + 1];
    return 'Next · ${n.minutes}′ ${n.zone >= 3 ? 'hard' : 'easy'} in Z${n.zone}. Tempo will buzz the band 5 s before.';
  }

  /// Open session: what the last five minutes add.
  static String _rateNote(LiveState s) {
    final r = s.strainRate;
    if (r == null) return '';
    final five = r * 5;
    return five < .05 ? 'not adding strain now' : '+${n1(five)} per 5′ now';
  }

  /// Where the day is against its target, and how long at this pace.
  static String? _dayNote(LiveState s) {
    final t = s.target;
    if (t == null || s.timerOnly) return null;
    if (t.cap) {
      if (s.dayStrain >= t.hi) return 'Past today’s cap';
      final m = s.minutesTo(t.hi);
      return m == null ? null : '≈ $m′ to the cap';
    }
    if (s.dayStrain >= t.hi) return 'Above target';
    if (s.dayStrain >= t.lo) return 'In target';
    final m = s.minutesTo(t.lo);
    return m == null ? null : '≈ $m′ more at this pace';
  }
}

/// Band link state: icon plus a dot (green streaming, red lost).
class _BandStatus extends StatelessWidget {
  const _BandStatus({required this.s});
  final LiveState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c, sc0 = context.s;
    final connecting = s.phase == LivePhase.connecting;
    final dot = s.timerOnly
        ? null
        : connecting
        ? c.text3
        : s.signalLost
        ? sc0.recLow
        : sc0.recHigh;
    return Semantics(
      label: s.timerOnly
          ? 'Timer only'
          : s.signalLost || connecting
          ? 'Band not streaming'
          : 'Band connected',
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                TempoIcon(
                  s.timerOnly ? TempoIcons.clock : TempoIcons.band,
                  size: 18,
                  color: c.text2,
                ),
                if (dot != null)
                  Positioned(
                    right: -2,
                    top: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface2, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Time in zones as one bar sized by minutes, plus the gap with no signal.
class _ZoneSplit extends StatelessWidget {
  const _ZoneSplit({required this.s});
  final LiveState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c, sc0 = context.s;
    final zs = s.zoneSeconds;
    final gap = s.noSignalSeconds;
    final showGap = gap >= 60;
    int flex(double v) => math.max(1, (v * 10).round());
    final parts = [
      for (var i = 0; i < 5; i++)
        if (zs[i] >= 1) (sc0.zone[i], zs[i]),
      if (gap >= 1) (c.trackOff, gap),
    ];
    Widget col(String label, double sec, {bool on = false}) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: on
                ? TempoType.caption
                      .c(c.text1)
                      .copyWith(fontWeight: FontWeight.w600)
                : TempoType.caption.c(c.text3),
          ),
          Text(
            '${(sec / 60).floor()}′',
            style: TempoType.label.c(on ? c.text1 : c.text2).tnum,
          ),
        ],
      ),
    );
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: parts.isEmpty
                  ? ColoredBox(color: c.trackOff)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, (color, sec)) in parts.indexed) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: flex(sec),
                            child: ColoredBox(color: color),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                col('Z${i + 1}', zs[i], on: i == s.zone - 1),
              if (showGap) col('No HR', gap),
            ],
          ),
        ],
      ),
    );
  }
}

/// Heart rate over the last 15 minutes on the zone bands, then steps and
/// cadence on foot, or time above Z1 otherwise.
class _HeartCard extends StatelessWidget {
  const _HeartCard({required this.s});
  final LiveState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final window = math.min(s.elapsed.inSeconds, LiveState.traceWindow);
    final onFoot = s.sport == sc.Sport.walking || s.sport == sc.Sport.running;
    final up = s.zoneSeconds.skip(1).fold(0.0, (a, b) => a + b);
    String? bpm(int? v) => v == null ? null : ' bpm';
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.trace.length >= 2) ...[
            Overline(
              window >= LiveState.traceWindow
                  ? 'Heart rate · last 15′'
                  : 'Heart rate',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: CustomPaint(
                painter: _TracePainter(
                  trace: s.trace,
                  now: s.elapsed.inSeconds,
                  window: math.max(window, 60),
                  hrMax: s.hrMax,
                  zones: context.s.zone,
                  line: c.text1,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              if (onFoot) ...[
                Expanded(
                  child: Stat(
                    'Steps',
                    s.steps == null ? '—' : grouped(s.steps!),
                  ),
                ),
                Expanded(
                  child: Stat(
                    'Cadence',
                    s.cadence?.toString() ?? '—',
                    unit: s.cadence == null ? null : ' spm',
                  ),
                ),
              ] else
                Expanded(child: Stat('Z2 and up', '${(up / 60).floor()}′')),
              Expanded(
                child: Stat(
                  'Avg HR',
                  s.avgHr?.toString() ?? '—',
                  unit: bpm(s.avgHr),
                ),
              ),
              if (!onFoot)
                Expanded(
                  child: Stat(
                    'Max HR',
                    s.maxHr?.toString() ?? '—',
                    unit: bpm(s.maxHr),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.trace,
    required this.now,
    required this.window,
    required this.hrMax,
    required this.zones,
    required this.line,
  });
  final List<(int, int)> trace;
  final int now, window, hrMax;
  final List<Color> zones;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = trace.first.$2, hi = lo;
    for (final (_, b) in trace) {
      lo = math.min(lo, b);
      hi = math.max(hi, b);
    }
    var yLo = lo - 8.0, yHi = hi + 8.0;
    if (yHi - yLo < 30) {
      final mid = (yHi + yLo) / 2;
      yLo = mid - 15;
      yHi = mid + 15;
    }
    double y(num b) => size.height * (1 - (b - yLo) / (yHi - yLo));
    double x(int t) => size.width * (1 - (now - t) / window);

    // Zone bands behind the line.
    for (var z = 1; z <= 5; z++) {
      final r = sc.zoneRange(z, hrMax);
      final top = math.max(0.0, y(z == 5 ? yHi : r.hi + 1));
      final bottom = math.min(size.height, y(r.lo));
      if (bottom <= top) continue;
      canvas.drawRect(
        Rect.fromLTRB(0, top, size.width, bottom),
        Paint()..color = zones[z - 1].withValues(alpha: .16),
      );
    }

    // Break the line where readings stop for more than 5 s.
    final path = Path();
    int? prev;
    for (final (t, b) in trace) {
      if (t < now - window) continue;
      if (prev == null || t - prev > 5) {
        path.moveTo(x(t), y(b));
      } else {
        path.lineTo(x(t), y(b));
      }
      prev = t;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final (lt, lb) = trace.last;
    canvas.drawCircle(Offset(x(lt), y(lb)), 3.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_TracePainter o) =>
      o.trace != trace || o.now != now || o.line != line;
}

/// Fills over 0.9 s while held, then ends. Letting go early shows a hint.
class _HoldToEnd extends StatefulWidget {
  const _HoldToEnd({required this.onEnd, required this.onConfirm});
  final Future<Object?> Function() onEnd;
  final VoidCallback onConfirm;

  @override
  State<_HoldToEnd> createState() => _HoldToEndState();
}

class _HoldToEndState extends State<_HoldToEnd>
    with SingleTickerProviderStateMixin {
  late final _a =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..addStatusListener((st) {
        if (st == AnimationStatus.completed) {
          HapticFeedback.heavyImpact();
          widget.onEnd();
        }
      });
  bool _hint = false;
  Timer? _hintTimer;

  void _release() {
    if (_a.isCompleted) return;
    _a.reverse();
    setState(() => _hint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'End workout',
      onTap: widget.onConfirm,
      child: ExcludeSemantics(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            HapticFeedback.selectionClick();
            _a.forward();
          },
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) => Container(
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.text1,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _a.value,
                    child: ColoredBox(color: context.s.recLow),
                  ),
                  Center(
                    child: Text(
                      _a.value > 0 && _a.status == AnimationStatus.forward
                          ? 'Keep holding'
                          : _hint
                          ? 'Hold to end'
                          : 'End',
                      style: TextStyle(
                        fontFamily: TempoType.family,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.075,
                        color: c.textInverse,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.fill,
    required this.max,
    this.lo,
    this.hi,
    required this.caption,
    this.color,
    this.note,
    this.shaded = false,
  });
  final String label, value, caption;
  final String? note;
  final bool shaded;
  final double fill, max;
  final double? lo, hi;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline(label),
          const SizedBox(height: 6),
          Text(value, style: TempoType.scoreS.c(color ?? c.text1)),
          const SizedBox(height: 6),
          TargetStrip(
            value: fill,
            max: max,
            lo: lo,
            hi: hi,
            color: context.s.strain[1],
            height: 12,
            track: 6,
            marker: false,
            shaded: shaded,
          ),
          const SizedBox(height: 6),
          Text(caption, style: TempoType.caption.c(c.text3)),
          // Always a second line, so both tiles in the row match.
          Text(note ?? '', style: TempoType.caption.c(c.text2)),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerStatefulWidget {
  const _Summary({required this.s});
  final LiveState s;
  @override
  ConsumerState<_Summary> createState() => _SummaryState();
}

class _SummaryState extends ConsumerState<_Summary> {
  int? _rpe;
  static const _words = [
    'Very easy',
    'Easy',
    'Easy',
    'Moderate',
    'Moderate',
    'Somewhat hard',
    'Hard',
    'Very hard',
    'Very hard',
    'Max',
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = context.c, sc0 = context.s;
    final zm = [for (final z in s.zoneSeconds) (z / 60).round()];
    final effect = ref
        .watch(effectProvider(EffectQuery(s.sport?.name, s.sessionStrain)))
        .value;
    final t = s.target;
    final inTarget = t != null && !t.cap && t.contains(s.dayStrain);
    final n = ref.read(liveSessionProvider.notifier);
    return TempoPage(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Overline('Workout saved · ${clockOf(DateTime.now())}'),
              ),
              Transform.translate(
                offset: const Offset(10, 0),
                child: TempoIconButton(
                  TempoIcons.close,
                  label: 'Close',
                  onTap: () {
                    n.close();
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: TempoType.pageTitle.c(c.text1)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  if (s.guided) TextSpan(text: '${_landed(s)} '),
                  const TextSpan(text: 'Day strain is now '),
                  TextSpan(
                    text: n1(s.dayStrain),
                    style: TextStyle(color: c.text1),
                  ),
                  TextSpan(
                    text: t == null
                        ? '.'
                        : t.cap
                        ? ' against a cap of ${t.hi.round()}.'
                        : inTarget
                        ? ' — inside today’s ${t.lo.round()}–${t.hi.round()}.'
                        : ' — today’s target is ${t.lo.round()}–${t.hi.round()}.',
                  ),
                ],
              ),
              style: TempoType.body.c(c.text2),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Stat(
                'Strain',
                '+${n1(s.sessionStrain)}',
                color: sc0.strain[1],
              ),
            ),
            Expanded(child: Stat('Time', mmss(s.elapsed))),
            Expanded(
              child: Stat(
                'Avg / max',
                '${s.avgHr ?? '—'}',
                unit: ' / ${s.maxHr ?? '—'}',
              ),
            ),
          ],
        ),
        Column(
          children: [
            SegmentBar(
              height: 12,
              parts: [for (var i = 0; i < 5; i++) (zm[i], sc0.zone[i])],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 5; i++)
                  Text(
                    'Z${i + 1} ${zm[i]}′',
                    style: TempoType.caption.c(c.text2).tnum,
                  ),
              ],
            ),
          ],
        ),
        TempoCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How hard did that feel?',
                style: TempoType.titleM.c(c.text1),
              ),
              const SizedBox(height: 4),
              Text(
                'Coach compares it with the plan: sessions that keep feeling harder or easier shift the next days.',
                style: TempoType.bodyS.c(c.text2),
              ),
              const SizedBox(height: 14),
              Semantics(
                label: 'Rate of perceived exertion',
                child: Row(
                  children: [
                    for (var i = 1; i <= 10; i++) ...[
                      if (i > 1) const SizedBox(width: 4),
                      Expanded(
                        child: Pressable(
                          label: 'RPE $i',
                          selected: _rpe == i,
                          onTap: () {
                            setState(() => _rpe = i);
                            n.rate(i);
                          },
                          child: AnimatedContainer(
                            duration: TempoMotion.fast,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _rpe == i ? c.text1 : c.surface2,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$i',
                              style: TempoType.body
                                  .copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: _rpe == i ? c.textInverse : c.text1,
                                  )
                                  .tnum,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Very easy', style: TempoType.caption.c(c.text3)),
                  if (_rpe != null)
                    Text(
                      '$_rpe · ${_words[_rpe! - 1]}',
                      style: TempoType.caption.copyWith(
                        color: c.text1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  Text('Max', style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        if (effect != null && effect.n >= 3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TempoRadii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '■',
                    style: TextStyle(fontSize: 10, color: sc0.recMid),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Likely effect on tomorrow: ',
                              style: TextStyle(color: c.text1),
                            ),
                            TextSpan(
                              text:
                                  'sessions like this have moved your next-day recovery by about ${effect.delta >= 0 ? '+' : '−'}${effect.delta.abs().round()} points on average. Hitting your bedtime usually covers it.',
                            ),
                          ],
                        ),
                        style: TempoType.bodyS.c(c.text2),
                      ),
                      const SizedBox(height: 6),
                      TempoBadge('Est. · ${effect.n} sessions', small: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        TempoButton(
          'Save',
          expand: true,
          onTap: () {
            n.close();
            Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }

  static String _landed(LiveState s) {
    final p = s.plan!;
    final work = [
      for (final g in p.segments.skip(1).take(p.segments.length - 2))
        if (g.zone >= 3) g,
    ];
    if (work.isEmpty) return 'Session complete.';
    final hard = (s.zoneSeconds[work.first.zone - 1]) / 60;
    final planned = work.fold(0, (a, g) => a + g.minutes);
    return hard >= planned * .8
        ? 'The work blocks landed in Z${work.first.zone}.'
        : 'About ${hard.round()} of $planned planned minutes landed in Z${work.first.zone}.';
  }
}
