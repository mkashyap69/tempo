// Tempo design tokens — one source of truth, mirrored from the design canvas
// (tempo-tokens.css). Token `--rec-high` → `TempoScales.recHigh`.
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Neutrals. Do all the work; hue only appears on [TempoScales].
@immutable
class TempoColors extends ThemeExtension<TempoColors> {
  const TempoColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.trackOff,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.textInverse,
    required this.scrim,
    required this.shadowSheet,
    required this.shadowFloat,
    required this.dark,
  });

  final Color bg, surface1, surface2, surface3, line, lineStrong, trackOff;
  final Color text1, text2, text3, textInverse, scrim;
  final List<BoxShadow> shadowSheet, shadowFloat;
  final bool dark;

  static const darkTheme = TempoColors(
    bg: Color(0xFF0A0B0D),
    surface1: Color(0xFF121417),
    surface2: Color(0xFF1A1D21),
    surface3: Color(0xFF24282E),
    line: Color(0xFF23272D),
    lineStrong: Color(0xFF353A42),
    trackOff: Color(0xFF2A2E35),
    text1: Color(0xFFF3F2EF),
    text2: Color(0xFFA9ADB4),
    text3: Color(0xFF858A92),
    textInverse: Color(0xFF0A0B0D),
    scrim: Color(0x9E000000),
    shadowSheet: [
      BoxShadow(
        color: Color(0x8C000000),
        offset: Offset(0, -12),
        blurRadius: 40,
      ),
    ],
    shadowFloat: [
      BoxShadow(
        color: Color(0x80000000),
        offset: Offset(0, 10),
        blurRadius: 30,
      ),
    ],
    dark: true,
  );

  static const lightTheme = TempoColors(
    bg: Color(0xFFF6F5F2),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFEEEA),
    surface3: Color(0xFFE4E2DD),
    line: Color(0xFFE3E1DC),
    lineStrong: Color(0xFFCFCCC5),
    trackOff: Color(0xFFDEDBD5),
    text1: Color(0xFF121316),
    text2: Color(0xFF575B62),
    text3: Color(0xFF6B6F76),
    textInverse: Color(0xFFFFFFFF),
    scrim: Color(0x61121316),
    shadowSheet: [
      BoxShadow(
        color: Color(0x24121316),
        offset: Offset(0, -10),
        blurRadius: 36,
      ),
    ],
    shadowFloat: [
      BoxShadow(color: Color(0x29121316), offset: Offset(0, 8), blurRadius: 24),
    ],
    dark: false,
  );

  @override
  TempoColors copyWith() => this;

  @override
  TempoColors lerp(TempoColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return TempoColors(
      bg: c(bg, other.bg),
      surface1: c(surface1, other.surface1),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      line: c(line, other.line),
      lineStrong: c(lineStrong, other.lineStrong),
      trackOff: c(trackOff, other.trackOff),
      text1: c(text1, other.text1),
      text2: c(text2, other.text2),
      text3: c(text3, other.text3),
      textInverse: c(textInverse, other.textInverse),
      scrim: c(scrim, other.scrim),
      shadowSheet: t < 0.5 ? shadowSheet : other.shadowSheet,
      shadowFloat: t < 0.5 ? shadowFloat : other.shadowFloat,
      dark: t < 0.5 ? dark : other.dark,
    );
  }
}

/// The five semantic scales. Lightness does the ordering; every state also
/// carries a glyph or label.
@immutable
class TempoScales extends ThemeExtension<TempoScales> {
  const TempoScales({
    required this.recHigh,
    required this.recMid,
    required this.recLow,
    required this.strain,
    required this.zone,
    required this.loadDetraining,
    required this.loadMaintaining,
    required this.loadBuilding,
    required this.loadOverreaching,
    required this.sleepAwake,
    required this.sleepRem,
    required this.sleepLight,
    required this.sleepDeep,
    required this.sleepChannel,
    required this.tintRecHigh,
    required this.tintRecMid,
    required this.tintRecLow,
    required this.tintStrain,
    required this.tintSleep,
  });

  final Color recHigh, recMid, recLow;

  /// strain-1..4 (Light, Moderate, High, All-out).
  final List<Color> strain;

  /// zone-1..5.
  final List<Color> zone;
  final Color loadDetraining, loadMaintaining, loadBuilding, loadOverreaching;
  final Color sleepAwake, sleepRem, sleepLight, sleepDeep, sleepChannel;
  final Color tintRecHigh, tintRecMid, tintRecLow, tintStrain, tintSleep;

  static const darkTheme = TempoScales(
    recHigh: Color(0xFF3CCBC0),
    recMid: Color(0xFFF0C24B),
    recLow: Color(0xFFEE4F6C),
    strain: [
      Color(0xFFFFD9A8),
      Color(0xFFFFB066),
      Color(0xFFFF8A3D),
      Color(0xFFE8602C),
    ],
    zone: [
      Color(0xFF5D636D),
      Color(0xFFFFE0B3),
      Color(0xFFFFBE76),
      Color(0xFFFF9446),
      Color(0xFFEE6A2C),
    ],
    loadDetraining: Color(0xFF6E7686),
    loadMaintaining: Color(0xFFC9CED8),
    loadBuilding: Color(0xFF5DA1FF),
    loadOverreaching: Color(0xFFFF8C5A),
    sleepAwake: Color(0xFFEDE3CF),
    sleepRem: Color(0xFFEBA6E6),
    sleepLight: Color(0xFF7E8CF4),
    sleepDeep: Color(0xFF5357D4),
    sleepChannel: Color(0xFF9AA4FF),
    tintRecHigh: Color(0x1F3CCBC0),
    tintRecMid: Color(0x1FF0C24B),
    tintRecLow: Color(0x21EE4F6C),
    tintStrain: Color(0x1FFFB066),
    tintSleep: Color(0x1F9AA4FF),
  );

  static const lightTheme = TempoScales(
    recHigh: Color(0xFF0B958C),
    recMid: Color(0xFFA87A00),
    recLow: Color(0xFFCC3150),
    strain: [
      Color(0xFFF0B470),
      Color(0xFFE8913F),
      Color(0xFFD86A22),
      Color(0xFFB24D17),
    ],
    zone: [
      Color(0xFFA3A8B0),
      Color(0xFFF2C48A),
      Color(0xFFEE9C54),
      Color(0xFFD86A22),
      Color(0xFFB24D17),
    ],
    loadDetraining: Color(0xFF6B7384),
    loadMaintaining: Color(0xFF7C8798),
    loadBuilding: Color(0xFF2F7BE0),
    loadOverreaching: Color(0xFFE0622A),
    sleepAwake: Color(0xFFB8A274),
    sleepRem: Color(0xFFB4529F),
    sleepLight: Color(0xFF5868E0),
    sleepDeep: Color(0xFF2E2FA3),
    sleepChannel: Color(0xFF5B57E6),
    tintRecHigh: Color(0x1A0B958C),
    tintRecMid: Color(0x1AA87A00),
    tintRecLow: Color(0x1ACC3150),
    tintStrain: Color(0x1AD86A22),
    tintSleep: Color(0x1A5B57E6),
  );

  /// Strain colour for a value on 0–21 (tick colour follows its band).
  Color strainFor(double s) => s < 9
      ? strain[0]
      : s < 13
      ? strain[1]
      : s < 17
      ? strain[2]
      : strain[3];

  /// Recovery state colour: ≥ 67 high, ≥ 34 mid, else low.
  Color recoveryFor(double r) => r >= 67
      ? recHigh
      : r >= 34
      ? recMid
      : recLow;

  Color zoneColor(int z) => zone[(z.clamp(1, 5)) - 1];

  @override
  TempoScales copyWith() => this;

  @override
  TempoScales lerp(TempoScales? o, double t) {
    if (o == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) c(a[i], b[i]),
    ];
    return TempoScales(
      recHigh: c(recHigh, o.recHigh),
      recMid: c(recMid, o.recMid),
      recLow: c(recLow, o.recLow),
      strain: l(strain, o.strain),
      zone: l(zone, o.zone),
      loadDetraining: c(loadDetraining, o.loadDetraining),
      loadMaintaining: c(loadMaintaining, o.loadMaintaining),
      loadBuilding: c(loadBuilding, o.loadBuilding),
      loadOverreaching: c(loadOverreaching, o.loadOverreaching),
      sleepAwake: c(sleepAwake, o.sleepAwake),
      sleepRem: c(sleepRem, o.sleepRem),
      sleepLight: c(sleepLight, o.sleepLight),
      sleepDeep: c(sleepDeep, o.sleepDeep),
      sleepChannel: c(sleepChannel, o.sleepChannel),
      tintRecHigh: c(tintRecHigh, o.tintRecHigh),
      tintRecMid: c(tintRecMid, o.tintRecMid),
      tintRecLow: c(tintRecLow, o.tintRecLow),
      tintStrain: c(tintStrain, o.tintStrain),
      tintSleep: c(tintSleep, o.tintSleep),
    );
  }
}

/// 4-pt grid. Screen gutter s5 · card padding s4 · between cards 10.
abstract final class TempoSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0;
  static const s8 = 32.0, s10 = 40.0, s12 = 48.0, s16 = 64.0;
  static const gutter = s5;
  static const cardGap = 10.0;
}

abstract final class TempoRadii {
  static const xs = 6.0,
      sm = 10.0,
      md = 14.0,
      lg = 20.0,
      xl = 28.0,
      pill = 999.0;
}

abstract final class TempoMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const count = Duration(milliseconds: 900);
  static const draw = Duration(milliseconds: 1200);
  static const tickStagger = Duration(milliseconds: 18);
  static const easeOut = Cubic(.22, 1, .36, 1);
  static const easeInOut = Cubic(.65, 0, .35, 1);
  static const outQuart = Cubic(.25, 1, .5, 1);
  static const splashBeat = Duration(milliseconds: 600);
}

/// Shorthand: `context.c.text2`, `context.s.recHigh`.
extension TempoContext on BuildContext {
  TempoColors get c => Theme.of(this).extension<TempoColors>()!;
  TempoScales get s => Theme.of(this).extension<TempoScales>()!;

  /// Reduce Motion: count-ups and fills jump to the final value.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

double lerpD(double a, double b, double t) => lerpDouble(a, b, t)!;
