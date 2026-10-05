import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart';
import 'longevity_service.dart';
import 'notifications.dart';
import 'pause.dart';
import 'profile.dart';
import 'score_service.dart';
import 'today.dart';

/// Tempo Coach notifications: works out the next 48 hours from today's
/// plan and data ([sc.planNudges]), replaces whatever was pending, and
/// logs every decision and answer to `nudge_log`.
///
/// Runs on app open and resume, after every sync, and after every button
/// press, so the pending set is always rebuilt from the latest state.
class CoachNotifier {
  CoachNotifier(this.db, {NotificationSink? sink})
    : sink = sink ?? notificationSink;
  final st.TempoDb db;
  final NotificationSink sink;

  /// Which kinds are on (Settings → Notifications).
  static Future<Set<sc.NudgeKind>> kinds(st.TempoDb db) async {
    final out = {...sc.defaultKinds};
    try {
      final raw = await db.setting(Keys.notifCats);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in m.entries) {
          final k = sc.NudgeKind.values.asNameMap()[e.key];
          if (k == null) continue;
          e.value == 1 ? out.add(k) : out.remove(k);
        }
      }
    } catch (_) {}
    // The two older settings still switch their kinds off.
    if (await db.setting(Keys.morningCall) == 'off') {
      out.remove(sc.NudgeKind.brief);
    }
    if (await db.setting(Keys.bedtimeNudge) == 'off') {
      out.remove(sc.NudgeKind.winddown);
    }
    return out;
  }

  static Future<void> setKind(st.TempoDb db, sc.NudgeKind k, bool on) async {
    Map<String, dynamic> m = {};
    try {
      m = jsonDecode(
        await db.setting(Keys.notifCats) ?? '{}',
      ) as Map<String, dynamic>;
    } catch (_) {}
    m[k.name] = on ? 1 : 0;
    await db.putSetting(Keys.notifCats, jsonEncode(m));
  }

  Future<List<sc.NudgeSpec>> refresh({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final t = await loadToday(db, at: at);
    final ctx = await context(t, at);
    final specs = sc.planNudges(ctx);
    await _replace(specs, at);
    return specs;
  }

  /// Everything [sc.planNudges] needs, from the DB.
  Future<sc.NudgeContext> context(TodayData t, DateTime now) async {
    final day = dayOf(now);
    final tomorrow = day.add(const Duration(days: 1));
    final coach = CoachService(db);
    final week = await coach.ensureWeek(tomorrow);
    final tRow = week.where((r) => r.date == st.dateKey(tomorrow)).firstOrNull;
    final slots = await loadSlots(db);
    sc.NudgeDay? tomorrowDay;
    if (tRow != null) {
      final s = sc.Session.fromJson(
        jsonDecode(tRow.session) as Map<String, dynamic>,
      );
      tomorrowDay = sc.NudgeDay(
        title: s.title,
        minutes: s.minutes,
        rest: s.isRest,
        hard: s.isHard,
        plannedMinute: s.isRest
            ? null
            : tRow.plannedMinute ?? slots.minuteFor(s),
      );
    }
    final plan = t.plan ?? sc.sessionTemplate('rest');
    final todayDay = sc.NudgeDay(
      title: plan.title,
      minutes: plan.minutes,
      rest: plan.isRest,
      hard: plan.isHard,
      plannedMinute: t.plannedMinute,
      status: t.status,
    );
    final log = await db.nudgesSince(now.subtract(const Duration(days: 14)));
    final morning = await db.setting(Keys.morningCall) ?? '07:00';
    final nudge = await db.setting(Keys.bedtimeNudge) ?? '45';
    final cap = int.tryParse(await db.setting(Keys.notifCap) ?? '') ?? 1;
    final paused = isPaused(await loadPauses(db), day);

    // Steps so far against the focus lever's target.
    final focus = await loadFocus(db);
    String? leverLine;
    var behind = false;
    if (focus != null && focus.lever == sc.Lever.steps && focus.activeOn(day)) {
      final steps = await db.stepsBetween(day, now);
      final target = sc.leverTarget(
        sc.Lever.steps,
        age: t.profile.age,
        male: t.profile.male,
      );
      final a = sc
          .leverActions(
            focus: sc.Lever.steps,
            nowMinute: 15 * 60,
            wakeMinute: t.wakeMinute,
            bedtime: t.bedtimeMinute,
            stepsToday: steps,
            stepTarget: target,
          )
          .first;
      behind = !a.done && a.detail.contains('walk');
      leverLine = '${_k(steps)} steps so far';
    }

    // A detected workout from the last 6 h with no rating yet.
    (int, String)? rpe;
    final recent = await db.workoutsBetween(
      now.subtract(const Duration(hours: 6)),
      now,
    );
    final asked = {
      for (final r in log)
        if (r.kind == sc.NudgeKind.rpe.name) _payload(r)['workout'],
    };
    for (final w in recent.reversed) {
      if (w.source == 'live' || w.rpe != null) continue;
      if (st.fromTs(w.end).isAfter(now)) continue;
      if (asked.contains(w.start)) continue;
      rpe = (w.start, w.title);
      break;
    }

    return sc.NudgeContext(
      now: now,
      wake: t.wakeMinute,
      bedtime: t.bedtimeMinute,
      today: todayDay,
      tomorrow: tomorrowDay,
      morning: morning == 'off' ? null : parseHm(morning),
      winddownBefore: int.tryParse(nudge),
      pmSlot: t.pmSlot,
      rescue: t.rescue,
      briefLine: _brief(t),
      leverLine: leverLine,
      stepsBehind: behind,
      syncAgeMinutes: t.syncAge?.inMinutes,
      paused: paused,
      kinds: await kinds(db),
      cap: cap.clamp(0, 2),
      ignoreStreak: ignoreStreaksFrom(log),
      sentLast7: log
          .where(
            (r) =>
                r.event == 'posted' &&
                r.ts >= st.toTs(now.subtract(const Duration(days: 7))) &&
                sc.proactiveKinds.any((k) => k.name == r.kind),
          )
          .length,
      rpeWorkout: rpe,
      illness: t.rhrFlag == sc.RhrFlag.illness,
      healthSentToday: log.any(
        (r) =>
            r.kind == sc.NudgeKind.health.name &&
            r.day == st.dateKey(day) &&
            (r.event == 'posted' || r.event == 'action'),
      ),
    );
  }

  static String? _brief(TodayData t) {
    if (t.calibrating) {
      return 'Still learning your baseline · in by ${fmtHm(t.bedtimeMinute)}';
    }
    final r = t.recovery;
    if (r == null) return null;
    final why = switch (t.rhrFlag) {
      sc.RhrFlag.illness => ' · night HR high',
      sc.RhrFlag.elevated => ' · resting HR up',
      _ => t.shortNight ? ' · short night' : '',
    };
    return 'Recovery ${r.round()}%$why · in by ${fmtHm(t.bedtimeMinute)}';
  }

  /// Cancels what was pending and schedules [specs]. What fired since the
  /// last run is logged as posted; changes are logged once.
  Future<void> _replace(List<sc.NudgeSpec> specs, DateTime now) async {
    if (await db.setting(Keys.notifV2) != '1') {
      try {
        await sink.cancelLegacy();
      } catch (e) {
        debugPrint('legacy notifications: $e');
      }
      await db.putSetting(Keys.notifV2, '1');
    }
    final old = <Map<String, dynamic>>[];
    try {
      old.addAll(
        (jsonDecode(await db.setting(Keys.notifScheduled) ?? '[]') as List)
            .cast<Map<String, dynamic>>(),
      );
    } catch (_) {}
    final fresh = {for (final s in specs) s.id: s};
    for (final o in old) {
      final fire = DateTime.fromMillisecondsSinceEpoch(o['fireAt'] as int);
      final id = o['id'] as int;
      if (!fire.isAfter(now)) {
        await _log(o['kind'] as String, id, fire, 'posted', ts: fire);
      } else {
        await sink.cancel(id);
        final n = fresh[id];
        if (n == null || n.fireAt != fire) {
          await _log(o['kind'] as String, id, fire, 'cancelled');
        }
      }
    }
    final precise = await db.setting(Keys.notifPrecise) == '1';
    final kept = {
      for (final o in old)
        if (DateTime.fromMillisecondsSinceEpoch(o['fireAt'] as int)
            .isAfter(now))
          o['id'] as int: o['fireAt'] as int,
    };
    for (final n in specs) {
      try {
        await sink.schedule(n, precise: precise);
      } catch (e) {
        debugPrint('schedule ${n.kind.name}: $e');
        continue;
      }
      if (kept[n.id] != n.fireAt.millisecondsSinceEpoch) {
        await _log(
          n.kind.name,
          n.id,
          n.fireAt,
          'scheduled',
          payload: n.payload,
        );
      }
    }
    await db.putSetting(
      Keys.notifScheduled,
      jsonEncode([
        for (final n in specs)
          {
            'id': n.id,
            'kind': n.kind.name,
            'fireAt': n.fireAt.millisecondsSinceEpoch,
          },
      ]),
    );
  }

  Future<void> _log(
    String kind,
    int id,
    DateTime? fireAt,
    String event, {
    DateTime? ts,
    String? action,
    Map<String, Object?> payload = const {},
  }) => db.logNudge(
    st.NudgeLogCompanion.insert(
      ts: st.toTs(ts ?? DateTime.now()),
      day: st.dateKey(fireAt ?? DateTime.now()),
      kind: kind,
      notifId: id,
      fireAt: Value(fireAt == null ? null : st.toTs(fireAt)),
      event: event,
      action: Value(action),
      payload: Value(jsonEncode(payload)),
      algoVersion: sc.nudgeAlgo,
    ),
  );

  Future<void> logResponse(
    String kind,
    int id,
    DateTime? fireAt,
    String? action,
    Map<String, Object?> payload,
  ) => _log(
    kind,
    id,
    fireAt,
    action == null ? 'tapped' : 'action',
    action: action,
    payload: payload,
  );
}

Map<String, dynamic> _payload(st.NudgeLogData r) {
  try {
    return jsonDecode(r.payload) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

/// Consecutive ignored notifications per kind: a posted one counts as
/// answered if a tap or button for that kind came within 2 hours.
Map<sc.NudgeKind, int> ignoreStreaksFrom(List<st.NudgeLogData> log) {
  final responses = [
    for (final r in log)
      if (r.event == 'tapped' || r.event == 'action') r,
  ];
  final posted = [
    for (final r in log.reversed)
      if (r.event == 'posted') r,
  ];
  return sc.ignoreStreaks([
    for (final p in posted)
      if (sc.NudgeKind.values.asNameMap()[p.kind] case final k?)
        (
          k,
          st.fromTs(p.fireAt ?? p.ts),
          responses.any(
            (r) =>
                r.kind == p.kind &&
                r.ts >= (p.fireAt ?? p.ts) &&
                r.ts <= (p.fireAt ?? p.ts) + 2 * 3600,
          ),
        ),
  ]);
}

String _k(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';

/// Applies a notification answer: changes today's plan, rates a workout,
/// or pauses, then rebuilds the schedule. Shared by the running app and
/// the background handler.
Future<void> handleNudgeResponse(
  st.TempoDb db,
  String? payload,
  String? actionId, {
  NotificationSink? sink,
}) async {
  Map<String, dynamic> p = {};
  try {
    p = jsonDecode(payload ?? '{}') as Map<String, dynamic>;
  } catch (_) {}
  final kind = p['kind'] as String? ?? 'unknown';
  final fire = p['fireAt'] is int
      ? DateTime.fromMillisecondsSinceEpoch(p['fireAt'] as int)
      : null;
  final notifier = CoachNotifier(db, sink: sink);
  await notifier.logResponse(kind, (p['id'] as int?) ?? 0, fire, actionId, p);
  final coach = CoachService(db);
  final today = dayOf(DateTime.now());
  final now = DateTime.now();
  final nowMin = now.hour * 60 + now.minute;
  switch (actionId) {
    case 'easier':
      final t = await loadToday(db);
      if (t.plan != null && !t.plan!.isRest) {
        await coach.swapToday(
          sc.sessionTemplate(sc.easierKeyFor(t.plan!)),
          'Swapped easier from the morning brief',
        );
      }
    case 'rest':
      await coach.swapToday(
        sc.sessionTemplate('rest'),
        'Rest day, from the morning brief',
      );
    case 'later':
      final row = await db.planDay(today);
      final from = row?.plannedMinute ?? nowMin;
      await coach.setIntent(
        today,
        sc.Intent.moved,
        source: 'notification',
        minute: (from < nowMin ? nowMin : from) + 60,
      );
    case 'skip':
      await coach.setIntent(today, sc.Intent.skipped, source: 'notification');
    case 'done':
      await coach.setIntent(today, sc.Intent.done, source: 'notification');
    case 'plan_pm':
      final start = (p['start'] as int?) ?? (await loadSlots(db)).pm;
      final key = p['session'] as String?;
      var s = key == null ? null : sc.sessionTemplate(key);
      final mins = p['minutes'] as int?;
      if (s != null && mins != null) s = sc.fitMinutes(s, mins);
      await coach.setIntent(
        today,
        sc.Intent.moved,
        source: 'notification',
        minute: start,
        slot: 'pm',
        session: s,
      );
    case final String a when a.startsWith('rpe_'):
      final rpe = int.tryParse(a.substring(4));
      final start = p['workout'] as int?;
      if (rpe != null && start != null) {
        final ws = await db.workoutsBetween(
          st.fromTs(start),
          st.fromTs(start + 1),
        );
        if (ws.isNotEmpty) {
          await db.updateWorkout(
            ws.first.id,
            const st.WorkoutsCompanion(confirmed: Value(true)),
          );
          await saveRpe(db, ws.first.id, rpe);
        }
      }
    case 'pause3':
      await startPause(
        db,
        PauseReason.ill,
        until: today.add(const Duration(days: 2)),
      );
    default:
    // open, start, got_it, not_today, fine: logged, nothing to change.
  }
  await notifier.refresh();
}
