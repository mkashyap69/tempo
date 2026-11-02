import 'package:flutter/material.dart';

import 'icons.dart';

/// A small heart that beats at [bpm]: a strong beat then a softer one, as
/// a pulse feels. Still (and dimmed) with no reading, or when the system
/// asks for reduced motion.
class BeatingHeart extends StatefulWidget {
  const BeatingHeart({
    super.key,
    required this.bpm,
    required this.color,
    this.size = 22,
    this.active = true,
  });

  final int? bpm;
  final Color color;
  final double size;

  /// False while paused or with no signal: the heart rests.
  final bool active;

  /// One beat's length for [bpm], kept within 30–220 bpm.
  static Duration period(int bpm) =>
      Duration(milliseconds: (60000 / bpm.clamp(30, 220)).round());

  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);

  // Lub-dub: up fast, down, a smaller second beat, then rest.
  static final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.28,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.28,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 14,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 10,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 14,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
  ]);

  bool get _beating => widget.active && widget.bpm != null && widget.bpm! > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BeatingHeart old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm || old.active != widget.active) _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_beating || still) {
      _a.stop();
      _a.value = 0;
      return;
    }
    final d = BeatingHeart.period(widget.bpm!);
    if (_a.duration == d && _a.isAnimating) return;
    _a.duration = d;
    // Keep the phase so a new reading doesn't restart the beat.
    _a.repeat();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _beating ? widget.color : widget.color.withValues(alpha: .35);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size * 1.3,
        child: Center(
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, child) => Transform.scale(
              scale: _scale.transform(_a.value),
              child: child,
            ),
            child: TempoIcon(
              TempoIcons.heart,
              size: widget.size,
              color: color,
              fill: true,
              stroke: 0,
            ),
          ),
        ),
      ),
    );
  }
}
