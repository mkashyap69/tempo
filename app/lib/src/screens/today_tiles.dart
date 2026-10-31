import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_extras.dart' show stepsToday;
import '../core/data_source.dart';
import '../core/everyday.dart' show loadMovement;
import '../core/format.dart';
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
}

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
        spark: [
          for (final a in ages.skip(math.max(0, ages.length - 7))) a.tempoAge,
        ],
      ),
    );
  }
  return tiles;
});

final _tilesOrderProvider = dbQuery(
  (db, _) async => parseTiles(await db.setting(Keys.todayTiles)),
);

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

/// Today: "Your numbers", a 2-column grid of tiles (today against your
/// normal, a 7-day line or progress to the goal). Tap opens the detail;
/// Edit reorders and hides.
class TodayTiles extends ConsumerWidget {
  const TodayTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final data = ref.watch(todayTilesProvider).value;
    final cfg = ref.watch(_tilesOrderProvider).value;
    if (data == null || cfg == null) return const SizedBox.shrink();
    final byId = {for (final d in data) d.id: d};
    final shown = [
      for (final id in cfg.order)
        if (!cfg.hidden.contains(id) && byId[id] != null) byId[id]!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your numbers', style: TempoType.titleM.c(c.text1)),
            ),
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
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Text(
            'All tiles are hidden. Edit to bring some back.',
            style: TempoType.bodyS.c(c.text2),
          ),
        for (var r = 0; r < shown.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Tile(shown[r])),
                const SizedBox(width: 10),
                Expanded(
                  child: r + 1 < shown.length
                      ? _Tile(shown[r + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.d);
  final TileData d;

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
      onTap: () => push(context, _detail(d.id)),
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
