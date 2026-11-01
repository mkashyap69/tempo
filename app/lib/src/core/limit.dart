import 'dart:convert';

import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;

/// Training around an injury (U3, decisions.md 2026-11-01): the plan
/// swaps what the injury rules out; baselines keep learning, unlike a
/// pause. Kept as JSON in settings: [[from, to|null, limit]], newest last.
const limitKey = 'coach_limit';

final class LimitSpan {
  const LimitSpan(this.from, this.limit, {this.to});
  final DateTime from;
  final DateTime? to;
  final sc.TrainingLimit limit;

  bool get active => to == null;

  bool covers(DateTime day) {
    final d = dayOf(day);
    if (d.isBefore(dayOf(from))) return false;
    return to == null || !d.isAfter(dayOf(to!));
  }

  List<Object?> toJson() => [
    st.dateKey(from),
    to == null ? null : st.dateKey(to!),
    limit.name,
  ];

  static LimitSpan? fromJson(List<dynamic> j) {
    final l = sc.TrainingLimit.values.asNameMap()[j[2]];
    if (l == null) return null;
    return LimitSpan(
      DateTime.parse(j[0] as String),
      l,
      to: j[1] == null ? null : DateTime.parse(j[1] as String),
    );
  }
}

Future<List<LimitSpan>> loadLimits(st.TempoDb db) async {
  final raw = await db.setting(limitKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [
      for (final e in jsonDecode(raw) as List) ?LimitSpan.fromJson(e as List),
    ];
  } catch (_) {
    return const [];
  }
}

/// The limit on [day] (none outside every span).
Future<sc.TrainingLimit> limitOn(st.TempoDb db, DateTime day) async {
  for (final s in (await loadLimits(db)).reversed) {
    if (s.covers(day)) return s.limit;
  }
  return sc.TrainingLimit.none;
}

/// Whether any day of the week from [monday] had a limit.
Future<bool> limitedWeek(st.TempoDb db, DateTime monday) async {
  final spans = await loadLimits(db);
  for (var i = 0; i < 7; i++) {
    final d = monday.add(Duration(days: i));
    if (spans.any((s) => s.covers(d))) return true;
  }
  return false;
}

/// Sets the limit from [on] (today): ends the open span the day before and
/// starts [l], unless [l] is none.
Future<void> setLimit(st.TempoDb db, sc.TrainingLimit l, {DateTime? on}) async {
  final day = dayOf(on ?? DateTime.now());
  final spans = [
    for (final s in await loadLimits(db))
      if (!s.active)
        s
      else if (dayOf(s.from).isBefore(day))
        LimitSpan(s.from, s.limit, to: day.subtract(const Duration(days: 1))),
  ];
  if (l != sc.TrainingLimit.none) spans.add(LimitSpan(day, l));
  await db.putSetting(
    limitKey,
    jsonEncode([for (final s in spans) s.toJson()]),
  );
}
