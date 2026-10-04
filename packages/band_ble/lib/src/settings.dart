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

  /// HR control point: HR-assisted sleep detection on/off. TODO(verify)
  static final sleepAssistOn = Uint8List.fromList([0x15, 0x00, 0x01]);
  static final sleepAssistOff = Uint8List.fromList([0x15, 0x00, 0x00]);

  static Uint8List sleepAssist(bool on) => on ? sleepAssistOn : sleepAssistOff;

  /// Config char: all-day stress monitoring on/off. TODO(verify)
  static final stressMonitoringOn = Uint8List.fromList([
    0xfe,
    0x06,
    0x00,
    0x01,
  ]);
  static final stressMonitoringOff = Uint8List.fromList([
    0xfe,
    0x06,
    0x00,
    0x00,
  ]);

  static Uint8List stressMonitoring(bool on) =>
      on ? stressMonitoringOn : stressMonitoringOff;

  /// User settings char: which wrist the band is on. The band uses it for
  /// raise-to-wake and step detection. TODO(verify)
  static Uint8List wearLocation({required bool left}) =>
      Uint8List.fromList([0x20, 0x00, 0x00, left ? 0x02 : 0x82]);

  /// Config char: one band alarm. TODO(verify) every byte.
  /// [slot] 0–9. [days] bit 0 = Monday … bit 6 = Sunday; 0 = once.
  /// [smart] lets the band wake you up to 30 minutes early in light sleep.
  static Uint8List alarm(BandAlarm a) => Uint8List.fromList([
    0x02,
    (a.enabled ? 0x80 : 0) | (a.smart ? 0 : 0x40) | (a.slot & 0x0f),
    a.hour,
    a.minute,
    a.days & 0x7f,
  ]);
}

final class BandAlarm {
  const BandAlarm({
    required this.hour,
    required this.minute,
    this.slot = 0,
    this.smart = true,
    this.enabled = true,
    this.days = 0,
  }) : assert(slot >= 0 && slot < 10);
  final int slot, hour, minute, days;
  final bool smart, enabled;
}
