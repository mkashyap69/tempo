import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// Drawing context in design view-box units (charts are drawn at 520 wide,
/// like the canvas, then scaled uniformly).
class Ink2 {
  Ink2(this.canvas, this.c, this.s);
  final Canvas canvas;
  final TempoColors c;
  final TempoScales s;

  Paint stroke(Color color, double w, {bool round = true}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = round ? StrokeCap.round : StrokeCap.butt;

  Paint fill(Color color, [double opacity = 1]) =>
      Paint()..color = color.withValues(alpha: color.a * opacity);

  void line(
    Offset a,
    Offset b,
    Color color, {
    double w = 1,
    List<double>? dash,
  }) {
    if (dash == null) {
      canvas.drawLine(a, b, stroke(color, w, round: false));
      return;
    }
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    var t = 0.0, on = true, k = 0;
    while (t < len) {
      final seg = dash[k % dash.length];
      final e = (t + seg).clamp(0, len).toDouble();
      if (on) {
        canvas.drawLine(a + u * t, a + u * e, stroke(color, w, round: false));
      }
      t = e;
      on = !on;
      k++;
    }
  }

  void polyline(
    List<Offset> pts,
    Color color, {
    double w = 2,
    List<double>? dash,
  }) {
    if (pts.length < 2) return;
    if (dash != null) {
      for (var i = 1; i < pts.length; i++) {
        line(pts[i - 1], pts[i], color, w: w, dash: dash);
      }
      return;
    }
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(p, stroke(color, w));
  }

  /// Polyline that breaks at null points.
  void gappedLine(List<Offset?> pts, Color color, {double w = 2}) {
    var run = <Offset>[];
    for (final p in pts) {
      if (p == null) {
        polyline(run, color, w: w);
        run = [];
      } else {
        run.add(p);
      }
    }
    polyline(run, color, w: w);
  }

  void area(
    List<Offset> top,
    List<Offset> bottom,
    Color color,
    double opacity,
  ) {
    if (top.isEmpty) return;
    final p = Path()..moveTo(top.first.dx, top.first.dy);
    for (final q in top.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    for (final q in bottom.reversed) {
      p.lineTo(q.dx, q.dy);
    }
    p.close();
    canvas.drawPath(p, fill(color, opacity));
  }

  void rect(Rect r, Color color, {double opacity = 1, double radius = 0}) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(radius)),
        fill(color, opacity),
      );

  void outline(Rect r, Color color, {double w = 1.5, double radius = 0}) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(w / 2), Radius.circular(radius)),
        stroke(color, w),
      );

  void dot(Offset p, double r, Color color, {double opacity = 1}) =>
      canvas.drawCircle(p, r, fill(color, opacity));

  void ring(Offset p, double r, Color color, {double w = 2, Color? inside}) {
    if (inside != null) canvas.drawCircle(p, r, fill(inside));
    canvas.drawCircle(p, r, stroke(color, w));
  }

  void text(
    String t,
    Offset at, {
    double size = 14,
    Color? color,
    TextAlign align = TextAlign.left,
    FontWeight weight = FontWeight.w400,
    bool baseline = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontFamily: TempoType.family,
          fontSize: size,
          color: color ?? c.text3,
          fontWeight: weight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right || TextAlign.end => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    // SVG text y is the baseline.
    final dy = baseline
        ? at.dy - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        : at.dy;
    tp.paint(canvas, Offset(dx, dy));
  }
}

typedef ChartDraw = void Function(Ink2 ink, Size box);

/// A chart drawn in a [width] × [height] view box, scaled to the available
/// width. With [animate], the drawing reveals left to right (m-draw).
class SvgChart extends StatelessWidget {
  const SvgChart({
    super.key,
    required this.height,
    required this.draw,
    this.width = 520,
    this.animate = true,
    this.semantics,
    this.stretchHeight,
  });
  final double width, height;
  final ChartDraw draw;
  final bool animate;
  final String? semantics;

  /// Rendered height in logical px with non-uniform scaling
  /// (preserveAspectRatio="none").
  final double? stretchHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    Widget paint(double t) => CustomPaint(
      painter: _Painter(draw, width, height, c, s, t),
      size: Size.infinite,
    );
    final child = animate && !context.reduceMotion
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: TempoMotion.draw,
            builder: (_, t, _) => paint(t),
          )
        : paint(1);
    return Semantics(
      label: semantics,
      image: semantics != null,
      child: stretchHeight != null
          ? SizedBox(
              height: stretchHeight,
              width: double.infinity,
              child: child,
            )
          : AspectRatio(aspectRatio: width / height, child: child),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.draw, this.w, this.h, this.c, this.s, this.t);
  final ChartDraw draw;
  final double w, h, t;
  final TempoColors c;
  final TempoScales s;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (t < 1) {
      canvas.clipRect(
        Rect.fromLTWH(-20, -40, size.width * t + 20, size.height + 80),
      );
    }
    canvas.scale(size.width / w, size.height / h);
    draw(Ink2(canvas, c, s), Size(w, h));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Painter o) => true;
}
