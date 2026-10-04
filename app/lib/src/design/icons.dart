import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Iconography: 24 px grid, 1.75 stroke, round caps and joins, no fills
/// except play. Paths are the design's SVG path strings.
abstract final class TempoIcons {
  static const today = 'M5 20V6M10 20v-7M15 20v-7M20 20v-7';
  static const coach = 'M6 21V4h11l-2.5 4.5L17 13H6';
  static const trends = 'M3 17l5.5-6 4 3.5L21 6M15 6h6v6';
  static const journal =
      'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM9 8h6M9 12h6M9 16h3';
  static const profile =
      'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c1.4-3.6 4.4-5.5 8-5.5s6.6 1.9 8 5.5';
  static const band =
      'M10 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM12 9v6';
  static const sync =
      'M20 12a8 8 0 0 1-14 5.3M4 12a8 8 0 0 1 14-5.3M18 3v4h-4M6 21v-4h4';
  static const heartRate = 'M3 12h4l2-5 4 10 2-5h6';
  static const sleep = 'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z';
  static const stress = 'M4 12c2-4 4-4 6 0s4 4 6 0 3-3 4-1';
  static const spo2 = 'M12 3c3 4 6 7.5 6 11a6 6 0 0 1-12 0c0-3.5 3-7 6-11z';
  static const steps =
      'M8 14c-2 0-3-2-3-5s1-5 3-5 3 2 3 5-1 5-3 5zM16 20c-2 0-3-2-3-4s1-4 3-4 3 2 3 4-1 4-3 4z';
  static const zone = 'M4 20h3v-4H4zM10.5 20h3V11h-3zM17 20h3V5h-3z';
  static const load = 'M4 17l6-6 4 4 6-8M14 7h6v6';
  static const bedtime = 'M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z';
  static const clock = bedtime;
  static const info = 'M12 11v5M12 8v.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z';
  static const estimate = 'M4 12h2M9 12h2M14 12h2M19 12h1M12 4v2M12 18v2';
  static const private = 'M6 11h12v10H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3';
  static const back = 'M15 6l-6 6 6 6';
  static const chevron = 'M9 6l6 6-6 6';
  static const down = 'M6 9l6 6 6-6';
  static const close = 'M6 6l12 12M18 6L6 18';
  static const check = 'M5 12.5l4.5 4.5L19 7';
  static const spinner = 'M21 12a9 9 0 1 1-6.2-8.56';
  static const dot = 'M12 12h.01';
  static const alert =
      'M12 8v5M12 16.5v.01M10.3 3.9L2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z';
  static const bluetooth = 'M7 7l10 10-5 4V3l5 4L7 17';
  static const search = 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4';
  static const link =
      'M9 15l6-6M10 6l1-1a4 4 0 0 1 6 6l-1 1M14 18l-1 1a4 4 0 0 1-6-6l1-1';
  static const bell = 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 21h4';
  static const edit = 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4';
  static const swap = 'M4 7h11M11 3l4 4-4 4M20 17H9M13 13l-4 4 4 4';
  static const calendar = 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4';
  static const timeline = 'M4 12h16M4 6h10M4 18h7';
  static const baselines = 'M3 12h18M3 8h18M3 16h18';
  static const arrow = 'M5 12h14M13 6l6 6-6 6';
  static const share = 'M12 15V3M7 8l5-5 5 5M5 13v7h14v-7';
  static const bandPill = 'M8 3h8v18H8zM12 9v6';
  static const play =
      'M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z';
}

class TempoIcon extends StatelessWidget {
  const TempoIcon(
    this.path, {
    super.key,
    this.size = 24,
    this.color,
    this.stroke = 1.75,
    this.fill = false,
  });
  final String path;
  final double size;
  final Color? color;
  final double stroke;
  final bool fill;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _IconPainter(
        path,
        color ??
            DefaultTextStyle.of(context).style.color ??
            const Color(0xFF000000),
        stroke,
        fill,
      ),
    ),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.d, this.color, this.stroke, this.fill);
  final String d;
  final Color color;
  final double stroke;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(
      parseSvgPath(d),
      Paint()
        ..color = color
        ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter o) =>
      o.d != d || o.color != color || o.stroke != stroke;
}

final _cache = <String, Path>{};

/// Minimal SVG path parser: M L H V C S Q A Z, absolute and relative.
Path parseSvgPath(String d) => _cache.putIfAbsent(d, () => _parse(d));

Path _parse(String d) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsQqAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final p = Path();
  var i = 0;
  var cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0, cx = 0, cy = 0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        p.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = ox + n();
        y = oy + n();
        p.lineTo(x, y);
      case 'H':
        x = (rel ? x : 0) + n();
        p.lineTo(x, y);
      case 'V':
        y = (rel ? y : 0) + n();
        p.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n();
        cx = ox + n();
        cy = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, cx, cy, x, y);
        continue;
      case 'S':
        final x1 = 2 * x - cx, y1 = 2 * y - cy;
        cx = ox + n();
        cy = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, cx, cy, x, y);
        continue;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(x1, y1, x, y);
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = n() != 0, sweep = n() != 0;
        x = ox + n();
        y = oy + n();
        p.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot * math.pi / 180,
          largeArc: large,
          clockwise: sweep,
        );
      case 'Z':
        if (i < tokens.length && !isCmd(tokens[i])) i++; // malformed; skip
        p.close();
        x = sx;
        y = sy;
    }
    cx = x;
    cy = y;
  }
  return p;
}
