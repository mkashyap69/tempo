import 'package:health_source/health_source.dart';
import 'package:store/store.dart' as st;

/// What Tempo found in Apple Health / Health Connect, in the user's words:
/// one line per thing Tempo needs, how much of it, and which apps wrote it
/// (B1b). Shown after the first read in onboarding and in You → Data source.
/// Built from the stored records, so it never touches the plugin.

enum CheckState { good, partial, missing }

const nothingYet = 'Nothing yet';

class SourceLine {
  const SourceLine({
    required this.title,
    required this.state,
    required this.amount,
    required this.apps,
    this.hint,
  });
  final String title;
  final CheckState state;

  /// "90 days", "23 nights", "31 workouts", or "Nothing yet".
  final String amount;

  /// Writers, most records first.
  final List<String> apps;

  /// What a partial or missing line means for the user.
  final String? hint;
}

class SourceCheck {
  const SourceCheck(this.lines, {this.sleepApps = const []});
  final List<SourceLine> lines;

  /// More than one app wrote sleep: Tempo uses one (You → Data source).
  final List<String> sleepApps;

  /// Anything read at all (an empty optional line is partial, not found).
  bool get anything => lines.any((l) => l.amount != nothingYet);
}

const _sleep = {
  HealthKind.sleepInBed,
  HealthKind.sleepSession,
  HealthKind.sleepAsleep,
  HealthKind.sleepAwake,
  HealthKind.sleepLight,
  HealthKind.sleepDeep,
  HealthKind.sleepRem,
};
const _staged = {
  HealthKind.sleepLight,
  HealthKind.sleepDeep,
  HealthKind.sleepRem,
};

/// Plain names for the apps Health reports (bundle ids on iOS, package
/// names on Android); anything unknown is shown as given.
String appName(String id) {
  final s = id.toLowerCase();
  if (s.contains('apple.health') || s == 'com.apple.health') return 'iPhone';
  if (s.contains('com.apple')) return 'Apple Watch';
  if (s.contains('fitbit')) return 'Fitbit';
  if (s.contains('garmin')) return 'Garmin';
  if (s.contains('oura')) return 'Oura';
  if (s.contains('samsung') || s.contains('shealth')) return 'Samsung Health';
  if (s.contains('xiaomi') || s.contains('mi.health') || s.contains('mifit')) {
    return 'Mi Fitness';
  }
  if (s.contains('google.android.apps.fitness')) return 'Google Fit';
  if (s.contains('whoop')) return 'WHOOP';
  if (s.contains('polar')) return 'Polar';
  if (s.contains('withings')) return 'Withings';
  if (s.contains('sleepcycle') || s.contains('sleep.cycle')) {
    return 'Sleep Cycle';
  }
  if (s.contains('dev.tempo')) return 'Tempo';
  return id;
}

/// Reads the last [days] of stored Health records and sums them up.
Future<SourceCheck> sourceCheck(
  st.TempoDb db, {
  int days = 90,
  DateTime? now,
}) async {
  final to = now ?? DateTime.now();
  final rows = await db.healthRecordsBetween(
    to.subtract(Duration(days: days)),
    to,
  );
  return summarise([
    for (final r in rows)
      if (HealthKind.values.asNameMap()[r.kind] case final k?)
        (k, DateTime.fromMillisecondsSinceEpoch(r.endMs), r.sourceApp),
  ]);
}

/// The summary for (kind, end time, writer) triples. Pure, for tests.
SourceCheck summarise(List<(HealthKind, DateTime, String)> recs) {
  final days = <HealthKind, Set<int>>{};
  final apps = <HealthKind, Map<String, int>>{};
  final count = <HealthKind, int>{};
  for (final (k, at, app) in recs) {
    // A night belongs to the morning it ends on.
    days
        .putIfAbsent(k, () => {})
        .add(DateTime(at.year, at.month, at.day).millisecondsSinceEpoch);
    final m = apps.putIfAbsent(k, () => {});
    final name = appName(app);
    m[name] = (m[name] ?? 0) + 1;
    count[k] = (count[k] ?? 0) + 1;
  }
  int dayCount(Iterable<HealthKind> ks) =>
      {for (final k in ks) ...?days[k]}.length;
  List<String> writers(Iterable<HealthKind> ks) {
    final m = <String, int>{};
    for (final k in ks) {
      for (final e in (apps[k] ?? const {}).entries) {
        m[e.key] = (m[e.key] ?? 0) + e.value;
      }
    }
    return (m.entries.toList()..sort((a, b) => b.value - a.value))
        .map((e) => e.key)
        .toList();
  }

  String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';

  final hrDays = dayCount([HealthKind.heartRate]);
  final nights = dayCount(_sleep);
  final stagedNights = dayCount(_staged);
  final hrvNights = dayCount([HealthKind.hrvSdnn, HealthKind.hrvRmssd]);
  final stepDays = dayCount([HealthKind.steps]);
  final workouts = count[HealthKind.workout] ?? 0;
  final body = [
    HealthKind.spo2,
    HealthKind.respiratoryRate,
    HealthKind.wristTemp,
  ].where((k) => (count[k] ?? 0) > 0).toList();

  final sleepWriters = writers(_sleep).where((a) => a != 'Tempo').toList();
  return SourceCheck([
    SourceLine(
      title: 'Heart rate',
      state: hrDays == 0 ? CheckState.missing : CheckState.good,
      amount: hrDays == 0 ? nothingYet : n(hrDays, 'day', 'days'),
      apps: writers([HealthKind.heartRate]),
      hint: hrDays == 0
          ? 'Strain and recovery need heart rate. Allow it, and wear your watch.'
          : null,
    ),
    SourceLine(
      title: stagedNights > 0 ? 'Sleep with stages' : 'Sleep',
      state: nights == 0
          ? CheckState.missing
          : stagedNights * 2 < nights
          ? CheckState.partial
          : CheckState.good,
      amount: nights == 0 ? nothingYet : n(nights, 'night', 'nights'),
      apps: sleepWriters,
      hint: nights == 0
          ? 'Wear your watch to bed tonight, or allow Sleep.'
          : stagedNights * 2 < nights
          ? 'Most nights have no stages, so sleep scores are less exact.'
          : null,
    ),
    SourceLine(
      title: 'HRV',
      state: hrvNights == 0 ? CheckState.partial : CheckState.good,
      amount: hrvNights == 0 ? nothingYet : n(hrvNights, 'night', 'nights'),
      apps: writers([HealthKind.hrvSdnn, HealthKind.hrvRmssd]),
      hint: hrvNights == 0
          ? 'Recovery works without it, from resting heart rate and sleep.'
          : null,
    ),
    SourceLine(
      title: 'Steps and workouts',
      state: stepDays == 0 && workouts == 0
          ? CheckState.missing
          : CheckState.good,
      amount: workouts > 0
          ? n(workouts, 'workout', 'workouts')
          : stepDays == 0
          ? nothingYet
          : n(stepDays, 'day', 'days'),
      apps: writers([HealthKind.steps, HealthKind.workout]),
    ),
    SourceLine(
      title: 'SpO₂, breathing, temperature',
      state: body.isEmpty ? CheckState.partial : CheckState.good,
      amount: body.isEmpty ? nothingYet : '${body.length} of 3',
      apps: writers(body),
      hint: body.isEmpty
          ? 'Optional: they refine recovery when present.'
          : null,
    ),
  ], sleepApps: sleepWriters.length > 1 ? sleepWriters : const []);
}
