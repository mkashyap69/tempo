import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

/// v3 interactive coach 4 (0.11.0): "Plan next week with me". One week's
/// busy days and long day, on top of the usual availability and template.
final class WeekOverride {
  const WeekOverride({this.busy = const {}, this.longDay});

  /// Weekdays (1 = Monday) with no training this week.
  final Set<int> busy;

  /// This week's long day, or null for the usual one.
  final int? longDay;

  String toJson() =>
      jsonEncode({'busy': busy.toList()..sort(), 'long': longDay});

  static WeekOverride? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return WeekOverride(
        busy: {for (final d in (j['busy'] as List)) d as int},
        longDay: j['long'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

String weekOverrideKey(DateTime monday) =>
    'week_override_${st.dateKey(monday)}';

/// [base] for a week with [o]: busy days come off the available and lifting
/// days, and the long day moves (when it's still an available day).
sc.CoachPrefs prefsForWeek(sc.CoachPrefs base, WeekOverride? o) {
  if (o == null) return base;
  final days = base.days.difference(o.busy);
  final long = o.longDay != null && days.contains(o.longDay)
      ? o.longDay
      : (base.longDay != null && days.contains(base.longDay)
            ? base.longDay
            : null);
  return sc.CoachPrefs(
    goal: base.goal,
    likes: base.likes,
    days: days,
    maxMinutes: base.maxMinutes,
    dayMinutes: base.dayMinutes,
    longDay: long,
    liftDays: base.liftDays.difference(o.busy),
    hardSessions: base.hardSessions,
  );
}

Future<WeekOverride?> loadWeekOverride(st.TempoDb db, DateTime monday) async =>
    WeekOverride.parse(await db.setting(weekOverrideKey(monday)));
