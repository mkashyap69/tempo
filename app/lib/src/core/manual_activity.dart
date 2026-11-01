import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show dayOf;
import 'profile.dart' show sportLabel;
import 'score_service.dart';

/// An activity added by hand (U4, decisions.md 2026-11-01): a workout row
/// with source `manual`, its minutes in the RPE's zone (an estimate), and
/// its load from session RPE. Rescored twice: the first pass measures the
/// heart rate the watch caught in its window, the second adds the rest.
Future<int> addManualActivity(
  st.TempoDb db, {
  required sc.Sport sport,
  required DateTime start,
  required int minutes,
  required int rpe,
  String? title,
}) async {
  final end = start.add(Duration(minutes: minutes));
  final id = await db.addWorkout(
    st.WorkoutsCompanion.insert(
      start: st.toTs(start),
      end: st.toTs(end),
      sport: Value(sport.name),
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : sportLabel(sport),
      source: 'manual',
      confirmed: const Value(true),
      rpe: Value(rpe),
      strain: sc.strainFromTrimp(sc.trimpFromRpe(rpe, minutes)),
      trimp: 0,
      zones: jsonEncode(sc.manualZones(minutes, rpe)),
    ),
  );
  final svc = ScoreService(db);
  await svc.recomputeFrom(dayOf(start));
  await svc.recomputeFrom(dayOf(start));
  return id;
}
