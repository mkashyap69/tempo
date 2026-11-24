import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import 'body.dart' show loadWeightTrend;
import 'data_source.dart';
import 'food.dart' show loadSavedFood;
import 'format.dart' show grouped, hmSpaced;
import 'health_sync.dart'
    show SourceMetric, metricSource, sourceLabel, sourceNames;
import 'limit.dart' show limitOn;
import 'profile.dart';
import 'today.dart';

/// Where an input the plan and scores use came from (D2).
enum Origin {
  /// You told Tempo (onboarding or You).
  you('You set'),

  /// Measured from your data.
  measured('Measured'),

  /// Worked out from other inputs (a formula, your usual).
  estimated('Estimated'),

  /// Tempo's default, until you or your data say otherwise.
  standard('Default'),

  /// Not enough data yet.
  learning('Learning');

  const Origin(this.label);
  final String label;
}

/// One line on the "What Tempo uses" page.
final class Input {
  const Input(this.text, this.origin, this.how, {this.editable = false});

  /// The fact, as a sentence.
  final String text;
  final Origin origin;

  /// Where it came from, or what would firm it up.
  final String how;

  /// You can change it in You.
  final bool editable;
}

typedef InputGroup = ({String title, List<Input> items});

String _hm(int m) => fmtHm(m);

/// Every input the plan and the scores use, grouped, with its origin.
Future<List<InputGroup>> whatTempoUses(st.TempoDb db, TodayData t) async {
  final p = t.profile;
  final source = await loadDataSource(db);
  final trend = await loadWeightTrend(db);
  final food = await loadSavedFood(db);
  final limit = await limitOn(db, DateTime.now());
  final slot = await db.setting(Keys.coachSlot);
  final wakeSet = (await db.setting(Keys.wakeTime) ?? '').isNotEmpty;
  final estimate = sc.maxHrFromAge(p.age);
  final names = source.isHealth
      ? await sourceNames(db)
      : const <String, String>{};

  final hrMax = t.hrMax;
  final Input maxHr = p.maxHr != null
      ? Input(
          'Max heart rate $hrMax bpm',
          Origin.you,
          'From You → Max heart rate',
          editable: true,
        )
      : hrMax > estimate
      ? Input(
          'Max heart rate $hrMax bpm',
          Origin.measured,
          'The highest your data has shown; above the $estimate bpm your age predicts',
        )
      : Input(
          'Max heart rate $hrMax bpm',
          Origin.estimated,
          'From your age (208 − 0.7 × age). A hard effort or a value you know would firm it up',
          editable: true,
        );

  final rhr = t.rhrBase;
  final hrv = t.hrvBase;
  final sources = <Input>[
    Input(
      'Data from ${source.label}',
      Origin.you,
      source.isHealth
          ? 'Read only; Tempo never writes back what it read'
          : 'Read straight from the band over Bluetooth',
    ),
    if (source.isHealth)
      for (final (m, name) in [
        (SourceMetric.sleep, 'Sleep'),
        (SourceMetric.heartRate, 'Heart rate'),
        (SourceMetric.steps, 'Steps'),
        (SourceMetric.hrv, 'HRV'),
      ])
        switch (await metricSource(db, m)) {
          final id? => Input(
            '$name from ${sourceLabel(id, names)}',
            Origin.you,
            'Chosen in You → Data sources',
            editable: true,
          ),
          null => Input(
            '$name from every app, merged',
            Origin.standard,
            'Pick one app in You → Data sources if two disagree',
            editable: true,
          ),
        },
  ];

  return [
    (
      title: 'Goal and training',
      items: [
        Input(
          'Priority: ${goalLabel(p.goal).toLowerCase()}',
          Origin.you,
          'From onboarding or You → Priority',
          editable: true,
        ),
        Input(
          'Trains ${p.days.length} days a week, up to ${p.maxMinutes} min',
          Origin.you,
          'You → Availability',
          editable: true,
        ),
        if (p.longDay != null ||
            p.liftDays.isNotEmpty ||
            p.hardSessions != null)
          const Input(
            'Week template set',
            Origin.you,
            'You → Week template',
            editable: true,
          )
        else
          const Input(
            'Long day, lifting days and hard sessions: Tempo’s choice',
            Origin.standard,
            'Set them in You → Week template',
            editable: true,
          ),
        switch (slot) {
          'am' => const Input(
            'Trains in the morning',
            Origin.you,
            'You → Tempo Coach → Training time',
            editable: true,
          ),
          'pm' => const Input(
            'Trains in the evening',
            Origin.you,
            'You → Tempo Coach → Training time',
            editable: true,
          ),
          'flex' => const Input(
            'Trains any time',
            Origin.you,
            'You → Tempo Coach → Training time',
            editable: true,
          ),
          _ => Input(
            'Usual training time from your workouts (${_hm(t.amSlot)} or ${_hm(t.pmSlot)})',
            Origin.estimated,
            'From when you usually train',
          ),
        },
        if (limit != sc.TrainingLimit.none)
          Input(
            'Injury: ${sc.limitName(limit).toLowerCase()}',
            Origin.you,
            'You → Injury',
            editable: true,
          ),
        if (p.vdot != null)
          const Input(
            'Running paces from your race time',
            Origin.you,
            'You → Race time for paces',
            editable: true,
          ),
        Input(
          '${grouped(p.effectiveStepGoal)} steps a day',
          p.stepGoal == null ? Origin.standard : Origin.you,
          p.stepGoal == null
              ? 'Default for your age; change it in You → Daily step goal'
              : 'You → Daily step goal',
          editable: true,
        ),
        if (food != null)
          Input(
            '${food.protein.round()} g protein a day${food.kcal == null ? '' : ', ${grouped(food.kcal!)} kcal'}',
            Origin.you,
            'You → Food targets',
            editable: true,
          )
        else
          const Input(
            'Food targets suggested, not set',
            Origin.estimated,
            'From your weight and the energy Health holds; You → Food targets',
            editable: true,
          ),
      ],
    ),
    (
      title: 'Body',
      items: [
        Input(
          '${p.age}, ${p.male ? 'male' : 'female'}, ${p.heightCm} cm',
          Origin.you,
          'You → About you',
          editable: true,
        ),
        trend != null
            ? Input(
                'Weight ${trend.weekMean.toStringAsFixed(1)} kg',
                Origin.measured,
                'Mean of ${trend.readings} readings from Health this week',
              )
            : Input(
                'Weight ${p.weightKg.round()} kg',
                Origin.you,
                'You → Weight; a scale that writes to Health would keep it current',
                editable: true,
              ),
      ],
    ),
    (
      title: 'Heart',
      items: [
        maxHr,
        rhr != null
            ? Input(
                'Resting heart rate ${rhr.mean.round()} bpm',
                Origin.measured,
                'Your normal over ${rhr.n} nights',
              )
            : const Input(
                'Resting heart rate',
                Origin.learning,
                'Needs a few nights of heart rate while you sleep',
              ),
        if (source.isHealth)
          hrv != null
              ? Input(
                  'HRV ${hrv.mean.round()} ms',
                  Origin.measured,
                  'Your normal over ${hrv.n} nights',
                )
              : const Input(
                  'HRV',
                  Origin.learning,
                  'Needs a watch that shares HRV with Health; Recovery leans on resting heart rate until then',
                ),
        Input(
          p.zonesByReserve
              ? 'Zones from resting to max heart rate'
              : 'Zones as a share of max heart rate',
          p.zonesByReserve ? Origin.you : Origin.standard,
          'You → Heart-rate zones',
          editable: true,
        ),
      ],
    ),
    (
      title: 'Sleep',
      items: [
        t.baseNeedLearned
            ? Input(
                'Needs about ${hmSpaced(t.baseNeed)} of sleep',
                Origin.measured,
                'Learned from your own nights',
              )
            : Input(
                'Needs about ${hmSpaced(t.baseNeed)} of sleep',
                Origin.standard,
                'Tempo’s default until your own nights show it',
              ),
        wakeSet
            ? Input(
                'Wakes at ${_hm(t.wakeMinute)}',
                Origin.you,
                'Sleep → Wake time',
                editable: true,
              )
            : t.wakeFromUsual
            ? Input(
                'Wakes at ${_hm(t.wakeMinute)}',
                Origin.measured,
                'Your usual wake time over the last 14 nights',
              )
            : Input(
                'Wakes at ${_hm(t.wakeMinute)}',
                Origin.standard,
                'Set one in Sleep → Wake time, or sleep a few nights with your watch on',
                editable: true,
              ),
        Input(
          'Bed by ${_hm(t.bedtimeMinute)} tonight',
          Origin.estimated,
          t.goalBedtimeMinute != null && t.goalBedtimeMinute != t.bedtimeMinute
              ? 'Moving 15 min at a time from your usual toward ${_hm(t.goalBedtimeMinute!)}, what your need asks for'
              : 'Your wake time minus your need tonight',
        ),
        t.calibrating
            ? Input(
                '${t.nights} of 14 nights toward your normal',
                Origin.learning,
                'Recovery starts at 14 nights; a night without data is left out',
              )
            : const Input(
                '14 nights of your own normal',
                Origin.measured,
                'Every score compares you with you',
              ),
      ],
    ),
    (title: 'Data', items: sources),
  ];
}
