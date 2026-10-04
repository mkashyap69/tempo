import 'package:flutter/material.dart';

/// Type scale (TempoType → TextTheme). One family, Geist. Scores use the
/// light weight with tabular figures so they don't jitter while counting.
abstract final class TempoType {
  static const family = 'Geist';
  static const mono = 'GeistMono';
  static const _tnum = [FontFeature.tabularFigures()];

  static TextStyle _t(
    double size,
    double line,
    FontWeight w,
    double em, {
    bool tnum = false,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: line / size,
    fontWeight: w,
    letterSpacing: em * size,
    fontFeatures: tnum ? _tnum : null,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static final hero = _t(88, 84, FontWeight.w300, -0.045, tnum: true);
  static final scoreL = _t(56, 56, FontWeight.w300, -0.04, tnum: true);
  static final scoreM = _t(40, 40, FontWeight.w300, -0.035, tnum: true);
  static final scoreS = _t(26, 30, FontWeight.w400, -0.02, tnum: true);
  static final titleL = _t(24, 30, FontWeight.w500, -0.02);
  static final titleM = _t(18, 24, FontWeight.w500, -0.01);
  static final body = _t(15, 22, FontWeight.w400, 0);
  static final bodyS = _t(13, 18, FontWeight.w400, 0);
  static final label = _t(13, 16, FontWeight.w500, 0);

  /// Pass upper-case text; Flutter has no text-transform.
  static final overline = _t(11, 14, FontWeight.w600, 0.09);
  static final caption = _t(12, 16, FontWeight.w400, 0);

  /// Page titles on tab screens (28/34).
  static final pageTitle = _t(28, 34, FontWeight.w500, -0.02);

  static final monoS = const TextStyle(
    fontFamily: mono,
    fontSize: 14,
    letterSpacing: 0.28,
  );
}

extension TabularNums on TextStyle {
  TextStyle get tnum =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  TextStyle c(Color color) => copyWith(color: color);
  TextStyle get w500 => copyWith(fontWeight: FontWeight.w500);
}
