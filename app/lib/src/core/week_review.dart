import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_extras.dart' show statusOf;
import 'coach_service.dart';
import 'longevity_service.dart';
import 'profile.dart';

/// One day of the Coach week: what was planned and how it went.
final class ReviewDay {
  const ReviewDay(this.date, this.session, this.status, this.strain);
  final DateTime date;
  final sc.Session session;

  /// null for days still ahead.
  final sc.DayStatus? status;
  final double? strain;
}

/// The Coach's look back at a week (Sunday's look-back opens it).
final class WeekReview {
  WeekReview({
    required this.monday,
    required this.days,
    required this.moderateMinutes,
    required this.strengthDays,
    required this.load,
    required this.focus,
    required this.progress,
    required this.nudgesPosted,
    required this.nudgesAnswered,
  });
  final DateTime monday;
  final List<ReviewDay> days;
  final int moderateMinutes, strengthDays;
  final sc.CardioLoad load;
  final LongevityFocus? focus;
  final (double, double)? progress;
  final int nudgesPosted, nudgesAnswered;

  Iterable<ReviewDay> get planned =>
      days.where((d) => !d.session.isRest && d.status != null);
  int get done => planned
      .where(
        (d) =>
            d.status == sc.DayStatus.done ||
            d.status == sc.DayStatus.doneEasier,
      )
      .length;
  int get partial =>
      planned.where((d) => d.status == sc.DayStatus.partial).length;
  int get missed => planned
      .where(
        (d) =>
            d.status == sc.DayStatus.missedDay ||
            d.status == sc.DayStatus.skipped,
      )
      .length;

  /// One line for the top of the screen.
  String get headline {
    final n = planned.length;
    if (n == 0) return 'Nothing planned yet this week.';
    if (done == n) return 'Every planned session done.';
    if (done >= n - 1) return '$done of $n sessions done — a solid week.';
    if (missed >= 3) {
      return '$done of $n done. Busy week — next week starts fresh, nothing is owed.';
    }
    return '$done of $n sessions done.';
  }
}

Future<WeekReview> loadWeekReview(st.TempoDb db, {DateTime? at}) async {
  final now = at ?? DateTime.now();
  final today = dayOf(now);
  final mon = mondayOf(today);
  final sun = mon.add(const Duration(days: 6));
  final rows = await CoachService(db).ensureWeek(today);
  final scores = {
    for (final s in await db.scoresBetween(mon, sun)) s.date: s.strain,
  };
  final days = <ReviewDay>[];
  for (var i = 0; i < rows.length; i++) {
    final d = mon.add(Duration(days: i));
    final s = sc.Session.fromJson(
      jsonDecode(rows[i].session) as Map<String, dynamic>,
    );
    days.add(
      ReviewDay(
        d,
        s,
        d.isAfter(today) ? null : await statusOf(db, rows[i], d, at: now),
        scores[rows[i].date],
      ),
    );
  }
  final ws = await db.workoutsBetween(mon, sun.add(const Duration(days: 1)));
  var moderate = 0;
  final strength = <String>{};
  for (final w in ws) {
    final d = doneWorkout(w);
    if (d.zoneMinutes.length == 5) {
      moderate += d.zoneMinutes.skip(1).fold<int>(0, (a, z) => a + z);
    }
    if (d.sport == sc.Sport.strength) {
      strength.add(st.dateKey(st.fromTs(w.start)));
    }
  }
  var focus = await loadFocus(db);
  if (focus != null && !focus.activeOn(today)) focus = null;
  final profile = await loadAppProfile(db) ?? const Profile();
  final log = await db.nudgesSince(mon);
  final posted = log.where((r) => r.event == 'posted').toList();
  final answered = posted.where(
    (p) => log.any(
      (r) =>
          (r.event == 'action' || r.event == 'tapped') &&
          r.kind == p.kind &&
          r.ts >= (p.fireAt ?? p.ts) &&
          r.ts <= (p.fireAt ?? p.ts) + 2 * 3600,
    ),
  );
  return WeekReview(
    monday: mon,
    days: days,
    moderateMinutes: moderate,
    strengthDays: strength.length,
    load: await loadFor(db, today),
    focus: focus,
    progress: focus == null ? null : await focusProgress(db, focus, profile),
    nudgesPosted: posted.length,
    nudgesAnswered: answered.length,
  );
}
