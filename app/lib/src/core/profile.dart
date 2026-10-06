import 'dart:convert';

import 'package:band_ble/band_ble.dart';
import 'package:scoring/scoring.dart';
import 'package:store/store.dart';

/// Setting keys. Settings are never secrets; the auth key lives in KeyStore.
abstract final class Keys {
  static const profile = 'profile_v2';
  static const legacyProfile = 'profile';
  static const onboarded = 'onboarded';
  static const theme = 'theme'; // system | dark | light
  static const morningCall = 'morning_call'; // HH:mm or off
  static const bedtimeNudge = 'bedtime_nudge'; // minutes before, or off
  static const wakeTime = 'wake_time'; // HH:mm, empty = from your usual
  static const buzzCues = 'buzz_cues'; // 1 | 0
  static const firmware = 'firmware';
  static const battery = 'battery';
  static const batteryAt = 'battery_at';
  static const lastSync = 'last_sync';
  static const lastAttempt = 'last_sync_attempt';
  static const lastError = 'last_sync_error'; // kind|detail
  static const carried = 'coach_carried';
  static const planAdapted = 'plan_adapted';
  static const reportCardTheme = 'report_card_theme';
  static const reportExact = 'report_exact';
  static const rangeHaptic = 'range_haptic_day'; // date of the last one
  static const batteryLog = 'battery_log'; // JSON [[unix s, pct], …]
  static const sleepAssist = 'band_sleep_assist'; // 1 | 0
  static const stressMonitor = 'band_stress'; // 1 | 0
  static const smartAlarm = 'smart_alarm'; // HH:mm or off
  static const healthExport = 'health_export'; // 1 | 0
  static const healthExportedTo = 'health_exported_to'; // ISO, last written
  static const pauses = 'pauses'; // JSON, see pause.dart
  static const batteryPrompted = 'battery_opt_prompted'; // 1 once asked
  static const bandDismissed = 'band_workouts_dismissed'; // JSON [start ts]
  static const bandConfigured = 'band_configured'; // signature last confirmed
  static const lastCharge = 'last_charge'; // ISO|level, from band 0x0006
  static const longevityInputs = 'longevity_inputs'; // JSON, ManualHealth
  static const longevityFocus = 'longevity_focus'; // JSON {lever,start,weeks}
  // Tempo Coach.
  static const coachSlot = 'coach_slot'; // am | pm | flex; unset = inferred
  static const coachSlotAm = 'coach_slot_am'; // HH:mm, default 07:00
  static const coachSlotPm = 'coach_slot_pm'; // HH:mm, default 18:00
  static const notifCats = 'notif_cats'; // JSON {kind: 0|1}
  static const notifCap = 'notif_cap'; // proactive nudges a day, 0–2
  static const notifPrecise = 'notif_precise'; // 1 = exact alarms (Android)
  static const notifScheduled = 'notif_scheduled'; // JSON, what's pending
  static const notifV2 = 'notif_v2_migrated'; // 1 once legacy ids are gone
  static const stepsNow = 'steps_now'; // ISO|steps, band's own total
  static const realignDismissed = 'coach_realign_dismissed'; // date
  static const coachBlock = 'coach_block'; // JSON TrainingBlock, or empty
}

/// Everything the user tells Tempo in onboarding and Profile.
final class Profile {
  const Profile({
    this.age = 31,
    this.heightCm = 176,
    this.weightKg = 74,
    this.maxHr,
    this.metric = true,
    this.male = true,
    this.goal = Goal.fitness,
    this.likes = const {
      Sport.strength,
      Sport.running,
      Sport.cycling,
      Sport.yoga,
    },
    this.days = const {1, 2, 4, 5, 6, 7},
    this.maxMinutes = 75,
    this.wornOn = 'Left wrist',
  });

  final int age, heightCm;
  final double weightKg;

  /// null = estimated from age.
  final int? maxHr;
  final bool metric, male;
  final Goal goal;
  final Set<Sport> likes;
  final Set<int> days;
  final int maxMinutes;
  final String wornOn;

  int get effectiveMaxHr => maxHr ?? maxHrFromAge(age);
  bool get wornLeft => wornOn != 'Right wrist';
  bool get maxHrEstimated => maxHr == null;

  CoachPrefs get prefs =>
      CoachPrefs(goal: goal, likes: likes, days: days, maxMinutes: maxMinutes);

  UserProfile get band => UserProfile(
    birthDate: DateTime(DateTime.now().year - age, 1, 1),
    heightCm: heightCm,
    weightKg: weightKg,
    male: male,
  );

  Profile copyWith({
    int? age,
    int? heightCm,
    double? weightKg,
    int? Function()? maxHr,
    bool? metric,
    bool? male,
    Goal? goal,
    Set<Sport>? likes,
    Set<int>? days,
    int? maxMinutes,
    String? wornOn,
  }) => Profile(
    age: age ?? this.age,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    maxHr: maxHr == null ? this.maxHr : maxHr(),
    metric: metric ?? this.metric,
    male: male ?? this.male,
    goal: goal ?? this.goal,
    likes: likes ?? this.likes,
    days: days ?? this.days,
    maxMinutes: maxMinutes ?? this.maxMinutes,
    wornOn: wornOn ?? this.wornOn,
  );

  Map<String, Object?> toJson() => {
    'age': age,
    'height': heightCm,
    'weight': weightKg,
    'maxHr': maxHr,
    'metric': metric,
    'male': male,
    'goal': goal.name,
    'likes': [for (final s in likes) s.name],
    'days': days.toList()..sort(),
    'maxMinutes': maxMinutes,
    'wornOn': wornOn,
  };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
    age: j['age'] as int? ?? 31,
    heightCm: j['height'] as int? ?? 176,
    weightKg: (j['weight'] as num?)?.toDouble() ?? 74,
    maxHr: j['maxHr'] as int?,
    metric: j['metric'] as bool? ?? true,
    male: j['male'] as bool? ?? true,
    goal: Goal.values.asNameMap()[j['goal']] ?? Goal.fitness,
    likes: {
      for (final s in (j['likes'] as List? ?? const []))
        if (Sport.values.asNameMap()[s] != null)
          Sport.values.byName(s as String),
    },
    days: {for (final d in (j['days'] as List? ?? const [])) d as int},
    maxMinutes: j['maxMinutes'] as int? ?? 75,
    wornOn: j['wornOn'] as String? ?? 'Left wrist',
  );
}

Future<Profile?> loadAppProfile(TempoDb db) async {
  final raw = await db.setting(Keys.profile);
  if (raw != null) {
    return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
  // Phase 0–4 builds stored only the band profile.
  final legacy = await db.setting(Keys.legacyProfile);
  if (legacy == null) return null;
  final j = jsonDecode(legacy) as Map<String, dynamic>;
  final birth = DateTime.parse(j['birth'] as String);
  return Profile(
    age: DateTime.now().year - birth.year,
    heightCm: j['height'] as int,
    weightKg: (j['weight'] as num).toDouble(),
    male: j['male'] as bool,
  );
}

/// Saves the profile and keeps the scoring HR max in step with it.
Future<void> saveAppProfile(TempoDb db, Profile p) async {
  await db.putSetting(Keys.profile, jsonEncode(p.toJson()));
  await db.putSetting('hr_max', '${p.effectiveMaxHr}');
}

/// Band profile for configure(); used by Settings → rewrite.
Future<UserProfile?> loadProfile(TempoDb db) async =>
    (await loadAppProfile(db))?.band;

String goalLabel(Goal g) => switch (g) {
  Goal.fitness => 'Build fitness',
  Goal.fatLoss => 'Lose fat',
  Goal.performance => 'Perform at a sport',
  Goal.wellbeing => 'Feel better',
};

String goalSub(Goal g) => switch (g) {
  Goal.fitness => 'More aerobic engine, week on week',
  Goal.fatLoss => 'Steady daily movement, protected sleep',
  Goal.performance => 'Peak for sessions and match days',
  Goal.wellbeing => 'Energy, sleep and less stress first',
};

String sportLabel(Sport? s) => switch (s) {
  Sport.strength => 'Strength',
  Sport.running => 'Running',
  Sport.cycling => 'Cycling',
  Sport.walking => 'Walking',
  Sport.hiit => 'HIIT',
  Sport.yoga => 'Yoga',
  Sport.sport => 'Sport',
  null => 'Workout',
};

/// [sportLabel] for a stored sport name (null or unknown → "Workout").
String sportLabelFor(String? name) =>
    sportLabel(Sport.values.asNameMap()[name]);

/// Onboarding chip order.
const sportOrder = [
  Sport.strength,
  Sport.running,
  Sport.cycling,
  Sport.walking,
  Sport.hiit,
  Sport.yoga,
  Sport.sport,
];
