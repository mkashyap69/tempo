/// Band configuration writes done during pairing. All TODO(verify).
library;

import 'dart:typed_data';

import 'fetch.dart';

final class UserProfile {
  const UserProfile({
    required this.birthDate,
    required this.heightCm,
    required this.weightKg,
    this.male = true,
    this.userId = 1,
  });
  final DateTime birthDate;
  final int heightCm;
  final double weightKg;
  final bool male;
  final int userId;
}

abstract final class SettingsCommands {
  /// SIG Current Time (0x2A2B) style payload plus tz. TODO(verify)
  static Uint8List currentTime(DateTime now) {
    final l = now.toLocal();
    final t = encodeBandTime(l);
    return Uint8List.fromList([
      ...t.sublist(0, 6),
      l.second,
      l.weekday, // 1 = Monday
      0, // fractions256
      0, // adjust reason
      t[6], // tz quarter hours
    ]);
  }

  /// User info on the 0x0008 char. TODO(verify)
  static Uint8List userInfo(UserProfile p) {
    final w = (p.weightKg * 200).round();
    final b = p.birthDate;
    return Uint8List.fromList([
      0x4f, 0x00, 0x00, // TODO(verify)
      b.year & 0xff, b.year >> 8, b.month, b.day,
      p.male ? 0 : 1,
      p.heightCm & 0xff, p.heightCm >> 8,
      w & 0xff, w >> 8,
      p.userId & 0xff,
      (p.userId >> 8) & 0xff,
      (p.userId >> 16) & 0xff,
      (p.userId >> 24) & 0xff,
    ]);
  }

  /// HR control point: all-day HR measurement interval in minutes. TODO(verify)
  /// The activity log still has one slot per minute; this is how often a
  /// slot is filled. 1 is the finest. Live workout HR is a separate stream.
  static const hrIntervalChoices = [1, 10, 30];

  static Uint8List hrInterval(int minutes) =>
      Uint8List.fromList([0x14, minutes]);

  /// HR control point: HR-assisted sleep detection on. TODO(verify)
  static final sleepAssistOn = Uint8List.fromList([0x15, 0x00, 0x01]);

  /// Config char: all-day stress monitoring on. TODO(verify)
  static final stressMonitoringOn = Uint8List.fromList([
    0xfe,
    0x06,
    0x00,
    0x01,
  ]);
}
