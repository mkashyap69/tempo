import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart' show stepsToday;
import '../core/data_source.dart';
import '../core/everyday.dart' show loadMovement;
import '../core/format.dart';
import '../core/minutes.dart' show loadMinutes;
import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'biomarker.dart';
import 'longevity.dart';
import 'nav.dart';
import 'recovery.dart';
import 'sleep.dart';
import 'strain.dart';

/// Today's number tiles, in the default order.
enum TileId { sleep, recovery, rhr, hrv, steps, brisk, strain, age }

String tileName(TileId id) => switch (id) {
  TileId.sleep => 'Sleep',
  TileId.recovery => 'Recovery',
  TileId.rhr => 'Resting HR',
  TileId.hrv => 'HRV',
  TileId.steps => 'Steps',
  TileId.brisk => 'Brisk minutes',
  TileId.strain => 'Strain',
  TileId.age => 'Tempo Age',
};

/// The order and the hidden tiles, from settings ("-hrv" is hidden).
({List<TileId> order, Set<TileId> hidden}) parseTiles(String? raw) {
  final order = <TileId>[];
  final hidden = <TileId>{};
  for (final p in (raw ?? '').split(',')) {
    final off = p.startsWith('-');
    final id = TileId.values.asNameMap()[off ? p.substring(1) : p];
    if (id == null || order.contains(id)) continue;
    order.add(id);
    if (off) hidden.add(id);
  }
  for (final id in TileId.values) {
    if (!order.contains(id)) order.add(id);
  }
  return (order: order, hidden: hidden);
}

String writeTiles(List<TileId> order, Set<TileId> hidden) =>
    [for (final id in order) hidden.contains(id) ? '-${id.name}' : id.name]
        .join(',');

/// One tile's numbers.
final class TileData {
  const TileData({
    required this.id,
    required this.value,
    this.unit = '',
    required this.line,
    this.good,
    this.spark = const [],
    this.progress,
    this.unusual = false,
  });
  final TileId id;
  final String value, unit;

  /// "▲ 9 vs normal", "of 4,524 a day", "target 10–13".
  final String line;
  final bool? good;

  /// The last 7 days, oldest first (nulls are gaps).
  final List<double?> spark;

  /// 0–1 towards today's goal, instead of a sparkline.
  final double? progress;

  /// Moved away from your normal: shown in calm mode.
  final bool unusual;
}

bool _moved(sc.VsNormal? v) => v != null && v.trend != sc.Trend.flat;

String _delta(sc.VsNormal? v, String Function(double) f) => v == null
    ? 'learning your normal'
    : v.trend == sc.Trend.flat
    ? '● about normal'
    : '${v.trend == sc.Trend.up ? '▲' : '▼'} ${f(v.delta.abs())} vs normal';

final todayTilesProvider = FutureProvider<List<TileData>>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final t = await ref.watch(todayProvider.future);
  final now = DateTime.now();
  final s = t.score;
  // Newest first in history; the tiles want 30 days for normal, 7 to draw.
  final past = t.history.take(30).toList();
  List<double?> spark(double? Function(st.DailyScore) f) => [
    for (final d in past.take(6).toList().reversed) f(d),
    s == null ? null : f(s),
  ];
  final tiles = <TileData>[];

  final sleepV = sc.vsNormal(t.sleepScore, [
    for (final d in past) d.sleepScore ?? d.sleepPerf,
  ], minDelta: 3);
  tiles.add(
    TileData(
      id: TileId.sleep,
      value: t.sleepScore == null ? '–' : '${t.sleepScore!.round()}',
      unit: 'score',
      line: _delta(sleepV, (x) => '${x.round()}'),
      good: sleepV?.good,
      unusual: _moved(sleepV),
      spark: spark((d) => d.sleepScore ?? d.sleepPerf),
    ),
  );
  final recV = sc.vsNormal(t.recovery, [
    for (final d in past)
      if (!d.calibrating) d.recovery,
  ], minDelta: 5);
  tiles.add(
    TileData(
      id: TileId.recovery,
      value: t.recovery == null ? '–' : '${t.recovery!.round()}',
      unit: '%',
      line: t.recovery == null
          ? 'learning · ${t.nights} of 14 nights'
          : _delta(recV, (x) => '${x.round()}'),
      good: recV?.good,
      unusual: _moved(recV),
      spark: spark((d) => d.calibrating ? null : d.recovery),
    ),
  );
  final rhrV = sc.vsNormal(
    s?.rhr,
    [for (final d in past) d.rhr],
    better: sc.Better.lower,
    minDelta: 1,
  );
  tiles.add(
    TileData(
      id: TileId.rhr,
      value: s?.rhr == null ? '–' : '${s!.rhr!.round()}',
      unit: 'bpm',
      line: _delta(rhrV, (x) => '${x.round()}'),
      good: rhrV?.good,
      unusual: _moved(rhrV),
      spark: spark((d) => d.rhr),
    ),
  );
  if (s?.hrv != null) {
    final hrvV = sc.vsNormal(s!.hrv, [
      for (final d in past)
        if (d.hrvKind == s.hrvKind) d.hrv,
    ], minDelta: 2);
    tiles.add(
      TileData(
        id: TileId.hrv,
        value: '${s.hrv!.round()}',
        unit: 'ms',
        line: _delta(hrvV, (x) => '${x.round()}'),
        good: hrvV?.good,
        unusual: _moved(hrvV),
        spark: spark((d) => d.hrvKind == s.hrvKind ? d.hrv : null),
      ),
    );
  }

  final health = (await loadDataSource(db)).isHealth;
  final steps = await stepsToday(db, now);
  final daily = <double>[];
  for (var i = 1; i <= 7; i++) {
    final a = t.day.subtract(Duration(days: i));
    final n = await db.stepsBetween(
      a,
      a.add(const Duration(days: 1)),
      health: health,
    );
    if (n > 0) daily.add(n.toDouble());
  }
  final usual = daily.isEmpty
      ? null
      : daily.reduce((a, b) => a + b) / daily.length;
  tiles.add(
    TileData(
      id: TileId.steps,
      value: grouped(steps),
      line: usual == null ? 'today' : 'usual ${grouped(usual.round())} a day',
      progress: usual == null || usual == 0 ? null : steps / usual,
    ),
  );
  final move = await loadMovement(db);
  tiles.add(
    TileData(
      id: TileId.brisk,
      value: '${move.brisk}',
      unit: 'min',
      line: move.briskAvg == null
          ? '100+ steps a minute'
          : 'usual ${move.briskAvg!.round()} a day',
      progress: move.briskAvg == null || move.briskAvg == 0
          ? null
          : move.brisk / move.briskAvg!,
    ),
  );
  tiles.add(
    TileData(
      id: TileId.strain,
      value: n1(t.strain),
      line: 'target ${strainRange(t.target.lo, t.target.hi)}',
      progress: t.target.hi == 0 ? null : t.strain / t.target.hi,
    ),
  );
  final ages = await db.longevitySince(
    t.day.subtract(const Duration(days: 30)),
  );
  if (ages.isNotEmpty) {
    final last = ages.last, first = ages.first;
    final d = last.tempoAge - first.tempoAge;
    tiles.add(
      TileData(
        id: TileId.age,
        value: last.tempoAge.toStringAsFixed(1),
        line: ages.length < 2 || d.abs() < .05
            ? 'steady this month'
            : '${d < 0 ? '▼' : '▲'} ${d.abs().toStringAsFixed(1)} this month',
        good: ages.length < 2 || d.abs() < .05 ? null : d < 0,
        unusual: ages.length >= 2 && d.abs() >= .3,
        spark: [
          for (final a in ages.skip(math.max(0, ages.length - 7))) a.tempoAge,
        ],
      ),
    );
  }
  return tiles;
});

final _tilesOrderProvider = dbQuery((db, _) async {
  final p = parseTiles(await db.setting(Keys.todayTiles));
  return (
    order: p.order,
    hidden: p.hidden,
    all: await db.setting(Keys.todayTilesAll) == '1',
  );
});

Widget _detail(TileId id) => switch (id) {
  TileId.sleep => const SleepScreen(),
  TileId.recovery || TileId.hrv => const RecoveryScreen(),
  TileId.rhr => const BiomarkerScreen(sc.Lever.restingHr),
  TileId.steps => const BiomarkerScreen(sc.Lever.steps),
  TileId.brisk => const BiomarkerScreen(sc.Lever.activeMinutes),
  TileId.strain => const StrainScreen(),
  TileId.age => const LongevityScreen(),
};

Color _tint(BuildContext context, TileId id) {
  final c = context.c, s = context.s;
  return switch (id) {
    TileId.sleep => s.sleepChannel,
    TileId.recovery => s.recHigh,
    TileId.rhr => s.recLow,
    TileId.hrv => s.sleepRem,
    TileId.steps => c.text2,
    TileId.brisk => s.recHigh,
    TileId.strain => s.strain[1],
    TileId.age => c.text1,
  };
}

/// Days of history each tile can show when expanded (brisk minutes are
/// decoded from minutes, so they stop at 30).
List<int> tileRanges(TileId id) =>
    id == TileId.brisk ? const [7, 30] : const [7, 30, 180];

/// One value a day for [id] over the [days] up to [today], oldest first.
Future<List<double?>> loadTileSeries(
  st.TempoDb db,
  TileId id,
  int days, {
  required DateTime today,
}) async {
  final from = today.subtract(Duration(days: days - 1));
  final keys = [
    for (var i = 0; i < days; i++) st.dateKey(from.add(Duration(days: i))),
  ];
  switch (id) {
    case TileId.steps || TileId.brisk:
      final health = (await loadDataSource(db)).isHealth;
      final out = <double?>[];
      for (var i = 0; i < days; i++) {
        final a = from.add(Duration(days: i));
        if (id == TileId.steps) {
          final n = await db.stepsBetween(
            a,
            a.add(const Duration(days: 1)),
            health: health,
          );
          out.add(n == 0 ? null : n.toDouble());
        } else {
          final m = (await loadMinutes(
            db,
            a,
            a.add(const Duration(days: 1)),
          )).minutes;
          out.add(
            m.any((x) => x.steps > 0) ? sc.briskMinutes(m).toDouble() : null,
          );
        }
      }
      return out;
    case TileId.age:
      final byDay = {
        for (final l in await db.longevitySince(from)) l.date: l.tempoAge,
      };
      return [for (final k in keys) byDay[k]];
    case _:
      final byDay = {
        for (final s in await db.scoresBetween(from, today)) s.date: s,
      };
      final kind = byDay[st.dateKey(today)]?.hrvKind;
      double? pick(st.DailyScore? s) => s == null
          ? null
          : switch (id) {
              TileId.sleep => s.sleepScore ?? s.sleepPerf,
              TileId.recovery => s.calibrating ? null : s.recovery,
              TileId.rhr => s.rhr,
              TileId.hrv => s.hrvKind == kind ? s.hrv : null,
              _ => s.strain,
            };
      return [for (final k in keys) pick(byDay[k])];
  }
}

final _seriesProvider = FutureProvider.family<List<double?>, (TileId, int)>((
  ref,
  key,
) async {
  ref.watch(dbTickProvider);
  final t = await ref.watch(todayProvider.future);
  return loadTileSeries(ref.watch(dbProvider), key.$1, key.$2, today: t.day);
});

/// How each number is worked out, for the expanded tile.
String tileHow(TileId id) => switch (id) {
  TileId.sleep =>
    'Sleep score, 0–100: hours asleep against your need, then bedtime, '
        'wake-ups and time in bed.',
  TileId.recovery =>
    'From last night’s HRV (or the band’s stress index), resting heart '
        'rate and sleep, each against your own baseline.',
  TileId.rhr =>
    'Your lowest steady heart rate overnight. Lower than usual is usually '
        'good; 5 bpm or more above it can mean strain or illness coming.',
  TileId.hrv =>
    'Overnight heart-rate variability as your watch wrote it to Health '
        '(SDNN on Apple Watch, RMSSD on Android), only compared with nights '
        'of the same kind.',
  TileId.steps =>
    'Steps from midnight to now, from your band or Health. Usual is the '
        'average of the last 7 days with steps.',
  TileId.brisk =>
    'Minutes at 100 or more steps a minute: a simple measure of moderate '
        'activity.',
  TileId.strain =>
    'Effort 0–21 from time in heart-rate zones today. The target comes '
        'from this morning’s recovery.',
  TileId.age =>
    'Your age adjusted by fitness, resting heart rate, activity, sleep and '
        'more. Longevity shows every part.',
};

/// Today: "Your numbers". Calm by default: only the tiles that moved away
/// from your normal show, the rest fold into one line; "Show all" is
/// remembered. Tap a tile to open it in place (7 days, 30 days, 6 months,
/// your normal band, how it's calculated). Edit reorders and hides.
class TodayTiles extends ConsumerStatefulWidget {
  const TodayTiles({super.key});

  @override
  ConsumerState<TodayTiles> createState() => _TodayTilesState();
}

class _TodayTilesState extends ConsumerState<TodayTiles> {
  TileId? _open;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = ref.watch(todayTilesProvider).value;
    final cfg = ref.watch(_tilesOrderProvider).value;
    if (data == null || cfg == null) return const SizedBox.shrink();
    final db = ref.read(dbProvider);
    final byId = {for (final d in data) d.id: d};
    final visible = [
      for (final id in cfg.order)
        if (!cfg.hidden.contains(id) && byId[id] != null) byId[id]!,
    ];
    final calm = !cfg.all;
    final shown = calm
        ? [
            for (final d in visible)
              if (d.unusual) d,
          ]
        : visible;
    final rest = [
      for (final d in visible)
        if (!shown.contains(d)) d,
    ];
    Future<void> setAll(bool on) =>
        db.putSetting(Keys.todayTilesAll, on ? '1' : '0');

    final rows = <Widget>[];
    var i = 0;
    while (i < shown.length) {
      final d = shown[i];
      if (d.id == _open) {
        rows.add(_Expanded(d: d, onClose: () => setState(() => _open = null)));
        i++;
        continue;
      }
      final next = i + 1 < shown.length && shown[i + 1].id != _open
          ? shown[i + 1]
          : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Tile(d, onTap: () => setState(() => _open = d.id)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: next == null
                    ? const SizedBox.shrink()
                    : _Tile(next, onTap: () => setState(() => _open = next.id)),
              ),
            ],
          ),
        ),
      );
      i += next == null ? 1 : 2;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your numbers', style: TempoType.titleM.c(c.text1)),
            ),
            TempoButton(
              calm ? 'Show all' : 'Calm',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () => setAll(calm),
            ),
            const SizedBox(width: 8),
            TempoButton(
              'Edit',
              small: true,
              kind: ButtonKind.secondary,
              onTap: () => showTempoSheet<void>(
                context,
                builder: (_) =>
                    _EditTiles(order: cfg.order, hidden: cfg.hidden),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          visible.isEmpty
              ? 'All tiles are hidden. Edit to bring some back.'
              : !calm
              ? 'All your numbers. Tap one to see its trend.'
              : shown.isEmpty
              ? 'Everything is in your normal range today.'
              : shown.length == 1
              ? 'One thing stands out today. Everything else is normal.'
              : '${shown.length} things stand out today. Everything else is '
                    'normal.',
          style: TempoType.bodyS.c(c.text2),
        ),
        for (final r in rows) ...[const SizedBox(height: 10), r],
        if (calm && rest.isNotEmpty) ...[
          const SizedBox(height: 10),
          Pressable(
            label: 'Show the others',
            onTap: () => setAll(true),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TempoRadii.lg),
                border: Border.all(color: c.lineStrong, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rest.map((d) => tileName(d.id)).join(', ')} · '
                      '${rest.length == 1 ? '1 other normal' : '${rest.length} others normal'}',
                      style: TempoType.bodyS.c(c.text2),
                    ),
                  ),
                  Text('›', style: TempoType.titleM.c(c.text3)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A tile opened in place: its trend over 7 days, 30 days or 6 months on
/// your normal band, the numbers behind it and how it's worked out.
class _Expanded extends ConsumerStatefulWidget {
  const _Expanded({required this.d, required this.onClose});
  final TileData d;
  final VoidCallback onClose;

  @override
  ConsumerState<_Expanded> createState() => _ExpandedState();
}

class _ExpandedState extends ConsumerState<_Expanded> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = widget.d;
    final ranges = tileRanges(d.id);
    final days = ranges.contains(_days) ? _days : ranges.last;
    final series = ref.watch(_seriesProvider((d.id, days))).value;
    final xs = [for (final x in series ?? const <double?>[]) ?x];
    final mean = xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
    final sd = mean == null
        ? null
        : math.sqrt(
            xs.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) /
                xs.length,
          );
    String f(double x) => switch (d.id) {
      TileId.steps => grouped(x.round()),
      TileId.strain || TileId.age => x.toStringAsFixed(1),
      _ => '${x.round()}',
    };
    final tint = _tint(context, d.id);
    return TempoCard(
      label: '${tileName(d.id)}, open',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tileName(d.id), style: TempoType.caption.c(c.text2)),
                    Text(
                      '${d.value}${d.unit.isEmpty ? '' : ' ${d.unit}'}',
                      style: TempoType.titleL.c(c.text1).tnum,
                    ),
                    Text(d.line, style: TempoType.caption.c(c.text2).tnum),
                  ],
                ),
              ),
              TempoButton(
                'Close',
                small: true,
                kind: ButtonKind.secondary,
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final r in ranges) ...[
                TempoButton(
                  r == 7
                      ? '7 days'
                      : r == 30
                      ? '30 days'
                      : '6 months',
                  small: true,
                  kind: r == days ? ButtonKind.primary : ButtonKind.secondary,
                  onTap: () => setState(() => _days = r),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: series == null
                ? const SizedBox.shrink()
                : xs.length < 2
                ? Center(
                    child: Text(
                      'Not enough days yet',
                      style: TempoType.bodyS.c(c.text3),
                    ),
                  )
                : Semantics(
                    label:
                        '${tileName(d.id)} over $days days, with your normal '
                        'range shaded',
                    child: CustomPaint(
                      painter: _Trend(
                        series,
                        tint,
                        band: c.surface2,
                        lo: mean! - sd!,
                        hi: mean + sd,
                      ),
                    ),
                  ),
          ),
          if (mean != null) ...[
            const SizedBox(height: 8),
            Text(
              'Average ${f(mean)} · usual range ${f(mean - sd!)}–${f(mean + sd)} '
              '· ${xs.length} days',
              style: TempoType.caption.c(c.text2).tnum,
            ),
          ],
          const SizedBox(height: 12),
          Text('How it’s worked out', style: TempoType.label.c(c.text1)),
          const SizedBox(height: 2),
          Text(tileHow(d.id), style: TempoType.bodyS.c(c.text2)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TempoButton(
              'Open ${tileName(d.id)} ›',
              small: true,
              kind: ButtonKind.text,
              onTap: () => push(context, _detail(d.id)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line over the shaded usual range (mean ± one standard deviation).
class _Trend extends CustomPainter {
  _Trend(
    this.values,
    this.color, {
    required this.band,
    required this.lo,
    required this.hi,
  });
  final List<double?> values;
  final Color color, band;
  final double lo, hi;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = values.whereType<double>();
    final min = math.min(xs.reduce(math.min), lo);
    final max = math.max(xs.reduce(math.max), hi);
    final span = max - min == 0 ? 1 : max - min;
    double y(double v) =>
        size.height - 4 - (v - min) / span * (size.height - 8);
    canvas.drawRRect(
      RRect.fromLTRBR(0, y(hi), size.width, y(lo), const Radius.circular(6)),
      Paint()..color = band,
    );
    final step = size.width / math.max(1, values.length - 1);
    final path = Path();
    var started = false;
    Offset? last;
    for (final (i, v) in values.indexed) {
      if (v == null) {
        started = false;
        continue;
      }
      final o = Offset(i * step, y(v));
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
      last = o;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    if (last != null) canvas.drawCircle(last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Trend o) =>
      o.values != values || o.color != color || o.lo != lo || o.hi != hi;
}

class _Tile extends StatelessWidget {
  const _Tile(this.d, {required this.onTap});
  final TileData d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final tint = _tint(context, d.id);
    final lineColor = d.good == null
        ? c.text2
        : d.good!
        ? s.recHigh
        : s.recMid;
    return TempoCard(
      label: '${tileName(d.id)} ${d.value} ${d.unit}',
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tileName(d.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TempoType.caption.c(c.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: d.value, style: TempoType.titleL.c(c.text1)),
                if (d.unit.isNotEmpty)
                  TextSpan(
                    text: ' ${d.unit}',
                    style: TempoType.caption.c(c.text2),
                  ),
              ],
            ),
            maxLines: 1,
          ).tnumText,
          const SizedBox(height: 2),
          Text(
            d.line,
            maxLines: 2,
            style: TempoType.caption
                .copyWith(fontWeight: FontWeight.w500)
                .c(lineColor)
                .tnum,
          ),
          const Spacer(),
          const SizedBox(height: 8),
          if (d.progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: d.progress!.clamp(0.0, 1.0),
                minHeight: 6,
                color: tint,
                backgroundColor: c.trackOff,
              ),
            )
          else if (d.spark.whereType<double>().length >= 2)
            SizedBox(
              height: 26,
              width: double.infinity,
              child: CustomPaint(painter: _Spark(d.spark, tint)),
            ),
        ],
      ),
    );
  }
}

extension on Text {
  /// Tabular figures on rich text without restyling it.
  Widget get tnumText => DefaultTextStyle.merge(
    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    child: this,
  );
}

class _Spark extends CustomPainter {
  _Spark(this.values, this.color);
  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = values.whereType<double>();
    final lo = xs.reduce(math.min), hi = xs.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    final step = size.width / math.max(1, values.length - 1);
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var started = false;
    Offset? last;
    for (final (i, v) in values.indexed) {
      if (v == null) {
        started = false;
        continue;
      }
      final o = Offset(
        i * step,
        size.height - 3 - (v - lo) / span * (size.height - 6),
      );
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
      last = o;
    }
    canvas.drawPath(path, p);
    if (last != null) canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Spark o) => o.values != values || o.color != color;
}

class _EditTiles extends ConsumerStatefulWidget {
  const _EditTiles({required this.order, required this.hidden});
  final List<TileId> order;
  final Set<TileId> hidden;

  @override
  ConsumerState<_EditTiles> createState() => _EditTilesState();
}

class _EditTilesState extends ConsumerState<_EditTiles> {
  late final List<TileId> _order = [...widget.order];
  late final Set<TileId> _hidden = {...widget.hidden};

  Future<void> _save() => ref
      .read(dbProvider)
      .putSetting(Keys.todayTiles, writeTiles(_order, _hidden));

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= _order.length) return;
    setState(() {
      final x = _order.removeAt(i);
      _order.insert(j, x);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your numbers', style: TempoType.titleM.c(c.text1)),
        const SizedBox(height: 4),
        Text(
          'Show, hide and reorder the tiles on Today.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: CardList(
              children: [
                for (final (i, id) in _order.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tileName(id),
                            style: TempoType.label.c(
                              _hidden.contains(id) ? c.text3 : c.text1,
                            ),
                          ),
                        ),
                        TempoIconButton(
                          TempoIcons.down,
                          label: 'Move ${tileName(id)} down',
                          size: 16,
                          onTap: i == _order.length - 1
                              ? null
                              : () => _move(i, 1),
                        ),
                        TempoIconButton(
                          TempoIcons.up,
                          label: 'Move ${tileName(id)} up',
                          size: 16,
                          onTap: i == 0 ? null : () => _move(i, -1),
                        ),
                        TempoSwitch(
                          value: !_hidden.contains(id),
                          label: 'Show ${tileName(id)}',
                          onChanged: (on) {
                            setState(
                              () => on ? _hidden.remove(id) : _hidden.add(id),
                            );
                            _save();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TempoButton('Done', expand: true, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}
