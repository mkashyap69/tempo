import 'package:flutter/material.dart';
import 'package:scoring/scoring.dart';

String hm(double? hours) {
  if (hours == null) return '–';
  final m = (hours * 60).round();
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

String n0(double? v) => v == null ? '–' : v.toStringAsFixed(0);
String n1(double? v) => v == null ? '–' : v.toStringAsFixed(1);

String clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String shortDate(DateTime d) => '${d.day}/${d.month}';

Color recoveryColour(double? score) =>
    switch (score == null ? null : recoveryColor(score)) {
      RecoveryColor.green => const Color(0xFF16A34A),
      RecoveryColor.yellow => const Color(0xFFEAB308),
      RecoveryColor.red => const Color(0xFFDC2626),
      null => Colors.grey,
    };

const strainColour = Color(0xFF2563EB);
const sleepColour = Color(0xFF7C3AED);

/// HR zones by % of heart-rate reserve.
const zoneBounds = [0.5, 0.6, 0.7, 0.8, 0.9];
const zoneColours = [
  Color(0xFF94A3B8),
  Color(0xFF60A5FA),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFFF97316),
  Color(0xFFEF4444),
];

/// 0 = below zone 1, 1..5 = zones.
int zoneFor(int hr, double rest, double max) {
  final r = max <= rest ? 0 : (hr - rest) / (max - rest);
  var z = 0;
  for (final b in zoneBounds) {
    if (r >= b) z++;
  }
  return z;
}
