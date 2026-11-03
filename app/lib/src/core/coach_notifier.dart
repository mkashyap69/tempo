import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'block_service.dart' show loadGoalView;
import 'coach_extras.dart' show stepsToday;
import 'sleep_coach.dart' show loadSleepPlan;
import 'coach_service.dart';
import 'everyday.dart' show loadBodySignals;
import 'journal.dart' show journalCheckedIn;
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

  /// nudge-2 once timing is learned (C5), else nudge-1.
  String _algo = sc.nudgeAlgo;

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
    // V7: a kind that has changed nothing in four weeks is paused, unless
    // you turned it back on within them.
    try {
      final now = DateTime.now();
      final keep = _dateMap(await db.setting(Keys.notifEffectKeep));
      final counts = sc.followCounts(await followTrials(db, now));
      final paused = <String, String>{};
      for (final k in sc.notWorking(counts)) {
        final kept = keep[k.name];
        if (kept != null && now.difference(kept).inDays < effectWindowDays) {
          continue;
        }
        if (!out.contains(k)) continue;
        out.remove(k);
        final c = counts[k]!;
        paused[k.name] = '${st.dateKey(now)}|${c.n}|${c.followed}';
      }
      final raw = jsonEncode(paused);
      if (raw != (await db.setting(Keys.notifEffectPaused) ?? '{}')) {
        await db.putSetting(Keys.notifEffectPaused, raw);
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

  /// Days of reminders judged for [sc.notWorking].
  static const effectWindowDays = 28;

  static Map<String, DateTime> _dateMap(String? raw) {
    try {
      final m = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: ?DateTime.tryParse('${e.value}'.split('|').first),
      };
    } catch (_) {
      return {};
    }
  }

  /// Each wind-down and session reminder posted in the last four weeks and
  /// whether it was followed: asleep by the bedtime it was for (its fire
  /// time + the wind-down lead, within the plan's 30 minutes), or a
  /// workout of 10+ minutes that day after it.
  static Future<List<sc.NudgeTrial>> followTrials(
    st.TempoDb db,
    DateTime now,
  ) async {
    var from = now.subtract(const Duration(days: effectWindowDays));
    final since = DateTime.tryParse(
      await db.setting(Keys.notifEffectSince) ?? '',
    );
    if (since == null) {
      await db.putSetting(Keys.notifEffectSince, st.dateKey(now));
      return const [];
    }
    if (since.isAfter(from)) from = since;
    final log = await db.nudgesSince(from);
    final lead = int.tryParse(await db.setting(Keys.bedtimeNudge) ?? '') ?? 30;
    final scores = await db.scoresBetween(
      from.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    );
    final ws = await db.workoutsBetween(from, now);
    final out = <sc.NudgeTrial>[];
    for (final r in log) {
      final fa = r.fireAt;
      if (r.event != 'posted' || fa == null) continue;
      final fire = st.fromTs(fa);
      if (fire.isAfter(now)) continue;
      if (r.kind == sc.NudgeKind.winddown.name) {
        final bed = fire.add(Duration(minutes: lead));
        // The night that started nearest after the reminder.
        final night = scores
            .where(
              (s) =>
                  s.sleepStart != null &&
                  s.sleepStart! >= fa - 2 * 3600 &&
                  s.sleepStart! <= fa + 10 * 3600,
            )
            .firstOrNull;
        if (night == null) continue; // not worn: no verdict
        final asleep = st.fromTs(night.sleepStart!);
        out.add((
          kind: sc.NudgeKind.winddown,
          followed: sc.keptTime(
            asleep.hour * 60 + asleep.minute,
            bed.hour * 60 + bed.minute,
          ),
        ));
      } else if (r.kind == sc.NudgeKind.session.name) {
        final end = DateTime(fire.year, fire.month, fire.day + 1);
        out.add((
          kind: sc.NudgeKind.session,
          followed: ws.any(
            (w) =>
                (w.source != 'auto' || w.confirmed) &&
                w.end - w.start >= 600 &&
                w.start >= fa - 1800 &&
                st.fromTs(w.start).isBefore(end),
          ),
        ));
      }
    }
    return out;
  }

  static Future<void> setKind(st.TempoDb db, sc.NudgeKind k, bool on) async {
    if (on && sc.measuredKinds.contains(k)) {
      // Turned back on: not paused again for four weeks (V7).
      final keep = {
        for (final e in _dateMap(
          await db.setting(Keys.notifEffectKeep),
        ).entries)
          e.key: st.dateKey(e.value),
      };
      keep[k.name] = st.dateKey(DateTime.now());
      await db.putSetting(Keys.notifEffectKeep, jsonEncode(keep));
    }
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
        key: sc.isKeySession(s),
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
      final steps = await stepsToday(db, now);
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

    sc.BodySignals body;
    try {
      body = await loadBodySignals(db, day: day);
    } catch (_) {
      body = const sc.BodySignals([], sc.BodyLevel.learning);
    }

    final m = await moments(t, now, log);
    final model = learnedModel(log, now);
    _algo = model == null ? sc.nudgeAlgo : sc.nudgeAlgoLearned;
    final sleepPlan = await loadSleepPlan(db, now: now);
    return sc.NudgeContext(
      model: model,
      seed: day.year * 1000 + day.month * 40 + day.day,
      now: now,
      wake: t.wakeMinute,
      bedtime: t.bedtimeMinute,
      today: todayDay,
      tomorrow: tomorrowDay,
      morning: morning == 'off' || parseHm(morning) == null
          ? null
          : sc.briefMinute(parseHm(morning)!, t.usualWakeMinute),
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
      bodyOff: body.level == sc.BodyLevel.rest ? body.off.length : 0,
      journalPending: !await journalCheckedIn(
        db,
        day.subtract(const Duration(days: 1)),
      ),
      needTonight: t.needTonight,
      briefTitle: m.briefTitle,
      win: m.win,
      weekGoal: m.weekGoal,
      insight: m.insight,
      comeback: m.comeback,
      sleepPlanLine: sleepPlan == null || sleepPlan.finished
          ? null
          : 'day ${sleepPlan.day + 1} · up by ${fmtHm(sleepPlan.plan.wake)}',
      healthSentToday: log.any(
        (r) =>
            r.kind == sc.NudgeKind.health.name &&
            r.day == st.dateKey(day) &&
            (r.event == 'posted' || r.event == 'action'),
      ),
    );
  }

  /// The N2 coach moments for [now]: the brief's title, today's win, the
  /// week-goal check-in, an insight and the come-back message. Each part
  /// fails alone: a broken query costs that moment, not the schedule.
  Future<
    ({
      String? briefTitle,
      sc.Win? win,
      (String, String)? weekGoal,
      (String, String)? insight,
      (String, String)? comeback,
    })
  >
  moments(TodayData t, DateTime now, List<st.NudgeLogData> log) async {
    final day = dayOf(now);
    Future<T?> safe<T>(Future<T?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        debugPrint('coach moments: $e');
        return null;
      }
    }

    String? briefTitle;
    final r = t.recovery;
    if (!t.calibrating && r != null && !t.stale) {
      final lead = callFor(t).lead.trim().replaceAll(RegExp(r'[.:,—–-]+$'), '');
      briefTitle = '$lead · recovery ${r.round()}%';
    }
    final win = await safe(() => _win(t, now, log));
    final weekGoal = await safe(() => _weekGoal(day));
    final comeback = await safe(() => _comeback(t, now));
    final insight = await safe(() => _insight(now, log));
    return (
      briefTitle: briefTitle,
      win: win,
      weekGoal: weekGoal,
      insight: insight,
      comeback: comeback,
    );
  }

  Future<sc.Win?> _win(
    TodayData t,
    DateTime now,
    List<st.NudgeLogData> log,
  ) async {
    final day = dayOf(now);
    final past = [
      for (final s in t.history)
        if (!s.calibrating && s.recovery != null) s.recovery!,
    ].take(30).toList();
    // Nights in a row in bed within 30 min of the bedtime Tempo set.
    var kept = 0;
    for (final s in [?t.score, ...t.history]) {
      final a = s.sleepStart;
      if (a == null) break;
      final at = st.fromTs(a);
      var diff = at.hour * 60 + at.minute - t.bedtimeMinute % 1440;
      if (diff > 720) diff -= 1440;
      if (diff < -720) diff += 1440;
      if (diff > 30) break;
      kept++;
    }
    // This week's sessions.
    final week = await CoachService(db).ensureWeek(day);
    var planned = 0, done = 0;
    var todayDone = false;
    const doneNames = {'done', 'doneEasier', 'doneHarder'};
    for (final row in week) {
      final s = sc.Session.fromJson(
        jsonDecode(row.session) as Map<String, dynamic>,
      );
      if (s.isRest) continue;
      planned++;
      if (doneNames.contains(row.status)) {
        done++;
        if (row.date == st.dateKey(day)) todayDone = true;
      }
    }
    // Days in a row at the step goal, today counted once reached.
    final goal = t.profile.effectiveStepGoal;
    final health = t.source != sc.bandSource;
    var stepDays = 0;
    for (var i = 0; i < 31; i++) {
      final d0 = day.subtract(Duration(days: i));
      final n = i == 0
          ? await stepsToday(db, now)
          : await db.stepsBetween(
              d0,
              d0.add(const Duration(days: 1)),
              health: health,
            );
      if (n < goal) {
        if (i == 0) continue;
        break;
      }
      stepDays++;
    }
    // Longest measured walk or run today against the 90 days before.
    double? km(Iterable<st.Workout> ws) {
      final xs = [
        for (final w in ws)
          if (w.distanceM != null) w.distanceM!,
      ];
      return xs.isEmpty ? null : xs.reduce((a, b) => a > b ? a : b) / 1000;
    }

    final todayKm = km(await db.workoutsBetween(day, now));
    final beforeKm = km(
      await db.workoutsBetween(day.subtract(const Duration(days: 90)), day),
    );
    // Halfway through a dated goal's block.
    sc.BlockWeek? bw;
    String? goalName;
    try {
      final gv = await loadGoalView(db, at: now);
      if (gv != null && gv.block.isEvent) {
        bw = gv.week;
        goalName = sc.goalName(gv.block.goal);
      }
    } catch (_) {}
    final recent = <sc.WinKind>{
      for (final r in log)
        if (r.kind == sc.NudgeKind.win.name &&
            r.ts >= st.toTs(now.subtract(const Duration(days: 7))))
          ?sc.WinKind.values.asNameMap()[_payload(r)['win']],
    };
    return sc.pickWin(
      sc.WinInput(
        recovery: r0(t),
        recoveryLast30: past,
        bedtimeKeptNights: kept,
        sessionsDone: done,
        sessionsPlanned: planned,
        weekJustDone: todayDone && done == planned,
        stepGoalDays: stepDays,
        stepGoal: goal,
        calibratedToday:
            !t.calibrating &&
            t.history.isNotEmpty &&
            t.history.first.calibrating,
        longestKmToday: todayKm,
        longestKmBefore: beforeKm,
        bedtime: fmtHm(t.bedtimeMinute),
        recentWins: recent,
        blockWeek: bw?.index,
        blockWeeks: bw == null || bw.weeks == 0 ? null : bw.weeks,
        goal: goalName,
      ),
    );
  }

  /// Today's win for the moment card on Today, whatever was notified.
  Future<sc.Win?> todayWin(TodayData t, DateTime now) => _win(t, now, const []);

  static double? r0(TodayData t) => t.stale ? null : t.recovery;

  Future<(String, String)?> _weekGoal(DateTime day) async {
    final week = await CoachService(db).ensureWeek(day);
    var planned = 0, done = 0;
    String? nextTitle, nextDay;
    const doneNames = {'done', 'doneEasier', 'doneHarder'};
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    for (final row in week) {
      final s = sc.Session.fromJson(
        jsonDecode(row.session) as Map<String, dynamic>,
      );
      if (s.isRest) continue;
      planned++;
      if (doneNames.contains(row.status)) {
        done++;
      } else if (nextTitle == null &&
          row.date.compareTo(st.dateKey(day)) >= 0) {
        final d = DateTime.parse(row.date);
        nextTitle = '${s.title} ${s.minutes}′';
        nextDay = row.date == st.dateKey(day) ? 'Today' : days[d.weekday - 1];
      }
    }
    return sc.weekGoalCopy(
      done: done,
      planned: planned,
      nextTitle: nextTitle,
      nextDay: nextDay,
    );
  }

  Future<(String, String)?> _comeback(TodayData t, DateTime now) async {
    final last = DateTime.tryParse(await db.setting(Keys.lastOpened) ?? '');
    if (last == null) return null;
    final away = dayOf(now).difference(dayOf(last)).inDays;
    final since = [
      for (final s in [?t.score, ...t.history])
        if (parseDateKey(s.date).isAfter(dayOf(last)) && s.sleptHours != null)
          s,
    ];
    final best14 = [
      for (final s in t.history.take(14))
        if (s.recovery != null && !s.calibrating) s.recovery!,
    ];
    return sc.comebackCopy(
      daysAway: away,
      nights: since.length,
      avgSleepH: since.isEmpty
          ? null
          : since.fold<double>(0, (a, s) => a + s.sleptHours!) / since.length,
      recovery: r0(t),
      recoveryBest14: best14.isEmpty
          ? null
          : best14.reduce((a, b) => a > b ? a : b),
    );
  }

  /// Today's insight as a quiet notification, when Tempo wasn't opened
  /// today (else Today already shows it) and none went in 3 days.
  Future<(String, String)?> _insight(
    DateTime now,
    List<st.NudgeLogData> log,
  ) async {
    final last = DateTime.tryParse(await db.setting(Keys.lastOpened) ?? '');
    if (last != null && dayOf(last) == dayOf(now)) return null;
    final recent = log.any(
      (r) =>
          r.kind == sc.NudgeKind.insight.name &&
          r.event == 'posted' &&
          r.ts >= st.toTs(now.subtract(const Duration(days: 3))),
    );
    if (recent) return null;
    final h = await insightPicker?.call(db);
    if (h == null) return null;
    return (h.$1, h.$2);
  }

  /// Picks today's insight (title, body); set by the app, which owns the
  /// providers the picker reads. Null in tests and the background run.
  static Future<(String, String)?> Function(st.TempoDb db)? insightPicker;

  /// The morning call, short: the same decision Today shows.
  static String? _brief(TodayData t) {
    if (t.calibrating) {
      return 'Still learning your baseline · in by ${fmtHm(t.bedtimeMinute)}';
    }
    final r = t.recovery;
    if (r == null) return null;
    final call = callFor(t);
    final why = sc.reasonShort(call.reason);
    final rest = t.restDay ? ' · rest day' : '';
    return 'Recovery ${r.round()}%$rest${why.isEmpty ? '' : ' · $why'} · in by ${fmtHm(t.bedtimeMinute)}';
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
        await _log(
          o['kind'] as String,
          id,
          fire,
          'posted',
          ts: fire,
          payload: {
            if (o['choice'] != null) 'choice': o['choice'],
            if (o['win'] != null) 'win': o['win'],
          },
        );
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
            if (n.payload['choice'] != null) 'choice': n.payload['choice'],
            if (n.payload['win'] != null) 'win': n.payload['win'],
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
      algoVersion: _algo,
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

/// The timing model (C5), once the log covers [sc.learnAfterDays]. Each
/// posted session or focus nudge is scored by what followed within 2 h:
/// a button 1, a tap 0.5, nothing 0.
sc.SlotModel? learnedModel(List<st.NudgeLogData> log, DateTime now) {
  if (log.isEmpty) return null;
  final first = st.fromTs(log.first.ts);
  if (now.difference(first).inDays < sc.learnAfterDays) return null;
  final outcomes = <sc.SlotOutcome>[];
  for (final p in log) {
    if (p.event != 'posted') continue;
    final kind = sc.NudgeKind.values.asNameMap()[p.kind];
    if (kind != sc.NudgeKind.session && kind != sc.NudgeKind.lever) continue;
    final choice = _payload(p)['choice'];
    if (choice is! int) continue;
    final fire = p.fireAt ?? p.ts;
    var reward = 0.0;
    for (final r in log) {
      if (r.kind != p.kind || r.ts < fire || r.ts > fire + 2 * 3600) continue;
      if (r.event == 'action') reward = 1;
      if (r.event == 'tapped' && reward < .5) reward = .5;
    }
    outcomes.add((
      kind: kind!,
      choice: choice,
      weekend: st.fromTs(fire).weekday >= 6,
      reward: reward,
    ));
  }
  return sc.SlotModel.fromOutcomes(outcomes);
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
