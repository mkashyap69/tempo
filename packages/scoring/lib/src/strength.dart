/// Strength: the exercise library, set logs, progression, muscle freshness
/// and the strain a lifting session adds. Pure Dart.
library;

import 'dart:math';

enum Muscle {
  chest,
  back,
  shoulders,
  biceps,
  triceps,
  forearms,
  core,
  glutes,
  quads,
  hamstrings,
  calves,
}

const lowerMuscles = {
  Muscle.glutes,
  Muscle.quads,
  Muscle.hamstrings,
  Muscle.calves,
};
const upperMuscles = {
  Muscle.chest,
  Muscle.back,
  Muscle.shoulders,
  Muscle.biceps,
  Muscle.triceps,
};

enum Equipment {
  barbell,
  dumbbell,
  kettlebell,
  machine,
  cable,
  bodyweight,
  band,
  other,
}

/// How a set is counted: load × reps, reps only, or seconds held.
enum SetKind { weighted, reps, timed }

final class ExerciseDef {
  const ExerciseDef(
    this.id,
    this.name,
    this.primary,
    this.equipment, {
    this.secondary = const [],
    this.kind = SetKind.weighted,
    this.home,
    this.aliases = const [],
  });

  /// Stored in `strength_sets.exercise`; never renamed once shipped.
  final String id;
  final String name;
  final List<Muscle> primary, secondary;
  final Equipment equipment;
  final SetKind kind;

  /// Library id of the at-home version.
  final String? home;

  /// Other names the picks or a user may use.
  final List<String> aliases;

  /// Smallest load step: 2.5 kg on a bar (1.25 a side), 2 kg dumbbells,
  /// 4 kg kettlebells, 5 kg on a stack.
  double get stepKg => switch (equipment) {
    Equipment.barbell => 2.5,
    Equipment.dumbbell => 2,
    Equipment.kettlebell => 4,
    Equipment.machine || Equipment.cable => 5,
    _ => 2.5,
  };

  bool get lower => primary.any(lowerMuscles.contains);
}

const _ch = Muscle.chest,
    _bk = Muscle.back,
    _sh = Muscle.shoulders,
    _bi = Muscle.biceps,
    _tr = Muscle.triceps,
    _fa = Muscle.forearms,
    _co = Muscle.core,
    _gl = Muscle.glutes,
    _qu = Muscle.quads,
    _hm = Muscle.hamstrings,
    _ca = Muscle.calves;
const _bb = Equipment.barbell,
    _db = Equipment.dumbbell,
    _kb = Equipment.kettlebell,
    _mc = Equipment.machine,
    _cb = Equipment.cable,
    _bw = Equipment.bodyweight,
    _bd = Equipment.band,
    _ot = Equipment.other;
const _r = SetKind.reps, _t = SetKind.timed;

/// The bundled library. Names and cues are Tempo's own.
const exerciseLibrary = <ExerciseDef>[
  // Squat and lunge.
  ExerciseDef(
    'back_squat',
    'Back squat',
    [_qu, _gl],
    _bb,
    secondary: [_hm, _co],
    home: 'goblet_squat',
  ),
  ExerciseDef(
    'front_squat',
    'Front squat',
    [_qu],
    _bb,
    secondary: [_gl, _co],
    home: 'goblet_squat',
  ),
  ExerciseDef(
    'goblet_squat',
    'Goblet squat',
    [_qu, _gl],
    _db,
    secondary: [_co],
    home: 'bodyweight_squat',
    aliases: ['Goblet squat holding a backpack'],
  ),
  ExerciseDef(
    'bodyweight_squat',
    'Bodyweight squat',
    [_qu, _gl],
    _bw,
    kind: _r,
    aliases: ['Bodyweight squat, slow down'],
  ),
  ExerciseDef(
    'box_squat',
    'Box squat',
    [_qu, _gl],
    _bb,
    secondary: [_hm],
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'hack_squat',
    'Hack squat',
    [_qu],
    _mc,
    secondary: [_gl],
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'leg_press',
    'Leg press',
    [_qu, _gl],
    _mc,
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'bulgarian_split_squat',
    'Bulgarian split squat',
    [_qu, _gl],
    _db,
    secondary: [_hm],
    home: 'split_squat',
  ),
  ExerciseDef('split_squat', 'Split squat', [_qu, _gl], _bw, kind: _r),
  ExerciseDef(
    'walking_lunge',
    'Walking lunge',
    [_qu, _gl],
    _db,
    secondary: [_hm],
    home: 'reverse_lunge',
  ),
  ExerciseDef(
    'reverse_lunge',
    'Reverse lunge',
    [_qu, _gl],
    _db,
    home: 'split_squat',
  ),
  ExerciseDef(
    'lateral_lunge',
    'Lateral lunge',
    [_qu, _gl],
    _db,
    home: 'split_squat',
  ),
  ExerciseDef('step_up', 'Step-up', [_qu, _gl], _db, home: 'split_squat'),
  ExerciseDef(
    'pistol_squat',
    'Pistol squat',
    [_qu, _gl],
    _bw,
    kind: _r,
    secondary: [_co],
  ),
  ExerciseDef('wall_sit', 'Wall sit', [_qu], _bw, kind: _t),
  ExerciseDef(
    'leg_extension',
    'Leg extension',
    [_qu],
    _mc,
    home: 'split_squat',
  ),
  ExerciseDef('sissy_squat', 'Sissy squat', [_qu], _bw, kind: _r),
  ExerciseDef(
    'jump_squat',
    'Jump squat',
    [_qu, _gl],
    _bw,
    kind: _r,
    secondary: [_ca],
  ),
  ExerciseDef(
    'box_jump',
    'Box jump',
    [_qu, _gl],
    _bw,
    kind: _r,
    secondary: [_ca],
  ),
  // Hinge.
  ExerciseDef(
    'deadlift',
    'Deadlift',
    [_hm, _gl, _bk],
    _bb,
    secondary: [_qu, _fa, _co],
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'romanian_deadlift',
    'Romanian deadlift',
    [_hm, _gl],
    _bb,
    secondary: [_bk],
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'sumo_deadlift',
    'Sumo deadlift',
    [_gl, _hm, _qu],
    _bb,
    secondary: [_bk],
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'trap_bar_deadlift',
    'Trap bar deadlift',
    [_qu, _gl, _hm],
    _bb,
    secondary: [_bk],
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'dumbbell_rdl',
    'Dumbbell Romanian deadlift',
    [_hm, _gl],
    _db,
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'single_leg_rdl',
    'Single-leg RDL',
    [_hm, _gl],
    _db,
    secondary: [_co],
  ),
  ExerciseDef(
    'good_morning',
    'Good morning',
    [_hm],
    _bb,
    secondary: [_bk, _gl],
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'kettlebell_swing',
    'Kettlebell swing',
    [_gl, _hm],
    _kb,
    secondary: [_co, _bk],
    home: 'glute_bridge',
  ),
  ExerciseDef(
    'hip_thrust',
    'Hip thrust',
    [_gl],
    _bb,
    secondary: [_hm],
    home: 'glute_bridge',
  ),
  ExerciseDef(
    'glute_bridge',
    'Glute bridge',
    [_gl],
    _bw,
    kind: _r,
    secondary: [_hm],
  ),
  ExerciseDef(
    'single_leg_bridge',
    'Single-leg glute bridge',
    [_gl],
    _bw,
    kind: _r,
    secondary: [_hm],
  ),
  ExerciseDef('leg_curl', 'Leg curl', [_hm], _mc, home: 'sliding_leg_curl'),
  ExerciseDef('nordic_curl', 'Nordic curl', [_hm], _bw, kind: _r),
  ExerciseDef(
    'sliding_leg_curl',
    'Sliding leg curl',
    [_hm],
    _bw,
    kind: _r,
    secondary: [_gl],
  ),
  ExerciseDef(
    'back_extension',
    'Back extension',
    [_bk, _gl],
    _mc,
    secondary: [_hm],
    home: 'superman',
  ),
  ExerciseDef(
    'superman',
    'Superman hold',
    [_bk],
    _bw,
    kind: _t,
    secondary: [_gl],
  ),
  ExerciseDef(
    'hip_abduction',
    'Hip abduction',
    [_gl],
    _mc,
    home: 'banded_side_walk',
  ),
  ExerciseDef('banded_side_walk', 'Banded side walk', [_gl], _bd, kind: _r),
  ExerciseDef(
    'cable_pull_through',
    'Cable pull-through',
    [_gl, _hm],
    _cb,
    home: 'glute_bridge',
  ),
  // Calves.
  ExerciseDef(
    'calf_raise',
    'Calf raise',
    [_ca],
    _mc,
    home: 'single_leg_calf_raise',
    aliases: ['Standing calf raise'],
  ),
  ExerciseDef(
    'single_leg_calf_raise',
    'Single-leg calf raise',
    [_ca],
    _bw,
    kind: _r,
    aliases: ['Single-leg calf raise on a step'],
  ),
  ExerciseDef(
    'seated_calf_raise',
    'Seated calf raise',
    [_ca],
    _mc,
    home: 'single_leg_calf_raise',
  ),
  // Horizontal push.
  ExerciseDef(
    'bench_press',
    'Bench press',
    [_ch],
    _bb,
    secondary: [_tr, _sh],
    home: 'push_up',
    aliases: ['Push-up or bench press'],
  ),
  ExerciseDef(
    'incline_bench_press',
    'Incline bench press',
    [_ch, _sh],
    _bb,
    secondary: [_tr],
    home: 'push_up',
  ),
  ExerciseDef(
    'dumbbell_bench_press',
    'Dumbbell bench press',
    [_ch],
    _db,
    secondary: [_tr, _sh],
    home: 'push_up',
  ),
  ExerciseDef(
    'incline_dumbbell_press',
    'Incline dumbbell press',
    [_ch, _sh],
    _db,
    secondary: [_tr],
    home: 'push_up',
  ),
  ExerciseDef(
    'close_grip_bench',
    'Close-grip bench press',
    [_tr, _ch],
    _bb,
    home: 'diamond_push_up',
  ),
  ExerciseDef(
    'push_up',
    'Push-up',
    [_ch],
    _bw,
    kind: _r,
    secondary: [_tr, _sh, _co],
    aliases: ['Push-up (feet raised if easy)'],
  ),
  ExerciseDef(
    'incline_push_up',
    'Incline push-up',
    [_ch],
    _bw,
    kind: _r,
    secondary: [_tr],
  ),
  ExerciseDef('diamond_push_up', 'Diamond push-up', [_tr, _ch], _bw, kind: _r),
  ExerciseDef('chest_dip', 'Dip', [_ch, _tr], _bw, kind: _r, secondary: [_sh]),
  ExerciseDef(
    'chest_press_machine',
    'Chest press machine',
    [_ch],
    _mc,
    secondary: [_tr],
    home: 'push_up',
  ),
  ExerciseDef('cable_fly', 'Cable fly', [_ch], _cb, home: 'push_up'),
  ExerciseDef('dumbbell_fly', 'Dumbbell fly', [_ch], _db, home: 'push_up'),
  ExerciseDef('pec_deck', 'Pec deck', [_ch], _mc, home: 'push_up'),
  // Vertical push.
  ExerciseDef(
    'overhead_press',
    'Overhead press',
    [_sh],
    _bb,
    secondary: [_tr, _co],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'dumbbell_shoulder_press',
    'Dumbbell shoulder press',
    [_sh],
    _db,
    secondary: [_tr],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'arnold_press',
    'Arnold press',
    [_sh],
    _db,
    secondary: [_tr],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'push_press',
    'Push press',
    [_sh],
    _bb,
    secondary: [_tr, _qu],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'landmine_press',
    'Landmine press',
    [_sh, _ch],
    _bb,
    secondary: [_tr, _co],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'pike_push_up',
    'Pike push-up',
    [_sh],
    _bw,
    kind: _r,
    secondary: [_tr],
  ),
  ExerciseDef(
    'handstand_push_up',
    'Handstand push-up',
    [_sh, _tr],
    _bw,
    kind: _r,
  ),
  ExerciseDef(
    'lateral_raise',
    'Lateral raise',
    [_sh],
    _db,
    home: 'band_lateral_raise',
  ),
  ExerciseDef('band_lateral_raise', 'Band lateral raise', [_sh], _bd, kind: _r),
  ExerciseDef(
    'front_raise',
    'Front raise',
    [_sh],
    _db,
    home: 'band_lateral_raise',
  ),
  ExerciseDef(
    'rear_delt_fly',
    'Rear delt fly',
    [_sh, _bk],
    _db,
    home: 'band_pull_apart',
    aliases: ['Reverse fly'],
  ),
  ExerciseDef(
    'upright_row',
    'Upright row',
    [_sh],
    _bb,
    secondary: [_bk],
    home: 'band_lateral_raise',
  ),
  ExerciseDef(
    'shoulder_press_machine',
    'Shoulder press machine',
    [_sh],
    _mc,
    secondary: [_tr],
    home: 'pike_push_up',
  ),
  // Pull.
  ExerciseDef(
    'bent_over_row',
    'Bent-over row',
    [_bk],
    _bb,
    secondary: [_bi, _sh],
    home: 'backpack_row',
  ),
  ExerciseDef(
    'dumbbell_row',
    'One-arm dumbbell row',
    [_bk],
    _db,
    secondary: [_bi],
    home: 'backpack_row',
  ),
  ExerciseDef('backpack_row', 'Backpack row', [_bk], _ot, secondary: [_bi]),
  ExerciseDef(
    'seated_cable_row',
    'Seated cable row',
    [_bk],
    _cb,
    secondary: [_bi],
    home: 'towel_row',
  ),
  ExerciseDef(
    'chest_supported_row',
    'Chest-supported row',
    [_bk],
    _db,
    secondary: [_bi],
    home: 'backpack_row',
  ),
  ExerciseDef(
    't_bar_row',
    'T-bar row',
    [_bk],
    _bb,
    secondary: [_bi],
    home: 'backpack_row',
  ),
  ExerciseDef(
    'inverted_row',
    'Inverted row',
    [_bk],
    _bw,
    kind: _r,
    secondary: [_bi],
  ),
  ExerciseDef(
    'towel_row',
    'Towel row on a door',
    [_bk],
    _ot,
    kind: _r,
    secondary: [_bi],
  ),
  ExerciseDef(
    'pull_up',
    'Pull-up',
    [_bk],
    _bw,
    kind: _r,
    secondary: [_bi],
    home: 'towel_row',
  ),
  ExerciseDef(
    'chin_up',
    'Chin-up',
    [_bk, _bi],
    _bw,
    kind: _r,
    home: 'towel_row',
  ),
  ExerciseDef(
    'lat_pulldown',
    'Lat pulldown',
    [_bk],
    _cb,
    secondary: [_bi],
    home: 'towel_row',
    aliases: ['Lat pulldown or pull-up'],
  ),
  ExerciseDef(
    'assisted_pull_up',
    'Assisted pull-up',
    [_bk],
    _mc,
    secondary: [_bi],
    home: 'towel_row',
  ),
  ExerciseDef(
    'straight_arm_pulldown',
    'Straight-arm pulldown',
    [_bk],
    _cb,
    home: 'band_pull_apart',
  ),
  ExerciseDef(
    'face_pull',
    'Face pull',
    [_sh, _bk],
    _cb,
    home: 'band_pull_apart',
  ),
  ExerciseDef(
    'band_pull_apart',
    'Band pull-apart',
    [_sh, _bk],
    _bd,
    kind: _r,
    aliases: ['Band pull-apart or reverse fly'],
  ),
  ExerciseDef(
    'shrug',
    'Shrug',
    [_bk],
    _db,
    secondary: [_fa],
    home: 'farmer_carry',
  ),
  ExerciseDef(
    'pullover',
    'Dumbbell pullover',
    [_bk, _ch],
    _db,
    home: 'towel_row',
  ),
  // Arms.
  ExerciseDef(
    'barbell_curl',
    'Barbell curl',
    [_bi],
    _bb,
    secondary: [_fa],
    home: 'band_curl',
  ),
  ExerciseDef(
    'dumbbell_curl',
    'Dumbbell curl',
    [_bi],
    _db,
    secondary: [_fa],
    home: 'band_curl',
  ),
  ExerciseDef('hammer_curl', 'Hammer curl', [_bi, _fa], _db, home: 'band_curl'),
  ExerciseDef(
    'incline_curl',
    'Incline dumbbell curl',
    [_bi],
    _db,
    home: 'band_curl',
  ),
  ExerciseDef('cable_curl', 'Cable curl', [_bi], _cb, home: 'band_curl'),
  ExerciseDef('preacher_curl', 'Preacher curl', [_bi], _mc, home: 'band_curl'),
  ExerciseDef('band_curl', 'Band curl', [_bi], _bd, kind: _r),
  ExerciseDef(
    'triceps_pushdown',
    'Triceps pushdown',
    [_tr],
    _cb,
    home: 'bench_dip',
  ),
  ExerciseDef(
    'overhead_triceps_extension',
    'Overhead triceps extension',
    [_tr],
    _db,
    home: 'bench_dip',
  ),
  ExerciseDef(
    'skull_crusher',
    'Skull crusher',
    [_tr],
    _bb,
    home: 'diamond_push_up',
  ),
  ExerciseDef('bench_dip', 'Bench dip', [_tr], _bw, kind: _r, secondary: [_ch]),
  ExerciseDef('wrist_curl', 'Wrist curl', [_fa], _db, home: 'dead_hang'),
  ExerciseDef('dead_hang', 'Dead hang', [_fa, _bk], _bw, kind: _t),
  // Carries and full body.
  ExerciseDef(
    'farmer_carry',
    'Farmer carry',
    [_fa, _co],
    _db,
    secondary: [_bk, _gl],
    kind: _t,
    home: 'suitcase_carry',
    aliases: ['Carry two heavy bags'],
  ),
  ExerciseDef('suitcase_carry', 'Suitcase carry', [_co, _fa], _db, kind: _t),
  ExerciseDef(
    'clean',
    'Power clean',
    [_gl, _hm, _bk],
    _bb,
    secondary: [_qu, _sh],
    home: 'kettlebell_swing',
  ),
  ExerciseDef(
    'thruster',
    'Thruster',
    [_qu, _sh],
    _db,
    secondary: [_gl, _tr],
    home: 'jump_squat',
  ),
  ExerciseDef(
    'kettlebell_snatch',
    'Kettlebell snatch',
    [_gl, _sh],
    _kb,
    secondary: [_hm, _bk],
  ),
  ExerciseDef(
    'turkish_get_up',
    'Turkish get-up',
    [_sh, _co],
    _kb,
    secondary: [_gl],
  ),
  ExerciseDef(
    'burpee',
    'Burpee',
    [_qu, _ch],
    _bw,
    kind: _r,
    secondary: [_co, _sh],
  ),
  ExerciseDef(
    'sled_push',
    'Sled push',
    [_qu, _gl],
    _ot,
    kind: _t,
    secondary: [_ca],
  ),
  ExerciseDef(
    'battle_ropes',
    'Battle ropes',
    [_sh],
    _ot,
    kind: _t,
    secondary: [_co],
  ),
  ExerciseDef(
    'wall_ball',
    'Wall ball',
    [_qu, _sh],
    _ot,
    kind: _r,
    secondary: [_gl],
  ),
  ExerciseDef('man_maker', 'Man maker', [_ch, _qu], _db, secondary: [_sh, _bk]),
  // Core.
  ExerciseDef('plank', 'Plank', [_co], _bw, kind: _t),
  ExerciseDef('side_plank', 'Side plank', [_co], _bw, kind: _t),
  ExerciseDef('dead_bug', 'Dead bug', [_co], _bw, kind: _r),
  ExerciseDef('bird_dog', 'Bird dog', [_co], _bw, kind: _r, secondary: [_gl]),
  ExerciseDef('hollow_hold', 'Hollow hold', [_co], _bw, kind: _t),
  ExerciseDef('pallof_press', 'Pallof press', [_co], _cb, home: 'side_plank'),
  ExerciseDef('ab_wheel', 'Ab wheel rollout', [_co], _ot, kind: _r),
  ExerciseDef(
    'hanging_leg_raise',
    'Hanging leg raise',
    [_co],
    _bw,
    kind: _r,
    secondary: [_fa],
  ),
  ExerciseDef('lying_leg_raise', 'Lying leg raise', [_co], _bw, kind: _r),
  ExerciseDef('cable_crunch', 'Cable crunch', [_co], _cb, home: 'crunch'),
  ExerciseDef('crunch', 'Crunch', [_co], _bw, kind: _r),
  ExerciseDef('russian_twist', 'Russian twist', [_co], _bw, kind: _r),
  ExerciseDef(
    'mountain_climber',
    'Mountain climber',
    [_co],
    _bw,
    kind: _t,
    secondary: [_sh, _qu],
  ),
  ExerciseDef('woodchop', 'Cable woodchop', [_co], _cb, home: 'russian_twist'),
  ExerciseDef(
    'copenhagen_plank',
    'Copenhagen plank',
    [_co],
    _bw,
    kind: _t,
    secondary: [_gl],
  ),
  ExerciseDef(
    'bear_crawl',
    'Bear crawl',
    [_co, _sh],
    _bw,
    kind: _t,
    secondary: [_qu],
  ),
  ExerciseDef('v_up', 'V-up', [_co], _bw, kind: _r),
  ExerciseDef('stir_the_pot', 'Stir the pot', [_co], _ot, kind: _r),
  // Mobility and stretches (logged, never progressed).
  ExerciseDef('hip_flexor_stretch', 'Hip flexor stretch', [_gl], _bw, kind: _t),
  ExerciseDef('thoracic_rotation', 'Thoracic rotation', [_bk], _bw, kind: _r),
  ExerciseDef(
    'worlds_greatest_stretch',
    'World’s greatest stretch',
    [_gl, _hm],
    _bw,
    kind: _r,
  ),
  ExerciseDef('cat_cow', 'Cat-cow', [_bk, _co], _bw, kind: _r),
  ExerciseDef('ninety_ninety', '90/90 hip switch', [_gl], _bw, kind: _r),
  ExerciseDef('couch_stretch', 'Couch stretch', [_qu], _bw, kind: _t),
  ExerciseDef('hamstring_stretch', 'Hamstring stretch', [_hm], _bw, kind: _t),
  ExerciseDef(
    'ankle_mobility',
    'Knee-to-wall ankle rock',
    [_ca],
    _bw,
    kind: _r,
  ),
  ExerciseDef(
    'shoulder_dislocate',
    'Band shoulder pass-through',
    [_sh],
    _bd,
    kind: _r,
  ),
  ExerciseDef('deep_squat_hold', 'Deep squat hold', [_qu, _gl], _bw, kind: _t),
  ExerciseDef('scap_push_up', 'Scapular push-up', [_sh, _ch], _bw, kind: _r),
  ExerciseDef('wall_slide', 'Wall slide', [_sh], _bw, kind: _r),
  ExerciseDef('foam_roll', 'Foam rolling', [_qu, _hm], _ot, kind: _t),
  // More machines and variations.
  ExerciseDef(
    'smith_squat',
    'Smith machine squat',
    [_qu, _gl],
    _mc,
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'belt_squat',
    'Belt squat',
    [_qu, _gl],
    _mc,
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'reverse_hyper',
    'Reverse hyperextension',
    [_gl, _hm],
    _mc,
    home: 'superman',
  ),
  ExerciseDef(
    'glute_kickback',
    'Cable glute kickback',
    [_gl],
    _cb,
    home: 'single_leg_bridge',
  ),
  ExerciseDef(
    'seated_leg_curl',
    'Seated leg curl',
    [_hm],
    _mc,
    home: 'sliding_leg_curl',
  ),
  ExerciseDef(
    'machine_row',
    'Machine row',
    [_bk],
    _mc,
    secondary: [_bi],
    home: 'backpack_row',
  ),
  ExerciseDef(
    'incline_cable_fly',
    'Incline cable fly',
    [_ch, _sh],
    _cb,
    home: 'incline_push_up',
  ),
  ExerciseDef(
    'decline_push_up',
    'Decline push-up',
    [_ch, _sh],
    _bw,
    kind: _r,
    secondary: [_tr],
  ),
  ExerciseDef(
    'zercher_squat',
    'Zercher squat',
    [_qu, _gl],
    _bb,
    secondary: [_co, _bk],
    home: 'goblet_squat',
  ),
  ExerciseDef(
    'kettlebell_goblet_squat',
    'Kettlebell goblet squat',
    [_qu, _gl],
    _kb,
    home: 'bodyweight_squat',
  ),
  ExerciseDef(
    'kettlebell_deadlift',
    'Kettlebell deadlift',
    [_hm, _gl],
    _kb,
    home: 'single_leg_rdl',
  ),
  ExerciseDef(
    'kettlebell_press',
    'Kettlebell press',
    [_sh],
    _kb,
    secondary: [_tr],
    home: 'pike_push_up',
  ),
  ExerciseDef(
    'kettlebell_row',
    'Kettlebell row',
    [_bk],
    _kb,
    secondary: [_bi],
    home: 'backpack_row',
  ),
  ExerciseDef('band_row', 'Band row', [_bk], _bd, kind: _r, secondary: [_bi]),
  ExerciseDef(
    'band_press',
    'Band chest press',
    [_ch],
    _bd,
    kind: _r,
    secondary: [_tr],
  ),
  ExerciseDef('band_squat', 'Band squat', [_qu, _gl], _bd, kind: _r),
];

final exerciseById = {for (final e in exerciseLibrary) e.id: e};

final _byName = {
  for (final e in exerciseLibrary) ...{
    e.name.toLowerCase(): e,
    for (final a in e.aliases) a.toLowerCase(): e,
  },
};

/// The library entry for a name the picks or a user used, or null.
ExerciseDef? exerciseByName(String name) => _byName[name.toLowerCase().trim()];

// ---- set logs ----------------------------------------------------------------

/// One logged set.
final class SetLog {
  const SetLog({
    required this.exercise,
    required this.at,
    this.kg = 0,
    this.reps = 0,
    this.seconds = 0,
    this.rir,
  });
  final String exercise;
  final DateTime at;
  final double kg;
  final int reps, seconds;

  /// Reps in reserve (0 = failure); null when not rated.
  final int? rir;

  double get volume => kg * reps;

  /// Hard set: within 3 reps of failure (or unrated, which most are).
  bool get hard => rir == null || rir! <= 3;
}

/// Epley estimated one-rep max; null for sets over 10 reps or without
/// load, where the estimate drifts.
double? e1rm(double kg, int reps) {
  if (kg <= 0 || reps <= 0 || reps > 10) return null;
  return reps == 1 ? kg : kg * (1 + reps / 30);
}

/// One session's sets of one exercise, oldest first.
final class ExerciseSession {
  const ExerciseSession(this.day, this.sets);
  final DateTime day;
  final List<SetLog> sets;

  double get topKg => sets.fold(0, (a, s) => max(a, s.kg));
  double get volume => sets.fold(0, (a, s) => a + s.volume);
  double? get bestE1rm => sets
      .map((s) => e1rm(s.kg, s.reps))
      .whereType<double>()
      .fold<double?>(null, (a, v) => a == null || v > a ? v : a);
}

/// Sessions of [exercise] from [sets], one per day, oldest first.
List<ExerciseSession> sessionsOf(String exercise, Iterable<SetLog> sets) {
  final byDay = <DateTime, List<SetLog>>{};
  for (final s in sets) {
    if (s.exercise != exercise) continue;
    final d = DateTime(s.at.year, s.at.month, s.at.day);
    byDay.putIfAbsent(d, () => []).add(s);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days)
      ExerciseSession(d, byDay[d]!..sort((a, b) => a.at.compareTo(b.at))),
  ];
}

// ---- progression ----------------------------------------------------------------

/// "8–12" → (8, 12); "5" → (5, 5); timed or unknown → null.
(int, int)? parseRepRange(String reps) {
  final m = RegExp(r'^\s*(\d+)\s*(?:[–-]\s*(\d+))?\s*$').firstMatch(reps);
  if (m == null) return null;
  final lo = int.parse(m.group(1)!);
  final hi = m.group(2) == null ? lo : int.parse(m.group(2)!);
  return (min(lo, hi), max(lo, hi));
}

/// How today's readiness shapes the numbers.
enum LiftDay {
  /// As planned.
  normal,

  /// Low recovery or a hard day behind you: same weight, one set fewer.
  hold,

  /// The lighter week of a training block: same weight, ~40 % fewer sets.
  lighter,
}

final class LiftTarget {
  const LiftTarget({
    required this.kg,
    required this.reps,
    required this.sets,
    required this.why,
  });
  final double kg;
  final int reps, sets;

  /// "Up 2.5 kg: you hit 12 on every set last time."
  final String why;
}

/// Double progression. Hit the top of the range on every working set
/// with a rep or more to spare → add the smallest step and drop to the
/// bottom of the range. Miss the bottom twice in a row → hold; three
/// times → take 10 % off. Otherwise keep the weight and aim one rep
/// higher. Null when there's no weighted history to go on.
LiftTarget? nextTarget(
  ExerciseDef e,
  List<ExerciseSession> history, {
  required (int, int) range,
  required int sets,
  LiftDay day = LiftDay.normal,
}) {
  final weighted = [
    for (final h in history)
      if (h.topKg > 0) h,
  ];
  if (weighted.isEmpty || e.kind != SetKind.weighted) return null;
  final last = weighted.last;
  final (lo, hi) = range;
  final working = [
    for (final s in last.sets)
      if (s.kg >= last.topKg * .9) s,
  ];
  bool missed(ExerciseSession s) {
    final w = [
      for (final x in s.sets)
        if (x.kg >= s.topKg * .9) x,
    ];
    return w.any((x) => x.reps < lo);
  }

  final misses = weighted.reversed.takeWhile(missed).length;
  var kg = last.topKg;
  var reps = lo;
  String why;
  final allTop =
      working.isNotEmpty &&
      working.every((s) => s.reps >= hi && (s.rir == null || s.rir! >= 1));
  if (misses >= 3) {
    kg = _round(kg * .9, e.stepKg);
    why = 'Down 10 %: the bottom of the range was missed three times.';
  } else if (misses == 2) {
    why = 'Same weight: two sessions short of $lo reps.';
  } else if (allTop) {
    kg = kg + e.stepKg;
    why = 'Up ${_kg(e.stepKg)}: you hit $hi on every set last time.';
  } else {
    final best = working.isEmpty ? lo : working.map((s) => s.reps).reduce(min);
    reps = (best + 1).clamp(lo, hi);
    why = 'Same weight, aim for $reps reps.';
  }
  var n = sets;
  switch (day) {
    case LiftDay.normal:
      break;
    case LiftDay.hold:
      if (kg > last.topKg) kg = last.topKg;
      n = max(1, sets - 1);
      why = 'Same weight, one set fewer: recovery is low today.';
    case LiftDay.lighter:
      if (kg > last.topKg) kg = last.topKg;
      n = max(1, (sets * .6).round());
      why = 'Lighter week: same weight, fewer sets.';
  }
  return LiftTarget(kg: kg, reps: reps, sets: n, why: why);
}

double _round(double kg, double step) =>
    max(step, (kg / step).roundToDouble() * step);

String _kg(double kg) => kg == kg.roundToDouble()
    ? '${kg.round()} kg'
    : '${kg.toStringAsFixed(1)} kg';

// ---- muscle freshness ----------------------------------------------------------

/// Hours for a muscle's load to halve.
const freshnessHalfLifeHours = 48.0;

/// Load (in hard sets) that takes a muscle to ~37 % fresh.
const freshnessScale = 6.0;

/// A run or ride as leg load, for freshness.
final class LegCardio {
  const LegCardio({
    required this.at,
    required this.minutes,
    this.hard = false,
    this.running = true,
  });
  final DateTime at;
  final int minutes;
  final bool hard, running;
}

/// Load per muscle at [now], in decayed hard-set units: a primary muscle
/// takes a whole set, a secondary half. Runs add leg load (a set per 15
/// easy minutes or 8 hard ones; rides count half and spare the calves).
Map<Muscle, double> muscleLoad(
  Iterable<SetLog> sets,
  DateTime now, {
  Iterable<LegCardio> cardio = const [],
}) {
  final out = {for (final m in Muscle.values) m: 0.0};
  double decay(DateTime t) {
    final h = now.difference(t).inMinutes / 60;
    return h < 0 ? 1 : pow(.5, h / freshnessHalfLifeHours).toDouble();
  }

  for (final s in sets) {
    if (!s.hard) continue;
    final e = exerciseById[s.exercise];
    if (e == null) continue;
    final d = decay(s.at);
    for (final m in e.primary) {
      out[m] = out[m]! + d;
    }
    for (final m in e.secondary) {
      out[m] = out[m]! + .5 * d;
    }
  }
  for (final c in cardio) {
    final per = c.hard ? 8 : 15;
    final units = c.minutes / per * (c.running ? 1 : .5) * decay(c.at);
    for (final m in [Muscle.quads, Muscle.hamstrings, Muscle.glutes]) {
      out[m] = out[m]! + units * .6;
    }
    if (c.running) out[Muscle.calves] = out[Muscle.calves]! + units;
  }
  return out;
}

/// 0–100: how recovered each muscle is (100 = no recent load).
Map<Muscle, double> freshness(Map<Muscle, double> load) => {
  for (final e in load.entries) e.key: 100 * exp(-e.value / freshnessScale),
};

double _mean(Map<Muscle, double> f, Set<Muscle> ms) =>
    ms.map((m) => f[m] ?? 100).reduce((a, b) => a + b) / ms.length;

double lowerFreshness(Map<Muscle, double> f) => _mean(f, lowerMuscles);
double upperFreshness(Map<Muscle, double> f) => _mean(f, upperMuscles);

// ---- strain -----------------------------------------------------------------------

/// TRIMP per hard set, scaled by how close to failure it went (starting
/// value to calibrate against session RPE).
double setTrimp(SetLog s) {
  if (!s.hard) return 0;
  final close = switch (s.rir) {
    null => 1.0,
    0 => 1.3,
    1 => 1.15,
    2 => 1.0,
    _ => .75,
  };
  // Heavier work (fewer reps) taxes more per set than long light sets:
  // session RPE runs higher for low-rep, high-load work at equal volume
  // (Day 2004). 6–12 reps is the reference (algo 10; starting values to
  // fit against logged sRPE in the T1 lifting check).
  final timed = s.reps == 0 && s.seconds > 0;
  final heavy = timed
      ? .6
      : s.reps <= 5
      ? 1.15
      : s.reps > 12
      ? .85
      : 1.0;
  return heavy * close * 1.6;
}

/// Load of a logged lifting session in TRIMP units.
double trimpFromSets(Iterable<SetLog> sets) =>
    sets.fold(0, (a, s) => a + setTrimp(s));
