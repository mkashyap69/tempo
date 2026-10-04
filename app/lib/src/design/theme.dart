import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

ThemeData tempoTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? TempoColors.darkTheme : TempoColors.lightTheme;
  final s = dark ? TempoScales.darkTheme : TempoScales.lightTheme;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.text1,
    onPrimary: c.textInverse,
    secondary: c.surface3,
    onSecondary: c.text1,
    error: s.recLow,
    onError: c.textInverse,
    surface: c.bg,
    onSurface: c.text1,
  );
  TextStyle t(TextStyle x) => x.copyWith(color: c.text1);
  return ThemeData(
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    fontFamily: TempoType.family,
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: TextTheme(
      displayLarge: t(TempoType.hero),
      displayMedium: t(TempoType.scoreL),
      displaySmall: t(TempoType.scoreM),
      headlineSmall: t(TempoType.scoreS),
      titleLarge: t(TempoType.titleL),
      titleMedium: t(TempoType.titleM),
      bodyLarge: t(TempoType.body),
      bodyMedium: t(TempoType.bodyS),
      labelLarge: t(TempoType.label),
      labelSmall: t(TempoType.overline),
      bodySmall: t(TempoType.caption),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.text1,
      selectionColor: c.text3.withValues(alpha: .4),
      selectionHandleColor: c.text1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TempoRadii.lg),
      ),
      titleTextStyle: TempoType.titleM.c(c.text1),
      contentTextStyle: TempoType.body.c(c.text2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.text1,
      linearTrackColor: c.trackOff,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    extensions: [c, s],
  );
}
