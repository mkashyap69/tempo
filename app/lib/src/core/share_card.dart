import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../design/components.dart' show TempoLockup, showTempoToast;
import '../design/type.dart';
import '../screens/live_workout.dart' show RoutePainter;
import 'route_tracker.dart' show RoutePoint;

/// One number on a share card.
class ShareStat {
  const ShareStat(this.label, this.value, {this.unit, this.color});
  final String label, value;
  final String? unit;
  final Color? color;
}

/// The card people share: Tempo's lockup and the date, a title, one big
/// number, a grid of stats and, for a walk or run, the route's shape and the
/// time in zones. Always dark, so it looks the same wherever it's posted.
/// Rendered off screen at 360 × n logical px, saved at 3× (1080 px wide).
/// Only what's on the card leaves the phone, and only when the user shares.
class TempoShareCard extends StatelessWidget {
  const TempoShareCard({
    super.key,
    required this.kicker,
    required this.title,
    required this.hero,
    this.heroUnit,
    this.heroLabel,
    required this.accent,
    this.stats = const [],
    this.route = const [],
    this.zoneMinutes,
    this.note,
    this.date,
  });

  final String kicker, title, hero;
  final String? heroUnit, heroLabel, note;
  final Color accent;
  final List<ShareStat> stats;
  final List<RoutePoint?> route;

  /// Minutes in Z1..Z5, for the bar; null hides it.
  final List<int>? zoneMinutes;
  final DateTime? date;

  static const _bg = Color(0xFF0A0B0D), _bgHi = Color(0xFF1C1F24);
  static const _text1 = Color(0xFFF3F2EF), _text2 = Color(0xFFA9ADB4);
  static const _text3 = Color(0xFF858A92), _line = Color(0xFF2A2E35);
  static const _zones = [
    Color(0xFF5D636D),
    Color(0xFFFFE0B3),
    Color(0xFFFFBE76),
    Color(0xFFFF9446),
    Color(0xFFEE6A2C),
  ];

  static String _date(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
  }

  TextStyle _t(double size, Color c, {FontWeight w = FontWeight.w400}) =>
      TextStyle(
        fontFamily: TempoType.family,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: 1.15,
        decoration: TextDecoration.none,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final drawn = route.whereType<RoutePoint>().length >= 2;
    final zm = zoneMinutes;
    final zTotal = zm == null ? 0 : zm.fold<int>(0, (a, b) => a + b);
    return Container(
      width: 360,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgHi, _bg],
        ),
      ),
      child: Stack(
        children: [
          // A soft glow in the card's colour, top right.
          Positioned(
            right: -120,
            top: -140,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: .22),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const TempoLockup(size: 16, color: _text1),
                    const Spacer(),
                    Text(_date(date ?? DateTime.now()), style: _t(12, _text3)),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  kicker.toUpperCase(),
                  style: _t(
                    11,
                    accent,
                    w: FontWeight.w600,
                  ).copyWith(letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(title, style: _t(24, _text1, w: FontWeight.w500)),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      hero,
                      style: _t(
                        76,
                        _text1,
                        w: FontWeight.w300,
                      ).copyWith(height: 1, letterSpacing: -3),
                    ),
                    if (heroUnit != null) ...[
                      const SizedBox(width: 6),
                      Text(heroUnit!, style: _t(20, _text2)),
                    ],
                  ],
                ),
                if (heroLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(heroLabel!, style: _t(14, accent, w: FontWeight.w500)),
                ],
                if (drawn) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 170,
                    child: CustomPaint(
                      painter: RoutePainter(
                        route: route,
                        line: accent,
                        start: _text3,
                        grid: _line,
                      ),
                    ),
                  ),
                ],
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    runSpacing: 14,
                    children: [
                      for (final s in stats)
                        SizedBox(
                          width: 104,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label, style: _t(11, _text3)),
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  text: s.value,
                                  style: _t(
                                    22,
                                    s.color ?? _text1,
                                    w: FontWeight.w500,
                                  ),
                                  children: [
                                    if (s.unit != null)
                                      TextSpan(
                                        text: s.unit,
                                        style: _t(12, _text3),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (zm != null && zTotal > 0) ...[
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (var i = 0; i < 5; i++)
                            if (zm[i] > 0)
                              Expanded(
                                flex: zm[i],
                                child: Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  color: _zones[i],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < 5; i++)
                        Text('Z${i + 1} ${zm[i]}′', style: _t(11, _text2)),
                    ],
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: 18),
                  Text(note!, style: _t(13, _text2)),
                ],
                const SizedBox(height: 22),
                Container(height: 1, color: _line),
                const SizedBox(height: 12),
                Text(
                  'Recovery, strain and sleep · tempo',
                  style: _t(11, _text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders [card] off screen, saves it as a PNG and opens the share sheet.
Future<void> shareCard(
  BuildContext context,
  Widget card, {
  required String name,
  String? text,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -4000,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.noScaling),
          child: Directionality(textDirection: TextDirection.ltr, child: card),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/tempo-$name.png');
    await f.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        text: text,
      ),
    );
  } catch (e) {
    if (context.mounted) showTempoToast(context, 'Couldn’t make the image');
  } finally {
    entry.remove();
  }
}
