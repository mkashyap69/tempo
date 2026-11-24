import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile.dart' show Keys;
import '../core/weather.dart';
import '../design/tokens.dart';
import '../state/providers.dart';

/// The sky over you, or null when weather is off (D3).
final weatherProvider = FutureProvider<Weather?>((ref) {
  ref.watch(settingProvider(Keys.weather));
  ref.watch(minuteClockProvider);
  return currentWeather(ref.watch(dbProvider));
});

/// A soft wash of the sky behind the top of Today: warm light when clear,
/// grey when cloudy, falling rain or snow. Quiet on purpose: it sits under
/// the rings and text, and stops moving with Reduce Motion.
class WeatherBackdrop extends ConsumerStatefulWidget {
  const WeatherBackdrop({super.key, this.height = 360});
  final double height;

  @override
  ConsumerState<WeatherBackdrop> createState() => _WeatherBackdropState();
}

class _WeatherBackdropState extends ConsumerState<WeatherBackdrop>
    with SingleTickerProviderStateMixin {
  late final _tick = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(weatherProvider).value;
    if (w == null) return const SizedBox.shrink();
    final c = context.c;
    final moving =
        (w.sky == Sky.rain ||
            w.sky == Sky.drizzle ||
            w.sky == Sky.snow ||
            w.sky == Sky.storm) &&
        !context.reduceMotion;
    if (moving && !_tick.isAnimating) _tick.repeat();
    if (!moving && _tick.isAnimating) _tick.stop();
    final tint = skyTint(w.sky, day: w.day);
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Semantics(
          label: 'Weather: ${skyWord(w.sky)}',
          child: AnimatedBuilder(
            animation: _tick,
            builder: (_, _) => CustomPaint(
              painter: _SkyPainter(
                sky: w.sky,
                day: w.day,
                tint: tint,
                bg: c.bg,
                t: _tick.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wash's colour for a sky.
Color skyTint(Sky s, {required bool day}) {
  if (!day) return const Color(0xFF2B3A67);
  return switch (s) {
    Sky.clear => const Color(0xFFFFB45C),
    Sky.partly => const Color(0xFFE8B77A),
    Sky.cloudy || Sky.fog => const Color(0xFF8A94A6),
    Sky.drizzle || Sky.rain => const Color(0xFF4F7CAC),
    Sky.snow => const Color(0xFFBFD4EA),
    Sky.storm => const Color(0xFF4B4E6D),
  };
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.sky,
    required this.day,
    required this.tint,
    required this.bg,
    required this.t,
  });
  final Sky sky;
  final bool day;
  final Color tint, bg;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: .28), bg.withValues(alpha: 0)],
        ).createShader(rect),
    );
    if (day && (sky == Sky.clear || sky == Sky.partly)) {
      final c = Offset(size.width * .82, size.height * .12);
      canvas.drawCircle(
        c,
        size.width * .42,
        Paint()
          ..shader = RadialGradient(
            colors: [tint.withValues(alpha: .30), tint.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: size.width * .42)),
      );
    }
    if (sky == Sky.cloudy || sky == Sky.partly || sky == Sky.fog) {
      final p = Paint()
        ..color = tint.withValues(alpha: .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      for (final (x, y, r) in const [
        (.15, .18, .22),
        (.45, .10, .28),
        (.78, .22, .20),
      ]) {
        canvas.drawCircle(
          Offset(size.width * x, size.height * y),
          size.width * r,
          p,
        );
      }
    }
    final rain = sky == Sky.rain || sky == Sky.drizzle || sky == Sky.storm;
    if (rain || sky == Sky.snow) {
      final n = sky == Sky.drizzle ? 26 : 44;
      final rnd = math.Random(7);
      final p = Paint()
        ..color = (sky == Sky.snow ? Colors.white : tint).withValues(
          alpha: sky == Sky.snow ? .45 : .35,
        )
        ..strokeWidth = sky == Sky.snow ? 0 : 1.2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < n; i++) {
        final x0 = rnd.nextDouble() * size.width;
        final phase = rnd.nextDouble();
        final speed = sky == Sky.snow ? .35 : 1.0;
        final y = ((phase + t * speed * 3) % 1) * size.height;
        final fade = 1 - y / size.height;
        if (sky == Sky.snow) {
          final x = x0 + math.sin((t * 6 + phase) * math.pi * 2) * 6;
          canvas.drawCircle(
            Offset(x, y),
            1.6 + rnd.nextDouble() * 1.4,
            p..color = p.color.withValues(alpha: .45 * fade),
          );
        } else {
          canvas.drawLine(
            Offset(x0, y),
            Offset(x0 - 2, y + 9),
            p..color = p.color.withValues(alpha: .35 * fade),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) =>
      o.t != t || o.sky != sky || o.day != day || o.bg != bg;
}
