import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/band_link.dart' show deviceIdKey, deviceNameKey;
import 'package:tempo/src/core/coach_service.dart';
import 'package:tempo/src/core/profile.dart';
import 'package:tempo/src/core/score_service.dart';

/// Loads Geist so rendered text matches the design.
Future<void> loadFonts() async {
  for (final (family, files) in [
    (
      'Geist',
      ['Geist-Light', 'Geist-Regular', 'Geist-Medium', 'Geist-SemiBold'],
    ),
    ('GeistMono', ['GeistMono-Regular', 'GeistMono-Medium']),
  ]) {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(rootBundle.load('assets/fonts/$f.ttf'));
    }
    await l.load();
  }
}

/// An in-memory DB with [days] days of plausible band data ending now:
/// nights 23:00–06:45 with stage cycles, a morning walk, rides and runs,
/// overnight stress, SpO₂ spot readings and journal tags.
Future<TempoDb> seededDb({
  int days = 40,
  bool paired = true,
  DateTime? now,
}) async {
  final db = TempoDb(NativeDatabase.memory());
  final r = Random(7);
  final end = now ?? DateTime.now();
  final today = dayOf(end);
  final minutes = <MinuteSamplesCompanion>[];
  final stress = <StressSamplesCompanion>[];
  final spo2 = <Spo2SamplesCompanion>[];
  void add(DateTime t, {required int kind, int? hr, int steps = 0}) {
    if (t.isAfter(end)) return;
    minutes.add(
      MinuteSamplesCompanion.insert(
        ts: Value(toTs(t)),
        steps: steps,
        intensity: steps > 0 ? 60 : 5,
        kind: kind,
        hr: Value(hr),
      ),
    );
  }

  for (var d = days; d >= 0; d--) {
    final day = today.subtract(Duration(days: d));
    final eve = day.subtract(const Duration(days: 1));
    final bed = DateTime(eve.year, eve.month, eve.day, 23, r.nextInt(30));
    final sleepMin = 400 + r.nextInt(70) - (d % 9 == 3 ? 90 : 0);
    final rest = 48 + r.nextInt(6) + (d % 9 == 3 ? 6 : 0);
    // Stage cycle: light → deep → light → REM, ~90 min.
    for (var m = 0; m < sleepMin; m++) {
      final c = m % 90;
      final kind = m > 30 && r.nextInt(120) == 0
          ? 0x01
          : c < 20
          ? 0x70
          : c < 45 && m < 300
          ? 0x7b
          : c < 70
          ? 0x70
          : 0x6e;
      add(
        bed.add(Duration(minutes: m)),
        kind: kind,
        hr:
            rest +
            (kind == 0x6e
                ? 6
                : kind == 0x7b
                ? -2
                : 2) +
            r.nextInt(3),
      );
      if (m % 5 == 0) {
        stress.add(
          StressSamplesCompanion.insert(
            ts: Value(toTs(bed.add(Duration(minutes: m)))),
            value: 26 + r.nextInt(14) + (d % 9 == 3 ? 14 : 0),
          ),
        );
      }
      if (m % 50 == 7) {
        spo2.add(
          Spo2SamplesCompanion.insert(
            ts: Value(toTs(bed.add(Duration(minutes: m)))),
            value: 95 + r.nextInt(3),
          ),
        );
      }
    }
    final wake = bed.add(Duration(minutes: sleepMin));
    final dayEnd = DateTime(day.year, day.month, day.day, 23);
    for (
      var t = wake;
      t.isBefore(dayEnd);
      t = t.add(const Duration(minutes: 1))
    ) {
      final h = t.hour * 60 + t.minute;
      int hr = 68 + r.nextInt(10),
          steps = r.nextInt(4) == 0 ? r.nextInt(40) : 0;
      if (h >= 485 && h < 528) {
        hr = 100 + r.nextInt(10);
        steps = 105 + r.nextInt(10);
      } else if (d % 3 == 1 && h >= 680 && h < 715) {
        hr = 130 + r.nextInt(14);
        steps = 0;
      } else if (d % 4 == 2 && h >= 1020 && h < 1063) {
        final rep = (h - 1030) % 5;
        hr = h >= 1030 && h < 1055 && rep < 3
            ? 152 + r.nextInt(10)
            : 120 + r.nextInt(10);
        steps = 160;
      }
      add(t, kind: 0x01, hr: hr, steps: steps);
      if (h % 10 == 0) {
        stress.add(
          StressSamplesCompanion.insert(
            ts: Value(toTs(t)),
            value: 30 + r.nextInt(30),
          ),
        );
      }
    }
    if (d > 0 && d < 36) {
      await db.setJournal(eve, 'alcohol', d % 6 == 4);
      await db.setJournal(eve, 'late_meal', d % 5 == 2);
      await db.setJournal(eve, 'caffeine_late', d % 7 == 1);
      await db.setJournal(eve, 'stressful_day', d % 9 == 4);
      await db.setJournal(eve, 'travel', false);
    }
  }
  await db.appendMinutes(minutes);
  await db.appendStress(stress);
  await db.appendSpo2(spo2);
  await saveAppProfile(db, const Profile());
  await db.putSetting(Keys.onboarded, '1');
  if (paired) {
    await db.putSetting(deviceIdKey, 'FD:BE:07:41:71:2B');
    await db.putSetting(deviceNameKey, 'Mi Smart Band 6');
    await db.putSetting(Keys.firmware, 'V1.0.6.20');
    await db.putSetting(Keys.battery, '64');
    await db.putSetting(
      Keys.lastSync,
      end.subtract(const Duration(minutes: 6)).toIso8601String(),
    );
    await db.logSync(
      'Night + 6h 42m of data · 1 activity',
      'ok',
      took: const Duration(seconds: 22),
      at: end.subtract(const Duration(minutes: 6)),
    );
  }
  await ScoreService(db).recomputeFrom(today.subtract(Duration(days: days)));
  await CoachService(db).ensureWeek(today);
  return db;
}

/// Paired and onboarded, with a few hours of today's daytime data but no
/// night yet (the "first day" state).
Future<TempoDb> emptyPaired() async {
  final db = TempoDb(NativeDatabase.memory());
  final now = DateTime.now();
  final from = now.subtract(const Duration(hours: 3));
  await db.appendMinutes([
    for (var t = from; t.isBefore(now); t = t.add(const Duration(minutes: 1)))
      MinuteSamplesCompanion.insert(
        ts: Value(toTs(t)),
        steps: 10,
        intensity: 5,
        kind: 0x01,
        hr: const Value(72),
      ),
  ]);
  await saveAppProfile(db, const Profile());
  await db.putSetting(Keys.onboarded, '1');
  await db.putSetting(deviceIdKey, 'FD:BE:07:41:71:2B');
  await db.putSetting(Keys.lastSync, now.toIso8601String());
  await ScoreService(db).recomputeFrom(dayOf(now));
  return db;
}
