import 'package:flutter/material.dart';

/// Screenshot palette: cream canvas, white cards, orange accent.
const canvas = Color(0xFFF4F4F6);
const ink = Color(0xFF111113);
const muted = Color(0xFF8E8E93);
const accent = Color(0xFFFF5A1F);
const cardRadius = 24.0;

ThemeData tempoTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
    surface: canvas,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
    ),
  ),
);
