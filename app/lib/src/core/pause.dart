import 'dart:convert';

import 'package:store/store.dart';

import 'profile.dart' show Keys;

enum PauseReason { ill, travel }

String pauseLabel(PauseReason r) => switch (r) {
  PauseReason.ill => 'Ill',
  PauseReason.travel => 'Travelling',
};

/// A stretch when the body isn't itself (illness, travel). Those days are
/// still scored and shown, but they don't feed baselines or calibration,
/// and the coach stops adapting the plan.
final class Pause {
  const Pause(this.from, this.reason, {this.to});
  final DateTime from;

  /// Last paused day; null while the pause is on.
  final DateTime? to;
  final PauseReason reason;

  bool get active => to == null;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final f = DateTime(from.year, from.month, from.day);
    if (d.isBefore(f)) return false;
    final t = to;
    return t == null || !d.isAfter(DateTime(t.year, t.month, t.day));
  }

  List<Object?> toJson() => [
    dateKey(from),
    to == null ? null : dateKey(to!),
    reason.name,
  ];

  static Pause fromJson(List<dynamic> j) => Pause(
    DateTime.parse(j[0] as String),
    PauseReason.values.asNameMap()[j[2]] ?? PauseReason.ill,
    to: j[1] == null ? null : DateTime.parse(j[1] as String),
  );
}

Future<List<Pause>> loadPauses(TempoDb db) async {
  final raw = await db.setting(Keys.pauses);
  if (raw == null || raw.isEmpty) return [];
  try {
    return [for (final e in jsonDecode(raw) as List) Pause.fromJson(e as List)];
  } catch (_) {
    return [];
  }
}

Future<void> _save(TempoDb db, List<Pause> ps) =>
    db.putSetting(Keys.pauses, jsonEncode([for (final p in ps) p.toJson()]));

Pause? activePause(List<Pause> ps) => ps.where((p) => p.active).firstOrNull;

bool isPaused(List<Pause> ps, DateTime day) => ps.any((p) => p.covers(day));

/// Starts a pause today (ends any open one first).
Future<void> startPause(TempoDb db, PauseReason r, {DateTime? on}) async {
  final day = on ?? DateTime.now();
  final ps = await loadPauses(db);
  final ended = [
    for (final p in ps)
      p.active
          ? Pause(p.from, p.reason, to: day.subtract(const Duration(days: 1)))
          : p,
  ].where((p) => !p.to!.isBefore(p.from)).toList();
  await _save(db, [...ended, Pause(day, r)]);
}

/// Ends the open pause; today is the first normal day again. A pause
/// started today is simply removed.
Future<void> endPause(TempoDb db, {DateTime? on}) async {
  final day = on ?? DateTime.now();
  final today = DateTime(day.year, day.month, day.day);
  final ps = await loadPauses(db);
  await _save(db, [
    for (final p in ps)
      if (!p.active)
        p
      else if (DateTime(p.from.year, p.from.month, p.from.day).isBefore(today))
        Pause(p.from, p.reason, to: today.subtract(const Duration(days: 1))),
  ]);
}
