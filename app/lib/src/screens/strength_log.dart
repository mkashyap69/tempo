import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/coach_service.dart' show dayOf;
import '../core/score_service.dart';
import '../core/strength.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/live_session.dart';
import '../state/providers.dart';
import 'nav.dart';

/// Strength log (decisions.md, 2026-10-16): every set with weight, reps
/// and reps in reserve, a rest timer that sounds, a plate calculator,
/// supersets and the library. Sets are saved as they're ticked.
class StrengthLogScreen extends ConsumerStatefulWidget {
  const StrengthLogScreen({super.key, this.plan});

  /// A session whose detail lists exercises (a strength pick), or null to
  /// start empty.
  final sc.Session? plan;

  @override
  ConsumerState<StrengthLogScreen> createState() => _LogState();
}

class _Row {
  _Row({this.kg = 0, this.reps = 0, this.seconds = 0});
  double kg;
  int reps, seconds;
  int? rir;
  int? savedId;
  bool get done => savedId != null;
}

class _Ex {
  _Ex(this.def, {required this.rest, this.target, this.why});
  final sc.ExerciseDef def;
  final rows = <_Row>[];
  int rest;

  /// Group label when linked to the next exercise as a superset.
  String? superset;
  final String? target, why;
}

class _LogState extends ConsumerState<StrengthLogScreen> {
  final _ex = <_Ex>[];
  final _started = DateTime.now();
  Timer? _clock;
  int _restLeft = 0, _restTotal = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((Object _) {});
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final d = widget.plan?.detail;
    if (d is sc.StrengthDetail) {
      for (final x in d.exercises) {
        final def = sc.exerciseByName(x.name);
        if (def == null) continue;
        final e = _Ex(def, rest: x.restSeconds, target: x.reps, why: x.target);
        final range = sc.parseRepRange(x.reps);
        final last = (await exerciseHistory(db, def.id)).lastOrNull;
        for (var i = 0; i < x.sets; i++) {
          final prev = last == null || last.sets.isEmpty
              ? null
              : last.sets[min(i, last.sets.length - 1)];
          e.rows.add(
            _Row(
              kg: x.kg ?? prev?.kg ?? 0,
              reps: range?.$1 ?? prev?.reps ?? 0,
              seconds: def.kind == sc.SetKind.timed
                  ? (_seconds(x.reps) ?? prev?.seconds ?? 30)
                  : 0,
            ),
          );
        }
        _ex.add(e);
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  static int? _seconds(String reps) {
    final m = RegExp(r'(\d+)\s*s').firstMatch(reps);
    return m == null ? null : int.parse(m.group(1)!);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      if (_restLeft > 0) {
        _restLeft--;
        if (_restLeft == 0) _restDone();
      }
    });
  }

  void _restDone() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _toggle(_Ex e, int i) async {
    final db = ref.read(dbProvider);
    final r = e.rows[i];
    if (r.done) {
      await db.deleteStrengthSet(r.savedId!);
      setState(() => r.savedId = null);
      return;
    }
    HapticFeedback.lightImpact();
    final id = await logSet(
      db,
      exercise: e.def.id,
      setNo: i + 1,
      kg: r.kg,
      reps: r.reps,
      seconds: r.seconds,
      rir: r.rir,
      superset: e.superset,
    );
    setState(() {
      r.savedId = id;
      // In a superset the rest comes after the last exercise of the round.
      final k = _ex.indexOf(e);
      final linkedOn = e.superset != null && k + 1 < _ex.length;
      if (!linkedOn) {
        _restTotal = _restLeft = e.rest;
      }
    });
  }

  Future<void> _edit(_Ex e, _Row r) async {
    if (!r.done) return;
    await ref
        .read(dbProvider)
        .updateStrengthSet(
          r.savedId!,
          st.StrengthSetsCompanion(
            kg: Value(r.kg),
            reps: Value(r.reps),
            seconds: Value(r.seconds),
            rir: Value(r.rir),
          ),
        );
  }

  Future<void> _finish() async {
    final db = ref.read(dbProvider);
    final done = _ex.expand((e) => e.rows).where((r) => r.done).length;
    final live = ref.read(liveSessionProvider);
    final liveOn =
        live != null &&
        live.phase != LivePhase.ended &&
        live.phase != LivePhase.failed;
    if (done > 0 && !liveOn) {
      // A set-only session still shows up as a workout; its load comes from
      // the sets (core/strength.dart → strengthExtraTrimp).
      final now = DateTime.now();
      await db.addWorkout(
        st.WorkoutsCompanion.insert(
          start: st.toTs(_started),
          end: st.toTs(now),
          sport: Value(sc.Sport.strength.name),
          title: widget.plan?.title ?? 'Strength',
          source: 'live',
          confirmed: const Value(true),
          strain: 0,
          trimp: 0,
          zones: '[0,0,0,0,0]',
        ),
      );
      await ScoreService(db).recomputeFrom(dayOf(now));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (done > 0) showTempoToast(context, '$done sets saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final live = ref.watch(liveSessionProvider);
    final el = DateTime.now().difference(_started);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Expanded(
            child: TempoPage(
              gap: 14,
              children: [
                DetailHeader(
                  title: _mmss(el),
                  subtitle: widget.plan?.title ?? 'Strength',
                  leadingIcon: TempoIcons.close,
                  onBack: _finish,
                  trailing: TempoButton('Finish', small: true, onTap: _finish),
                ),
                if (!_ready)
                  const SizedBox(height: 300)
                else ...[
                  for (final (k, e) in _ex.indexed) ...[
                    _ExerciseCard(
                      e,
                      onToggle: (i) => _toggle(e, i),
                      onChanged: (r) async {
                        setState(() {});
                        await _edit(e, r);
                      },
                      onAddSet: () => setState(() {
                        final last = e.rows.lastOrNull;
                        e.rows.add(
                          _Row(
                            kg: last?.kg ?? 0,
                            reps: last?.reps ?? 8,
                            seconds: last?.seconds ?? 0,
                          ),
                        );
                      }),
                      onRest: (s) => setState(() => e.rest = s),
                      onRemove: () => setState(() => _ex.removeAt(k)),
                    ),
                    if (k + 1 < _ex.length)
                      Center(
                        child: TempoIconButton(
                          TempoIcons.link,
                          label: e.superset == null
                              ? 'Link as a superset'
                              : 'Unlink superset',
                          color: e.superset == null ? c.text3 : c.text1,
                          onTap: () => setState(() {
                            final next = _ex[k + 1];
                            if (e.superset == null) {
                              final g = String.fromCharCode(65 + (k % 26));
                              e.superset = g;
                              next.superset ??= g;
                            } else {
                              e.superset = null;
                            }
                          }),
                        ),
                      ),
                  ],
                  TempoButton(
                    'Add exercise',
                    kind: ButtonKind.secondary,
                    expand: true,
                    onTap: () async {
                      final def = await Navigator.of(context)
                          .push<sc.ExerciseDef>(
                            MaterialPageRoute(
                              builder: (_) => const ExercisePickerScreen(),
                            ),
                          );
                      if (def == null) return;
                      final last = (await exerciseHistory(
                        ref.read(dbProvider),
                        def.id,
                      )).lastOrNull;
                      setState(() {
                        final e = _Ex(def, rest: 90);
                        for (var i = 0; i < 3; i++) {
                          final p = last == null || last.sets.isEmpty
                              ? null
                              : last.sets[min(i, last.sets.length - 1)];
                          e.rows.add(
                            _Row(
                              kg: p?.kg ?? 0,
                              reps: p?.reps ?? 8,
                              seconds: def.kind == sc.SetKind.timed
                                  ? (p?.seconds ?? 30)
                                  : 0,
                            ),
                          );
                        }
                        _ex.add(e);
                      });
                    },
                  ),
                  const SizedBox(height: 90),
                ],
              ],
            ),
          ),
          _RestBar(
            left: _restLeft,
            total: _restTotal,
            bpm: live?.bpm,
            onSkip: () => setState(() => _restLeft = 0),
            onAdd: () => setState(() {
              _restLeft += 15;
              _restTotal += 15;
            }),
          ),
        ],
      ),
    );
  }
}

String _mmss(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

String _kg(double kg) =>
    kg == kg.roundToDouble() ? '${kg.round()}' : kg.toStringAsFixed(1);

String _rir(int? r) => r == null ? 'RIR' : (r >= 3 ? '3+ left' : '$r left');

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard(
    this.e, {
    required this.onToggle,
    required this.onChanged,
    required this.onAddSet,
    required this.onRest,
    required this.onRemove,
  });
  final _Ex e;
  final ValueChanged<int> onToggle;
  final ValueChanged<_Row> onChanged;
  final VoidCallback onAddSet, onRemove;
  final ValueChanged<int> onRest;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = e.def;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: TempoType.titleM.c(c.text1)),
                    Text(
                      '${equipmentName(d.equipment)} · ${e.rows.length} sets${e.superset == null ? '' : ' · superset ${e.superset}'}',
                      style: TempoType.caption.c(c.text3),
                    ),
                  ],
                ),
              ),
              TempoButton(
                '${e.rest} s',
                kind: ButtonKind.text,
                small: true,
                onTap: () async {
                  final v = await pickOption<int>(
                    context,
                    title: 'Rest between sets',
                    options: const [0, 30, 45, 60, 90, 120, 180, 240],
                    selected: e.rest,
                    label: (s) => s == 0 ? 'No timer' : '$s s',
                  );
                  if (v != null) onRest(v);
                },
              ),
            ],
          ),
          if (e.why != null) ...[
            const SizedBox(height: 4),
            Text(e.why!, style: TempoType.caption.c(context.s.recHigh)),
          ],
          const SizedBox(height: 10),
          for (final (i, r) in e.rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: TempoType.label.c(c.text3).tnum,
                    ),
                  ),
                  if (d.kind == sc.SetKind.weighted)
                    _Cell(
                      '${_kg(r.kg)} kg',
                      label: 'Set ${i + 1} weight',
                      done: r.done,
                      onTap: () async {
                        final v = await (d.equipment == sc.Equipment.barbell
                            ? plateSheet(context, r.kg)
                            : numberSheet(
                                context,
                                title: 'Weight',
                                unit: 'kg',
                                initial: r.kg,
                                step: d.stepKg,
                              ));
                        if (v != null) {
                          r.kg = v;
                          onChanged(r);
                        }
                      },
                    ),
                  if (d.kind == sc.SetKind.timed)
                    _Cell(
                      '${r.seconds} s',
                      label: 'Set ${i + 1} seconds',
                      done: r.done,
                      onTap: () async {
                        final v = await numberSheet(
                          context,
                          title: 'Seconds',
                          unit: 's',
                          initial: r.seconds.toDouble(),
                          step: 5,
                        );
                        if (v != null) {
                          r.seconds = v.round();
                          onChanged(r);
                        }
                      },
                    )
                  else
                    _Cell(
                      '${r.reps} reps',
                      label: 'Set ${i + 1} reps',
                      done: r.done,
                      onTap: () async {
                        final v = await numberSheet(
                          context,
                          title: 'Reps',
                          unit: 'reps',
                          initial: r.reps.toDouble(),
                          step: 1,
                        );
                        if (v != null) {
                          r.reps = v.round();
                          onChanged(r);
                        }
                      },
                    ),
                  _Cell(
                    _rir(r.rir),
                    label: 'Set ${i + 1} reps in reserve',
                    done: r.done,
                    flex: 1,
                    onTap: () {
                      // —, 0, 1, 2, 3+ and round again.
                      r.rir = switch (r.rir) {
                        null => 0,
                        3 => null,
                        final x => x + 1,
                      };
                      onChanged(r);
                    },
                  ),
                  const SizedBox(width: 6),
                  Pressable(
                    label: r.done ? 'Undo set ${i + 1}' : 'Done set ${i + 1}',
                    selected: r.done,
                    onTap: () => onToggle(i),
                    child: AnimatedContainer(
                      duration: TempoMotion.fast,
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: r.done ? context.s.recHigh : Colors.transparent,
                        shape: BoxShape.circle,
                        border: r.done ? null : Border.all(color: c.lineStrong),
                      ),
                      child: Center(
                        child: TempoIcon(
                          TempoIcons.check,
                          size: 18,
                          color: r.done ? c.textInverse : c.text2,
                          stroke: 2.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TempoButton(
                'Progression',
                kind: ButtonKind.text,
                small: true,
                onTap: () => push(context, ExerciseHistoryScreen(d)),
              ),
              TempoButton(
                'Remove',
                kind: ButtonKind.text,
                small: true,
                onTap: e.rows.any((r) => r.done) ? null : onRemove,
              ),
              TempoButton(
                'Add set',
                kind: ButtonKind.text,
                small: true,
                onTap: onAddSet,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.label,
    required this.onTap,
    required this.done,
    this.flex = 2,
  });
  final String text, label;
  final VoidCallback onTap;
  final bool done;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Pressable(
          label: label,
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? context.s.recHigh.withValues(alpha: .15)
                  : c.surface2,
              borderRadius: BorderRadius.circular(TempoRadii.sm),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TempoType.label.c(c.text1).tnum,
            ),
          ),
        ),
      ),
    );
  }
}

class _RestBar extends StatelessWidget {
  const _RestBar({
    required this.left,
    required this.total,
    required this.bpm,
    required this.onSkip,
    required this.onAdd,
  });
  final int left, total;
  final int? bpm;
  final VoidCallback onSkip, onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  left > 0 ? 'Rest ${_mmss(Duration(seconds: left))}' : 'Ready',
                  style: TempoType.titleM.c(c.text1).tnum,
                ),
                if (left > 0 && total > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: 1 - left / total,
                      minHeight: 4,
                      backgroundColor: c.trackOff,
                      color: c.text1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (bpm != null) ...[
            const SizedBox(width: 12),
            Text('$bpm ♥', style: TempoType.label.c(c.text1).tnum),
          ],
          if (left > 0) ...[
            TempoButton(
              '+15 s',
              kind: ButtonKind.text,
              small: true,
              onTap: onAdd,
            ),
            TempoButton(
              'Skip',
              kind: ButtonKind.text,
              small: true,
              onTap: onSkip,
            ),
          ],
        ],
      ),
    );
  }
}

String equipmentName(sc.Equipment e) => switch (e) {
  sc.Equipment.barbell => 'Barbell',
  sc.Equipment.dumbbell => 'Dumbbell',
  sc.Equipment.kettlebell => 'Kettlebell',
  sc.Equipment.machine => 'Machine',
  sc.Equipment.cable => 'Cable',
  sc.Equipment.bodyweight => 'Bodyweight',
  sc.Equipment.band => 'Band',
  sc.Equipment.other => 'Other',
};

String muscleName(sc.Muscle m) => switch (m) {
  sc.Muscle.chest => 'Chest',
  sc.Muscle.back => 'Back',
  sc.Muscle.shoulders => 'Shoulders',
  sc.Muscle.biceps => 'Biceps',
  sc.Muscle.triceps => 'Triceps',
  sc.Muscle.forearms => 'Forearms',
  sc.Muscle.core => 'Core',
  sc.Muscle.glutes => 'Glutes',
  sc.Muscle.quads => 'Quads',
  sc.Muscle.hamstrings => 'Hamstrings',
  sc.Muscle.calves => 'Calves',
};

/// A number with − and + by [step]. Null = cancelled.
Future<double?> numberSheet(
  BuildContext context, {
  required String title,
  required String unit,
  required double initial,
  required double step,
}) {
  var v = initial;
  return showTempoSheet<double>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TempoType.titleM.c(ctx.c.text1)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TempoIconButton(
                TempoIcons.minus,
                label: 'Less',
                onTap: () => set(() => v = max(0, v - step)),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  '${_kg(v)} $unit',
                  textAlign: TextAlign.center,
                  style: TempoType.scoreS.c(ctx.c.text1),
                ),
              ),
              TempoIconButton(
                TempoIcons.plus,
                label: 'More',
                onTap: () => set(() => v += step),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TempoButton('Done', expand: true, onTap: () => Navigator.pop(ctx, v)),
        ],
      ),
    ),
  );
}

/// Plates a side for [kg] on a 20 kg bar, heaviest first (greedy).
List<double> platesFor(double kg, {double bar = 20}) {
  const sizes = <double>[25, 20, 15, 10, 5, 2.5, 1.25];
  var side = max(0.0, (kg - bar) / 2);
  final out = <double>[];
  for (final p in sizes) {
    while (side >= p - 1e-9) {
      out.add(p);
      side -= p;
    }
  }
  return out;
}

/// Plate calculator: tap plates to add a pair, tap a loaded plate to
/// take it off. Returns the total on the bar.
Future<double?> plateSheet(BuildContext context, double kg) {
  var plates = platesFor(kg);
  const bar = 20.0;
  double total() => bar + 2 * plates.fold<double>(0, (a, p) => a + p);
  return showTempoSheet<double>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_kg(total())} kg',
              textAlign: TextAlign.center,
              style: TempoType.scoreS.c(c.text1),
            ),
            Text(
              'Plates a side on a 20 kg bar · tap a plate to take it off',
              textAlign: TextAlign.center,
              style: TempoType.caption.c(c.text3),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 90,
              child: Row(
                children: [
                  Container(width: 50, height: 10, color: c.lineStrong),
                  for (final (i, p) in plates.indexed)
                    Pressable(
                      label: 'Remove $p kg',
                      onTap: () => set(() => plates = [...plates]..removeAt(i)),
                      child: Container(
                        width: 18,
                        height: 30 + p * 2.2,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: c.text1.withValues(alpha: .25 + p / 40),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            _kg(p),
                            style: TempoType.caption.c(c.textInverse),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: Container(height: 10, color: c.lineStrong)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Overline('Add a pair'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [1.25, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0])
                  TempoChip(
                    _kg(p),
                    selected: false,
                    height: 40,
                    onTap: () => set(() {
                      plates = [...plates, p]..sort((a, b) => b.compareTo(a));
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TempoButton(
              'Use ${_kg(total())} kg',
              expand: true,
              onTap: () => Navigator.pop(ctx, total()),
            ),
          ],
        );
      },
    ),
  );
}

// ---- library ----------------------------------------------------------------

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _PickerState();
}

class _PickerState extends State<ExercisePickerScreen> {
  final _q = TextEditingController();
  sc.Muscle? _muscle;
  sc.Equipment? _eq;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final e in sc.exerciseLibrary)
        if ((q.isEmpty || e.name.toLowerCase().contains(q)) &&
            (_muscle == null ||
                e.primary.contains(_muscle) ||
                e.secondary.contains(_muscle)) &&
            (_eq == null || e.equipment == _eq))
          e,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return TempoPage(
      gap: 12,
      children: [
        const DetailHeader(title: 'Library'),
        TempoField(
          controller: _q,
          label: 'Search ${sc.exerciseLibrary.length} exercises',
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: [
            Expanded(
              child: TempoButton(
                _muscle == null ? 'All muscles' : muscleName(_muscle!),
                kind: ButtonKind.secondary,
                small: true,
                onTap: () async {
                  final m = await pickOption<int>(
                    context,
                    title: 'Muscle',
                    options: [-1, for (final m in sc.Muscle.values) m.index],
                    selected: _muscle?.index ?? -1,
                    label: (i) =>
                        i < 0 ? 'All muscles' : muscleName(sc.Muscle.values[i]),
                  );
                  if (m != null) {
                    setState(
                      () => _muscle = m < 0 ? null : sc.Muscle.values[m],
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TempoButton(
                _eq == null ? 'All equipment' : equipmentName(_eq!),
                kind: ButtonKind.secondary,
                small: true,
                onTap: () async {
                  final m = await pickOption<int>(
                    context,
                    title: 'Equipment',
                    options: [-1, for (final e in sc.Equipment.values) e.index],
                    selected: _eq?.index ?? -1,
                    label: (i) => i < 0
                        ? 'All equipment'
                        : equipmentName(sc.Equipment.values[i]),
                  );
                  if (m != null) {
                    setState(() => _eq = m < 0 ? null : sc.Equipment.values[m]);
                  }
                },
              ),
            ),
          ],
        ),
        if (list.isEmpty)
          const TempoEmpty('No exercise matches.')
        else
          CardList(
            children: [
              for (final e in list)
                ListRow(
                  e.name,
                  sub:
                      '${equipmentName(e.equipment)} · ${e.primary.map(muscleName).join(', ')}',
                  onTap: () => Navigator.pop(context, e),
                ),
            ],
          ),
      ],
    );
  }
}

// ---- progression ----------------------------------------------------------------

final _historyProvider =
    FutureProvider.family<List<sc.ExerciseSession>, String>((ref, id) async {
      ref.watch(dbTickProvider);
      final db = ref.watch(dbProvider);
      return sc.sessionsOf(id, [
        for (final r in await db.strengthHistory(id)) setLog(r),
      ]);
    });

/// One exercise over time: estimated 1RM, top weight and volume.
class ExerciseHistoryScreen extends ConsumerStatefulWidget {
  const ExerciseHistoryScreen(this.def, {super.key});
  final sc.ExerciseDef def;

  @override
  ConsumerState<ExerciseHistoryScreen> createState() => _HistState();
}

enum _Metric { e1rm, top, volume, sets }

class _HistState extends ConsumerState<ExerciseHistoryScreen> {
  _Metric _m = _Metric.e1rm;

  double? _value(sc.ExerciseSession s) => switch (_m) {
    _Metric.e1rm => s.bestE1rm,
    _Metric.top => s.topKg,
    _Metric.volume => s.volume,
    _Metric.sets => s.sets.length.toDouble(),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = ref.watch(_historyProvider(widget.def.id)).value;
    final pts = [
      for (final s in h ?? const <sc.ExerciseSession>[])
        if (_value(s) case final v? when v > 0) (s.day, v),
    ];
    return TempoPage(
      gap: 14,
      children: [
        DetailHeader(title: widget.def.name),
        TempoSegmented<_Metric>(
          values: _Metric.values,
          labels: const ['1RM', 'Top', 'Volume', 'Sets'],
          selected: _m,
          onChanged: (v) => setState(() => _m = v),
          height: 34,
        ),
        if (pts.length < 2)
          const TempoEmpty('Two sessions are needed for a line.')
        else
          TempoCard(
            child: SvgChart(
              height: 180,
              semantics: '${widget.def.name} over time',
              draw: (ink, box) {
                final ys = pts.map((p) => p.$2);
                var lo = ys.reduce(min), hi = ys.reduce(max);
                if (hi - lo < 1e-6) {
                  lo -= 1;
                  hi += 1;
                }
                final t0 = pts.first.$1;
                final span = max(1, pts.last.$1.difference(t0).inDays);
                double x(DateTime t) =>
                    10 + t.difference(t0).inDays / span * 480;
                double y(double v) => 150 - (v - lo) / (hi - lo) * 130;
                final line = [for (final p in pts) Offset(x(p.$1), y(p.$2))];
                ink.polyline(line, ink.c.text1, w: 2.5);
                for (final p in line) {
                  ink.dot(p, 3.5, ink.c.text1);
                }
                ink.text(
                  _kg(pts.last.$2),
                  Offset(line.last.dx, line.last.dy - 10),
                  align: TextAlign.center,
                  size: 13,
                  color: ink.c.text1,
                );
              },
            ),
          ),
        if (h != null && h.isNotEmpty)
          CardList(
            children: [
              for (final s in h.reversed.take(12))
                ListRow(
                  '${s.day.day}/${s.day.month}',
                  value: s.sets
                      .map(
                        (x) => x.kg > 0
                            ? '${_kg(x.kg)}×${x.reps}'
                            : x.seconds > 0
                            ? '${x.seconds}s'
                            : '${x.reps}',
                      )
                      .join('  '),
                  chevron: false,
                ),
            ],
          ),
        Text(
          'Estimated 1RM uses the Epley formula on sets of 10 reps or fewer.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

// ---- freshness --------------------------------------------------------------------

final freshnessProvider = FutureProvider<Map<sc.Muscle, double>?>((ref) async {
  ref.watch(dbTickProvider);
  return loadFreshness(ref.watch(dbProvider));
});

/// How recovered each muscle is, from the last week of sets and runs.
class FreshnessCard extends ConsumerWidget {
  const FreshnessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(freshnessProvider).value;
    if (f == null) return const SizedBox.shrink();
    final c = context.c;
    Color tone(double v) => v >= 80
        ? context.s.recHigh
        : v >= 50
        ? context.s.recMid
        : context.s.recLow;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Muscle freshness')),
              Text(
                'Legs ${sc.lowerFreshness(f).round()} % · Upper ${sc.upperFreshness(f).round()} %',
                style: TempoType.caption.c(c.text2).tnum,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final m in sc.Muscle.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      muscleName(m),
                      style: TempoType.caption.c(c.text1),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: f[m]! / 100,
                        minHeight: 6,
                        backgroundColor: c.trackOff,
                        color: tone(f[m]!),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${f[m]!.round()} %',
                      textAlign: TextAlign.end,
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Hard sets in the last week fade by half every 48 h; runs count on the legs.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}
