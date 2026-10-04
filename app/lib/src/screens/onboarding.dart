import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/notifications.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';
import 'pairing.dart';

enum _Step {
  value1,
  value2,
  value3,
  profile,
  goals,
  workouts,
  availability,
  permissions,
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  var _step = _Step.value1;
  var _p = const Profile();
  final _age = TextEditingController(text: '31');
  final _ht = TextEditingController(text: '176');
  final _wt = TextEditingController(text: '74');
  final _mx = TextEditingController();
  bool _maxEdited = false;

  @override
  void dispose() {
    for (final c in [_age, _ht, _wt, _mx]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _i => _step.index;

  void _go(int d) {
    TempoHaptics.selection();
    setState(
      () => _step = _Step.values[(_i + d).clamp(0, _Step.values.length - 1)],
    );
  }

  bool get _profileValid {
    final a = int.tryParse(_age.text),
        h = int.tryParse(_ht.text),
        w = int.tryParse(_wt.text),
        m = int.tryParse(_mx.text);
    return a != null &&
        a >= 13 &&
        a <= 100 &&
        h != null &&
        h > 80 &&
        h < 260 &&
        w != null &&
        w > 25 &&
        w < 300 &&
        (!_maxEdited || (m != null && m >= 120 && m <= 230));
  }

  void _readProfile() {
    final metric = _p.metric;
    final h = int.parse(_ht.text), w = int.parse(_wt.text);
    _p = _p.copyWith(
      age: int.parse(_age.text),
      heightCm: metric ? h : (h * 2.54).round(),
      weightKg: metric ? w.toDouble() : w / 2.2046,
      maxHr: () => _maxEdited ? int.tryParse(_mx.text) : null,
    );
  }

  Future<void> _finish({required bool pair}) async {
    final db = ref.read(dbProvider);
    await saveAppProfile(db, _p);
    await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
    if (pair) {
      await requestBluetooth();
      await TempoNotifications.instance.requestPermission();
    }
    await db.putSetting(Keys.onboarded, '1');
    if (pair && mounted) await push(context, const PairingScreen());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top,
        bottom = MediaQuery.of(context).padding.bottom;
    final age = int.tryParse(_age.text) ?? 31;
    if (!_maxEdited) _mx.text = '${sc.maxHrFromAge(age)}';
    final (cta, enabled) = switch (_step) {
      _Step.value3 => ('Get started', true),
      _Step.profile => ('Continue', _profileValid),
      _Step.workouts => ('Continue', _p.likes.isNotEmpty),
      _Step.availability => ('Continue', _p.days.isNotEmpty),
      _Step.permissions => ('Allow Bluetooth', true),
      _ => ('Continue', true),
    };
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, top + 12, 10, 0),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: _i > 0
                        ? TempoIconButton(
                            TempoIcons.back,
                            label: 'Back',
                            onTap: () => _go(-1),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var k = 0; k < _Step.values.length; k++)
                          AnimatedContainer(
                            duration: TempoMotion.base,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: k == _i ? 18 : 6,
                            height: 4,
                            decoration: BoxDecoration(
                              color: k <= _i ? c.text1 : c.trackOff,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: _i < 2
                        ? Pressable(
                            onTap: () => setState(() => _step = _Step.profile),
                            child: Center(
                              child: Text(
                                'Skip',
                                style: TempoType.body.copyWith(
                                  fontSize: 14,
                                  color: c.text2,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: TempoMotion.base,
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        MediaQuery.of(context).size.height - top - bottom - 220,
                  ),
                  child: _body(context),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
            child: Column(
              children: [
                TempoButton(
                  cta,
                  expand: true,
                  onTap: !enabled
                      ? null
                      : () {
                          if (_step == _Step.profile) _readProfile();
                          if (_step == _Step.permissions) {
                            _finish(pair: true);
                          } else {
                            _go(1);
                          }
                        },
                ),
                if (_step == _Step.permissions) ...[
                  const SizedBox(height: 4),
                  TempoButton(
                    'Not now — I’ll pair later',
                    kind: ButtonKind.text,
                    expand: true,
                    onTap: () => _finish(pair: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t, style: TempoType.pageTitle.c(context.c.text1)),
      const SizedBox(height: 8),
      Text(sub, style: TempoType.bodyS.c(context.c.text2)),
    ],
  );

  Widget _hero(Widget art, String title, String body, {Widget? extra}) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          art,
          const SizedBox(height: 40),
          Text(
            title,
            style: TempoType.titleL.copyWith(
              fontSize: 32,
              height: 38 / 32,
              color: context.c.text1,
            ),
          ),
          const SizedBox(height: 10),
          Text(body, style: TempoType.body.c(context.c.text2)),
          if (extra != null) ...[const SizedBox(height: 40), extra],
        ],
      );

  Widget _body(BuildContext context) {
    final c = context.c, s = context.s;
    switch (_step) {
      case _Step.value1:
        Widget ladder(int filled, Color col) => Column(
          verticalDirection: VerticalDirection.up,
          children: [
            for (var i = 0; i < 20; i++)
              SizedBox(
                height: 10,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: (i + 1) % 5 == 0 ? 64 : 46,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < filled ? col : c.trackOff,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        );
        return _hero(
          SizedBox(
            height: 240,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ladder(16, s.recHigh),
                const SizedBox(width: 28),
                ladder(11, s.strain[1]),
                const SizedBox(width: 28),
                ladder(18, s.sleepChannel),
              ],
            ),
          ),
          'Know how ready you are, every morning.',
          'Recovery, strain and sleep from your Mi Band 6, measured against your own normal — not anyone else’s.',
        );
      case _Step.value2:
        return _hero(
          TempoCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Recovery 41%',
                        style: TextStyle(color: s.recMid),
                      ),
                      const TextSpan(text: ' — keep strain under 12 today.'),
                    ],
                  ),
                  style: TempoType.titleL.c(c.text1),
                ),
                const SizedBox(height: 14),
                const IntervalBars(
                  segments: [(5, 1), (30, 2), (5, 1)],
                  height: 30,
                  base: 8,
                  step: 6,
                ),
                const SizedBox(height: 14),
                Text(
                  'Easy aerobic ride · 40 min · Z2',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          'One clear call. One workout.',
          'Each morning answers “what should I do today?” — and your week adapts when your body says otherwise.',
        );
      case _Step.value3:
        Widget row(String a, Widget b) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: TempoType.body.c(c.text1),
                  child: Row(children: [Text(a)]),
                ),
              ),
              b,
            ],
          ),
        );
        return _hero(
          CardList(
            children: [
              row(
                'Resting HR',
                Text(
                  '▲ 4 bpm below normal',
                  style: TempoType.body.c(s.recHigh),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('Stress index', style: TempoType.body.c(c.text1)),
                    const SizedBox(width: 6),
                    const TempoBadge('≈', small: true),
                    const Spacer(),
                    Text('▲ calmer', style: TempoType.body.c(s.recHigh)),
                  ],
                ),
              ),
              row(
                'Sleep',
                Text('▼ 1h 10m short', style: TempoType.body.c(s.recLow)),
              ),
            ],
          ),
          'Every number explains itself.',
          'Tap any score to see exactly what moved it. Estimates are labelled as estimates.',
          extra: Row(
            children: [
              TempoIcon(TempoIcons.private, size: 18, color: c.text2),
              const SizedBox(width: 10),
              Text(
                'All data stays on this phone. No account, no cloud.',
                style: TempoType.bodyS.c(c.text2),
              ),
            ],
          ),
        );
      case _Step.profile:
        Widget f(
          String l,
          TextEditingController ctl,
          String suffix, {
          bool est = false,
        }) => TempoField(
          label: l,
          controller: ctl,
          suffix: suffix,
          estimate: est,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {
            if (ctl == _mx) _maxEdited = true;
          }),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'About you',
              'Used to set your heart-rate zones and strain. You can change these any time.',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: f('Age', _age, 'yrs')),
                const SizedBox(width: 12),
                Expanded(child: f('Height', _ht, _p.metric ? 'cm' : 'in')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: f('Weight', _wt, _p.metric ? 'kg' : 'lb')),
                const SizedBox(width: 12),
                Expanded(child: f('Max HR', _mx, 'bpm', est: !_maxEdited)),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface1,
                borderRadius: BorderRadius.circular(TempoRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TempoBadge('Est.'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Max HR is estimated from your age. If you’ve seen a higher number in a hard effort, use that — your zones will be more accurate.',
                      style: TempoType.bodyS.c(c.text2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TempoSegmented<bool>(
                width: 200,
                height: 36,
                values: const [true, false],
                labels: const ['Metric', 'Imperial'],
                selected: _p.metric,
                onChanged: (m) {
                  if (m == _p.metric) return;
                  final h = int.tryParse(_ht.text), w = int.tryParse(_wt.text);
                  setState(() {
                    if (h != null) {
                      _ht.text =
                          '${m ? (h * 2.54).round() : (h / 2.54).round()}';
                    }
                    if (w != null) {
                      _wt.text =
                          '${m ? (w / 2.2046).round() : (w * 2.2046).round()}';
                    }
                    _p = _p.copyWith(metric: m);
                  });
                },
              ),
            ),
          ],
        );
      case _Step.goals:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'What are you training for?',
              'Pick one. It shapes which workouts Coach suggests.',
            ),
            const SizedBox(height: 24),
            for (final g in sc.Goal.values) ...[
              Pressable(
                selected: _p.goal == g,
                label: goalLabel(g),
                onTap: () => setState(() => _p = _p.copyWith(goal: g)),
                child: AnimatedContainer(
                  duration: TempoMotion.fast,
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface1,
                    borderRadius: BorderRadius.circular(TempoRadii.lg),
                    border: Border.all(
                      color: _p.goal == g ? c.text1 : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goalLabel(g),
                              style: TempoType.label.copyWith(
                                fontSize: 15,
                                color: c.text1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(goalSub(g), style: TempoType.bodyS.c(c.text2)),
                          ],
                        ),
                      ),
                      AnimatedContainer(
                        duration: TempoMotion.fast,
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.text1,
                            width: _p.goal == g ? 7 : 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      case _Step.workouts:
        return WorkoutsEditor(
          profile: _p,
          onChanged: (p) => setState(() => _p = p),
        );
      case _Step.availability:
        return AvailabilityEditor(
          profile: _p,
          onChanged: (p) => setState(() => _p = p),
        );
      case _Step.permissions:
        Widget perm(String icon, String t, String req, String body) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: TempoIcon(icon, size: 20, color: c.text1),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t, style: TempoType.label.c(c.text1)),
                        ),
                        Text(req, style: TempoType.caption.c(c.text3)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: TempoType.bodyS.c(c.text2)),
                  ],
                ),
              ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Two permissions, explained',
              'Tempo talks to your band directly. There’s no account and nothing is uploaded.',
            ),
            const SizedBox(height: 24),
            CardList(
              children: [
                perm(
                  TempoIcons.bluetooth,
                  'Bluetooth',
                  'Required',
                  'To read heart rate, sleep and steps from your band, and to sync in the background.',
                ),
                perm(
                  TempoIcons.bell,
                  'Notifications',
                  'Optional',
                  'One message a morning with your call for the day, and a bedtime nudge. Nothing else.',
                ),
              ],
            ),
            const SizedBox(height: 24),
            const PrivacyNote(
              'All data stays on this phone. Export it any time from Profile.',
            ),
          ],
        );
    }
  }
}

/// Preferred workouts. In a sheet it carries its own Save button.
class WorkoutsEditor extends StatefulWidget {
  const WorkoutsEditor({
    super.key,
    required this.profile,
    this.onChanged,
    this.sheet = false,
  });
  final Profile profile;
  final ValueChanged<Profile>? onChanged;
  final bool sheet;
  @override
  State<WorkoutsEditor> createState() => _WorkoutsEditorState();
}

class _WorkoutsEditorState extends State<WorkoutsEditor> {
  late var _p = widget.profile;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What do you like doing?',
          style: (widget.sheet ? TempoType.titleL : TempoType.pageTitle).c(
            c.text1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose any. Suggestions only use these.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in sportOrder)
              TempoChip(
                sportLabel(s),
                height: 48,
                selected: _p.likes.contains(s),
                onTap: () {
                  final likes = {..._p.likes};
                  likes.contains(s) ? likes.remove(s) : likes.add(s);
                  setState(() => _p = _p.copyWith(likes: likes));
                  widget.onChanged?.call(_p);
                },
              ),
          ],
        ),
        if (widget.sheet) ...[
          const SizedBox(height: 24),
          TempoButton(
            'Save',
            expand: true,
            onTap: _p.likes.isEmpty ? null : () => Navigator.pop(context, _p),
          ),
        ],
      ],
    );
  }
}

/// Days and minutes available. The plan never asks for more than this.
class AvailabilityEditor extends StatefulWidget {
  const AvailabilityEditor({
    super.key,
    required this.profile,
    this.onChanged,
    this.sheet = false,
  });
  final Profile profile;
  final ValueChanged<Profile>? onChanged;
  final bool sheet;
  @override
  State<AvailabilityEditor> createState() => _AvailabilityEditorState();
}

class _AvailabilityEditorState extends State<AvailabilityEditor> {
  late var _p = widget.profile;

  void _set(Profile p) {
    setState(() => _p = p);
    widget.onChanged?.call(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hours = (_p.days.length.clamp(1, 6) * _p.maxMinutes * .75 / 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'When can you train?',
          style: (widget.sheet ? TempoType.titleL : TempoType.pageTitle).c(
            c.text1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your plan never asks for more than this.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            for (var d = 1; d <= 7; d++) ...[
              if (d > 1) const SizedBox(width: 6),
              Expanded(
                child: Pressable(
                  label: const [
                    'Monday',
                    'Tuesday',
                    'Wednesday',
                    'Thursday',
                    'Friday',
                    'Saturday',
                    'Sunday',
                  ][d - 1],
                  selected: _p.days.contains(d),
                  onTap: () {
                    TempoHaptics.selection();
                    final days = {..._p.days};
                    days.contains(d) ? days.remove(d) : days.add(d);
                    _set(_p.copyWith(days: days));
                  },
                  child: AnimatedContainer(
                    duration: TempoMotion.fast,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _p.days.contains(d) ? c.text1 : null,
                      borderRadius: BorderRadius.circular(14),
                      border: _p.days.contains(d)
                          ? null
                          : Border.all(color: c.lineStrong),
                    ),
                    child: Text(
                      'MTWTFSS'[d - 1],
                      style: TempoType.label.copyWith(
                        fontSize: 14,
                        color: _p.days.contains(d) ? c.textInverse : c.text2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Per session, up to',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_p.maxMinutes}',
                          style: TempoType.scoreS.c(c.text1),
                        ),
                        TextSpan(
                          text: ' min',
                          style: TempoType.caption.c(c.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: c.text1,
                  inactiveTrackColor: c.trackOff,
                  thumbColor: c.text1,
                  overlayColor: c.text1.withValues(alpha: .08),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 12,
                    elevation: 2,
                  ),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  min: 20,
                  max: 120,
                  divisions: 20,
                  value: _p.maxMinutes.toDouble(),
                  semanticFormatterCallback: (v) => '${v.round()} minutes',
                  onChanged: (v) {
                    if (v.round() != _p.maxMinutes) TempoHaptics.selection();
                    _set(_p.copyWith(maxMinutes: v.round()));
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('20', style: TempoType.caption.c(c.text3)),
                  Text('120', style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '${_p.days.length} days, up to ${_p.maxMinutes} min each. Coach usually plans ',
              ),
              TextSpan(
                text: '${hours.floor()}–${hours.ceil() + 1} hours',
                style: TextStyle(color: c.text1),
              ),
              const TextSpan(
                text: ' a week inside that, with at least one rest day.',
              ),
            ],
          ),
          style: TempoType.bodyS.c(c.text2),
        ),
        if (widget.sheet) ...[
          const SizedBox(height: 24),
          TempoButton(
            'Save',
            expand: true,
            onTap: _p.days.isEmpty ? null : () => Navigator.pop(context, _p),
          ),
        ],
      ],
    );
  }
}
