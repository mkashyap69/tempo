/// Journal v2: what can be logged, and the entries Tempo fills in by itself
/// from the day's data.
library;

enum EntryGroup { lifestyle, health, supplements, sleep, automatic }

/// Yes/no, a number with a unit, or a time of day (minutes after midnight).
enum EntryKind { yesNo, amount, time }

final class JournalEntryDef {
  const JournalEntryDef(
    this.key,
    this.name,
    this.question,
    this.group, {
    this.kind = EntryKind.yesNo,
    this.unit,
    this.step = 1,
    this.max = 100,
  });

  /// Stored in `journal.tag`; never renamed once shipped.
  final String key;
  final String name, question;
  final EntryGroup group;
  final EntryKind kind;
  final String? unit;

  /// Stepper increment and upper bound for [EntryKind.amount].
  final double step, max;

  bool get automatic => group == EntryGroup.automatic;
}

/// Marks a saved check-in, so an all-"no" day still counts as done.
const checkinTag = '_checkin';

/// The five tags from before Journal v2: on by default, keys unchanged.
const defaultJournalKeys = [
  'alcohol',
  'late_meal',
  'caffeine_late',
  'stressful_day',
  'travel',
];

const _l = EntryGroup.lifestyle,
    _h = EntryGroup.health,
    _s = EntryGroup.supplements,
    _z = EntryGroup.sleep,
    _a = EntryGroup.automatic;

const journalCatalog = <JournalEntryDef>[
  // Lifestyle.
  JournalEntryDef('alcohol', 'Alcohol', 'Any alcohol?', _l),
  JournalEntryDef(
    'drinks',
    'Drinks',
    'How many drinks?',
    _l,
    kind: EntryKind.amount,
    unit: 'drinks',
    max: 20,
  ),
  JournalEntryDef('late_meal', 'Late meal', 'Ate within 2 h of bed?', _l),
  JournalEntryDef(
    'first_meal',
    'First meal',
    'When did you first eat?',
    _l,
    kind: EntryKind.time,
  ),
  JournalEntryDef(
    'last_meal',
    'Last meal',
    'When did you last eat?',
    _l,
    kind: EntryKind.time,
  ),
  JournalEntryDef('caffeine_late', 'Caffeine late', 'Caffeine after 2 pm?', _l),
  JournalEntryDef(
    'caffeine_mg',
    'Caffeine',
    'How much caffeine?',
    _l,
    kind: EntryKind.amount,
    unit: 'mg',
    step: 50,
    max: 1000,
  ),
  JournalEntryDef(
    'last_caffeine',
    'Last caffeine',
    'When was your last caffeine?',
    _l,
    kind: EntryKind.time,
  ),
  JournalEntryDef(
    'water',
    'Water',
    'How much water?',
    _l,
    kind: EntryKind.amount,
    unit: 'ml',
    step: 250,
    max: 6000,
  ),
  JournalEntryDef('stressful_day', 'Stressful day', 'A stressful day?', _l),
  JournalEntryDef('travel', 'Travel', 'New place or time zone?', _l),
  JournalEntryDef('daylight', 'Morning daylight', '10+ min outside early?', _l),
  JournalEntryDef('screen_late', 'Screens in bed', 'Phone or TV in bed?', _l),
  JournalEntryDef('added_sugar', 'Added sugar', 'Much added sugar?', _l),
  JournalEntryDef(
    'processed_food',
    'Processed food',
    'Mostly processed food?',
    _l,
  ),
  JournalEntryDef('veg', 'Fruit and veg', '5+ portions of fruit and veg?', _l),
  JournalEntryDef(
    'high_protein',
    'Protein at meals',
    'Protein at each meal?',
    _l,
  ),
  JournalEntryDef('dairy', 'Dairy', 'Any dairy?', _l),
  JournalEntryDef(
    'spicy_late',
    'Spicy dinner',
    'Spicy food in the evening?',
    _l,
  ),
  JournalEntryDef('fasting', 'Fasting', 'Fasted on purpose?', _l),
  JournalEntryDef(
    'social',
    'Time with people',
    'Time with friends or family?',
    _l,
  ),
  JournalEntryDef('work_late', 'Worked late', 'Worked into the evening?', _l),
  JournalEntryDef(
    'meditation',
    'Meditation',
    'Meditated or did breathwork?',
    _l,
  ),
  JournalEntryDef('reading', 'Read before bed', 'Read before sleep?', _l),
  JournalEntryDef('sauna', 'Sauna', 'Sauna or hot bath?', _l),
  JournalEntryDef('cold', 'Cold exposure', 'Cold shower or ice bath?', _l),
  JournalEntryDef('stretching', 'Stretching', 'Stretched or did mobility?', _l),
  JournalEntryDef('massage', 'Massage', 'Massage or foam rolling?', _l),
  JournalEntryDef('nicotine', 'Nicotine', 'Any nicotine?', _l),
  JournalEntryDef('cannabis', 'Cannabis', 'Any cannabis?', _l),
  // Health status.
  JournalEntryDef('sick', 'Feeling ill', 'Felt ill?', _h),
  JournalEntryDef('fever', 'Fever', 'A fever?', _h),
  JournalEntryDef('sore_throat', 'Sore throat', 'A sore throat or cold?', _h),
  JournalEntryDef('headache', 'Headache', 'A headache?', _h),
  JournalEntryDef('injury', 'Injury', 'Carrying an injury?', _h),
  JournalEntryDef('sore', 'Sore muscles', 'Very sore muscles?', _h),
  JournalEntryDef('allergies', 'Allergies', 'Allergy symptoms?', _h),
  JournalEntryDef('period', 'Period', 'On your period?', _h),
  JournalEntryDef('cramps', 'Cramps', 'Abdominal cramps?', _h),
  JournalEntryDef('digestion', 'Upset stomach', 'An upset stomach?', _h),
  JournalEntryDef('low_mood', 'Low mood', 'A low mood?', _h),
  JournalEntryDef('anxious', 'Anxious', 'Felt anxious?', _h),
  JournalEntryDef('energised', 'Energised', 'Felt full of energy?', _h),
  // Supplements and medication.
  JournalEntryDef('magnesium', 'Magnesium', 'Took magnesium?', _s),
  JournalEntryDef('melatonin', 'Melatonin', 'Took melatonin?', _s),
  JournalEntryDef('creatine', 'Creatine', 'Took creatine?', _s),
  JournalEntryDef('vitamin_d', 'Vitamin D', 'Took vitamin D?', _s),
  JournalEntryDef('fish_oil', 'Fish oil', 'Took fish oil?', _s),
  JournalEntryDef('ashwagandha', 'Ashwagandha', 'Took ashwagandha?', _s),
  JournalEntryDef('electrolytes', 'Electrolytes', 'Took electrolytes?', _s),
  JournalEntryDef('sleep_aid', 'Sleep aid', 'Took a sleep aid?', _s),
  JournalEntryDef(
    'antihistamine',
    'Antihistamine',
    'Took an antihistamine?',
    _s,
  ),
  JournalEntryDef('painkiller', 'Painkiller', 'Took a painkiller?', _s),
  JournalEntryDef(
    'medication',
    'Medication',
    'Took your usual medication?',
    _s,
  ),
  // Sleep environment.
  JournalEntryDef('own_bed', 'Own bed', 'Slept in your own bed?', _z),
  JournalEntryDef('shared_bed', 'Shared bed', 'Shared the bed?', _z),
  JournalEntryDef('pet_bed', 'Pet in room', 'A pet in the bedroom?', _z),
  JournalEntryDef('noise', 'Noisy night', 'A noisy night?', _z),
  JournalEntryDef('hot_room', 'Warm room', 'A warm bedroom?', _z),
  JournalEntryDef('earplugs', 'Ear plugs', 'Slept with ear plugs?', _z),
  JournalEntryDef('eye_mask', 'Eye mask', 'Slept with an eye mask?', _z),
  JournalEntryDef(
    'blue_light',
    'Blue-light glasses',
    'Wore blue-light glasses?',
    _z,
  ),
  JournalEntryDef('woke_child', 'Woken by a child', 'Woken by a child?', _z),
  JournalEntryDef('alarm', 'Woke to an alarm', 'Woke to an alarm?', _z),
  // Automatic: filled from the day's data, never asked.
  JournalEntryDef('auto_steps', 'Step goal', 'Reached your step goal', _a),
  JournalEntryDef('auto_brisk', '30+ brisk minutes', '30+ brisk minutes', _a),
  JournalEntryDef(
    'auto_zone2',
    '30+ min Zone 2',
    '30+ min at Zone 2 or above',
    _a,
  ),
  JournalEntryDef(
    'auto_strength',
    'Strength session',
    'A strength session',
    _a,
  ),
  JournalEntryDef(
    'auto_late_workout',
    'Late workout',
    'A workout ending within 3 h of sleep',
    _a,
  ),
  JournalEntryDef('auto_nap', 'Nap', 'A nap of 20+ min', _a),
  JournalEntryDef(
    'auto_late_bed',
    'Late to bed',
    'Bed an hour or more late',
    _a,
  ),
  JournalEntryDef('auto_high_strain', 'Hard day', 'Strain of 14 or more', _a),
];

final journalByKey = {for (final e in journalCatalog) e.key: e};

/// A user's own yes/no entry ("custom_<slug>").
JournalEntryDef customEntry(String key, String name) =>
    JournalEntryDef(key, name, '$name?', EntryGroup.lifestyle);

String customKey(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'custom_${slug.isEmpty ? 'entry' : slug}';
}

/// What a day's data says, for the automatic entries.
final class AutoFacts {
  const AutoFacts({
    this.steps,
    this.stepTarget = 8000,
    this.briskMinutes,
    this.zone2Minutes,
    this.strengthDone = false,
    this.lastWorkoutEnd,
    this.sleepStart,
    this.napMinutes,
    this.bedMinute,
    this.usualBedMinute,
    this.strain,
  });
  final int? steps;
  final int stepTarget;
  final int? briskMinutes, zone2Minutes;
  final bool strengthDone;

  /// End of the day's last workout and the start of that night's sleep.
  final DateTime? lastWorkoutEnd, sleepStart;
  final int? napMinutes;

  /// Bedtime that night and the usual one, as minutes after noon so times
  /// past midnight compare correctly (see [minutesAfterNoon]).
  final int? bedMinute, usualBedMinute;
  final double? strain;
}

int minutesAfterNoon(DateTime t) => ((t.hour - 12) % 24) * 60 + t.minute;

/// Automatic entries for one day; an entry is left out when its data is
/// missing (unknown is not "no").
Map<String, bool> autoEntries(AutoFacts f) => {
  if (f.steps != null) 'auto_steps': f.steps! >= f.stepTarget,
  if (f.briskMinutes != null) 'auto_brisk': f.briskMinutes! >= 30,
  if (f.zone2Minutes != null) 'auto_zone2': f.zone2Minutes! >= 30,
  'auto_strength': f.strengthDone,
  if (f.sleepStart != null)
    'auto_late_workout':
        f.lastWorkoutEnd != null &&
        !f.lastWorkoutEnd!.isAfter(f.sleepStart!) &&
        f.sleepStart!.difference(f.lastWorkoutEnd!).inMinutes < 180,
  if (f.napMinutes != null) 'auto_nap': f.napMinutes! >= 20,
  if (f.bedMinute != null && f.usualBedMinute != null)
    'auto_late_bed': f.bedMinute! - f.usualBedMinute! >= 60,
  if (f.strain != null) 'auto_high_strain': f.strain! >= 14,
};

/// Overnight fast in hours: last meal on one day to first meal the next.
/// Null without both, or when it comes out under 0 or over 36 h.
double? overnightFastHours(int? lastMealMinute, int? nextFirstMealMinute) {
  if (lastMealMinute == null || nextFirstMealMinute == null) return null;
  final h = (24 * 60 - lastMealMinute + nextFirstMealMinute) / 60;
  return h <= 0 || h > 36 ? null : h;
}
