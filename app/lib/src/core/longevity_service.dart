import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'coach_service.dart' show CoachService, dayOf;
import 'pause.dart';
import 'profile.dart';
import 'score_service.dart' show parseDateKey;

/// Optional details only the user can give (Longevity → Health details).
final class ManualHealth {
  const ManualHealth({this.smoking, this.alcohol, this.systolic, this.waist});
  final sc.Smoking? smoking;
  final double? alcohol; // units a week
  final int? systolic;
  final double? waist; // cm

  Map<String, Object?> toJson() => {
    'smoking': smoking?.name,
    'alcohol': alcohol,
    'systolic': systolic,
    'waist': waist,
  };

  static ManualHealth fromJson(Map<String, dynamic> j) => ManualHealth(
    smoking: sc.Smoking.values.asNameMap()[j['smoking']],
    alcohol: (j['alcohol'] as num?)?.toDouble(),
    systolic: (j['systolic'] as num?)?.toInt(),
    waist: (j['waist'] as num?)?.toDouble(),
  );
}

Future<ManualHealth> loadManualHealth(st.TempoDb db) async {
  final raw = await db.setting(Keys.longevityInputs);
  if (raw == null || raw.isEmpty) return const ManualHealth();
  try {
    return ManualHealth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const ManualHealth();
  }
}

Future<void> saveManualHealth(st.TempoDb db, ManualHealth m) =>
    db.putSetting(Keys.longevityInputs, jsonEncode(m.toJson()));

/// The lever the user is working on, for a set number of weeks.
final class LongevityFocus {
  const LongevityFocus(this.lever, this.start, this.weeks);
  final sc.Lever lever;
  final DateTime start;
  final int weeks;

  DateTime get end => start.add(Duration(days: 7 * weeks));
  bool activeOn(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// 1-based week of the plan on [d].
  int weekOn(DateTime d) =>
      (dayOf(d).difference(dayOf(start)).inDays ~/ 7 + 1).clamp(1, weeks);

  String toJson() => jsonEncode({
    'lever': lever.name,
    'start': st.dateKey(start),
    'weeks': weeks,
  });

  static LongevityFocus? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return LongevityFocus(
        sc.Lever.values.byName(j['lever'] as String),
        DateTime.parse(j['start'] as String),
        j['weeks'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

Future<LongevityFocus?> loadFocus(st.TempoDb db) async =>
    LongevityFocus.parse(await db.setting(Keys.longevityFocus));

/// Starts an [sc.leverWeeks]-week plan on [lever] today and rebuilds this
/// week's Coach plan around it. Null ends the plan.
Future<void> setFocus(st.TempoDb db, sc.Lever? lever) async {
  if (lever == null) {
    await db.deleteSetting(Keys.longevityFocus);
  } else {
    await db.putSetting(
      Keys.longevityFocus,
      LongevityFocus(
        lever,
        dayOf(DateTime.now()),
        sc.leverWeeks(lever),
      ).toJson(),
    );
  }
  await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
}

/// This week's progress on the focus lever: (value so far, weekly goal).
/// Steps and sleep are daily averages; minutes and sessions are totals.
Future<(double, double)?> focusProgress(
  st.TempoDb db,
  LongevityFocus f,
  Profile p,
) async {
  final today = dayOf(DateTime.now());
  final mon = today.subtract(Duration(days: today.weekday - 1));
  final end = today.add(const Duration(days: 1));
  final target = sc.leverTarget(f.lever, age: p.age, male: p.male);
  switch (f.lever) {
    case sc.Lever.activeMinutes:
      final hrMax = p.effectiveMaxHr;
      return (
        (await _countMinutes(db, mon, end, (hrMax * .6).round())).toDouble(),
        target,
      );
    case sc.Lever.strength:
      final ws = await db.workoutsBetween(mon, end);
      return (_strength(ws).toDouble(), target);
    case sc.Lever.steps:
      final days = await _dailySteps(db, mon, end);
      return (
        days.isEmpty ? 0.0 : days.reduce((a, b) => a + b) / days.length,
        target,
      );
    case sc.Lever.sleepDuration:
      final s = await db.scoresBetween(mon, today);
      final h = [for (final d in s) ?d.sleptHours];
      return (h.isEmpty ? 0.0 : h.reduce((a, b) => a + b) / h.length, target);
    default:
      return null;
  }
}

int _strength(List<st.Workout> ws) => ws
    .where(
      (w) =>
          w.sport == sc.Sport.strength.name &&
          (w.source != 'auto' || w.confirmed),
    )
    .length;

Future<int> _countMinutes(
  st.TempoDb db,
  DateTime from,
  DateTime to,
  int minHr,
) async {
  final r = await db
      .customSelect(
        'SELECT COUNT(*) AS n FROM minute_samples WHERE ts >= ? AND ts < ? AND hr >= ?',
        variables: [
          Variable.withInt(st.toTs(from)),
          Variable.withInt(st.toTs(to)),
          Variable.withInt(minHr),
        ],
      )
      .getSingle();
  return r.read<int>('n');
}

/// Steps per local day in [from, to), days with no steps left out.
Future<List<double>> _dailySteps(
  st.TempoDb db,
  DateTime from,
  DateTime to,
) async {
  final out = <double>[];
  for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final r = await db
        .customSelect(
          'SELECT COALESCE(SUM(steps), 0) AS s FROM minute_samples WHERE ts >= ? AND ts < ?',
          variables: [
            Variable.withInt(st.toTs(d)),
            Variable.withInt(st.toTs(DateTime(d.year, d.month, d.day + 1))),
          ],
        )
        .getSingle();
    final s = r.read<int>('s');
    if (s > 0) out.add(s.toDouble());
  }
  return out;
}

/// Mean band stress (1–99) in [from, to); null under a day's worth.
Future<double?> _meanStress(st.TempoDb db, DateTime from, DateTime to) async {
  final r = await db
      .customSelect(
        'SELECT AVG(value) AS m, COUNT(*) AS n FROM stress_samples '
        'WHERE ts >= ? AND ts < ? AND value BETWEEN 1 AND 99',
        variables: [
          Variable.withInt(st.toTs(from)),
          Variable.withInt(st.toTs(to)),
        ],
      )
      .getSingle();
  return r.read<int>('n') < 60 ? null : r.read<double?>('m');
}

/// Builds Tempo Age's inputs from the 30 days before [end].
Future<sc.LongevityInputs> longevityInputs(
  st.TempoDb db, {
  DateTime? end,
}) async {
  final to = dayOf(end ?? DateTime.now()).add(const Duration(days: 1));
  final from = to.subtract(const Duration(days: 30));
  final p = await loadAppProfile(db) ?? const Profile();
  final manual = await loadManualHealth(db);
  final pauses = await loadPauses(db);
  final scores = [
    for (final s in await db.scoresBetween(
      from,
      to.subtract(const Duration(days: 1)),
    ))
      if (!isPaused(pauses, parseDateKey(s.date))) s,
  ];
  final withData = scores
      .where((s) => s.sleptHours != null || s.trimp > 0)
      .length;
  double? median(Iterable<double?> xs) => sc.quantile(xs, .5);
  double? mean(Iterable<double?> xs) {
    final v = xs.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final rhr = median(scores.map((s) => s.rhr));
  final hrMax = max(
    p.effectiveMaxHr,
    scores.fold<int>(0, (a, s) => max(a, s.hrMax)),
  );
  final weeks = max(1, withData) / 7;
  final steps = await _dailySteps(db, from, to);

  // Bedtime regularity: SD of bedtimes, after-midnight times wrapped.
  final beds = [
    for (final s in scores)
      if (s.sleepStart != null)
        () {
          final t = st.fromTs(s.sleepStart!);
          final m = t.hour * 60 + t.minute;
          return (m < 12 * 60 ? m + 1440 : m).toDouble();
        }(),
  ];
  double? bedSd;
  if (beds.length >= 5) {
    final m = beds.reduce((a, b) => a + b) / beds.length;
    bedSd = sqrt(
      beds.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / beds.length,
    );
  }

  // Breathing: mean nightly score where the night had enough SpO₂.
  final breathing = <double>[];
  for (final s in scores) {
    if (s.sleepStart == null || s.sleepEnd == null) continue;
    final a = st.fromTs(s.sleepStart!), b = st.fromTs(s.sleepEnd!);
    final n = sc.breathingNight(
      start: a,
      end: b,
      sleptHours: s.sleptHours ?? b.difference(a).inMinutes / 60,
      spo2: [
        for (final x in await db.spo2Between(a, b))
          (ts: st.fromTs(x.ts), avg: x.value, quality: x.quality),
      ],
      events: [
        for (final e in await db.odEventsBetween(a, b))
          (ts: st.fromTs(e.ts), drop: e.drop),
      ],
    );
    if (n != null) breathing.add(n.score.toDouble());
  }

  return sc.LongevityInputs(
    age: p.age,
    male: p.male,
    daysOfData: withData,
    vo2max: rhr == null ? null : sc.vo2maxFromHr(hrMax, rhr),
    restingHr: rhr,
    steps: steps.length < 5
        ? null
        : steps.reduce((a, b) => a + b) / steps.length,
    activeMinutes: withData < 5
        ? null
        : await _countMinutes(db, from, to, (hrMax * .6).round()) / weeks,
    strengthPerWeek: withData < 7
        ? null
        : _strength(await db.workoutsBetween(from, to)) / weeks,
    sleepHours: mean(scores.map((s) => s.sleptHours)),
    bedtimeSdMinutes: bedSd,
    breathingScore: breathing.length < 3 ? null : mean(breathing),
    stressIndex: await _meanStress(db, from, to),
    smoking: manual.smoking,
    alcoholUnits: manual.alcohol,
    systolic: manual.systolic,
    waistCm: manual.waist,
  );
}

/// Version of the Tempo Age method, stored on snapshots.
const longevityAlgo = 2; // 2: weekly change cap

Map<String, Object?> _contributorJson(sc.Contributor c) => {
  'lever': c.lever.name,
  'value': c.value,
  'years': c.years,
  'target': c.target,
  'gain': c.gain,
  'weak': c.weak,
};

/// Computes today's Tempo Age, saves it, and fills monthly snapshots for
/// the last six months where data exists, so the trend and pace have
/// history from the start.
Future<sc.TempoAge> updateLongevity(st.TempoDb db) async {
  final today = dayOf(DateTime.now());
  Future<sc.TempoAge> snap(DateTime d) async {
    final raw = sc.tempoAge(await longevityInputs(db, end: d));
    // At most a year per week from the last settled snapshot.
    final key = st.dateKey(d);
    final prev = [
      for (final r in await db.longevitySince(
        d.subtract(const Duration(days: 200)),
      ))
        if (r.date.compareTo(key) < 0 &&
            !r.calibrating &&
            r.algoVersion == longevityAlgo)
          r,
    ].lastOrNull;
    final t = raw.calibrating || prev == null
        ? raw
        : sc.TempoAge(
            realAge: raw.realAge,
            age: sc.capChange(
              raw.age,
              prev.tempoAge,
              d.difference(parseDateKey(prev.date)).inDays,
            ),
            contributors: raw.contributors,
            calibrating: false,
          );
    await db.putLongevity(
      st.LongevityCompanion.insert(
        date: st.dateKey(d),
        tempoAge: t.age,
        realAge: t.realAge,
        calibrating: t.calibrating,
        contributors: jsonEncode([
          for (final c in t.contributors) _contributorJson(c),
        ]),
        algoVersion: longevityAlgo,
      ),
    );
    return t;
  }

  final have = {
    for (final s in await db.longevitySince(
      today.subtract(const Duration(days: 190)),
    ))
      if (s.algoVersion == longevityAlgo) s.date,
  };
  final first = await db.firstMinute();
  for (var m = 6; m >= 1; m--) {
    final d = DateTime(today.year, today.month - m, today.day);
    if (first == null || d.isBefore(first.add(const Duration(days: 30)))) {
      continue;
    }
    if (!have.contains(st.dateKey(d))) await snap(d);
  }
  return snap(today);
}

/// Trend points: (date, Tempo Age), calibrating snapshots left out.
List<(DateTime, double)> longevityPoints(List<st.LongevitySnapshot> rows) => [
  for (final r in rows)
    if (!r.calibrating) (parseDateKey(r.date), r.tempoAge),
];

/// Pace of aging from snapshots: Tempo-Age years per calendar year.
/// Profile age is a whole number that rarely changes, so calendar time is
/// added back explicitly: pace = 1 + slope of (Tempo Age − real age).
double? paceFrom(List<st.LongevitySnapshot> rows) {
  final pts = [
    for (final r in rows)
      if (!r.calibrating) (parseDateKey(r.date), r.tempoAge - r.realAge),
  ];
  if (pts.isEmpty) return null;
  final t0 = pts.first.$1;
  return sc.paceOfAging([
    for (final (d, delta) in pts) (d, delta + d.difference(t0).inDays / 365.25),
  ]);
}

/// Stored contributors back as scoring objects.
List<sc.Contributor> decodeContributors(String json) {
  try {
    return [
      for (final m in (jsonDecode(json) as List).cast<Map<String, dynamic>>())
        sc.Contributor(
          lever: sc.Lever.values.byName(m['lever'] as String),
          value: (m['value'] as num).toDouble(),
          years: (m['years'] as num).toDouble(),
          target: (m['target'] as num).toDouble(),
          gain: (m['gain'] as num).toDouble(),
          weak: m['weak'] as bool? ?? false,
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// Days with data in the last 30 (for "calibrating · n of 30").
Future<int> daysOfData(st.TempoDb db) async {
  final today = dayOf(DateTime.now());
  final pauses = await loadPauses(db);
  return (await db.scoresBetween(
        today.subtract(const Duration(days: 29)),
        today,
      ))
      .where(
        (s) =>
            (s.sleptHours != null || s.trimp > 0) &&
            !isPaused(pauses, parseDateKey(s.date)),
      )
      .length;
}
