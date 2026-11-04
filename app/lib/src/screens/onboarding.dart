import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/data_source.dart';
import '../core/health_reader.dart';
import '../core/health_sync.dart';
import '../core/home_widgets.dart' show afterSync;
import '../core/notifications.dart';
import '../core/profile.dart';
import '../core/source_check.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'backups.dart' show RestorePanel;
import 'source_check_view.dart';
import '../account/account_service.dart';
import '../billing/pro.dart';
import '../core/build_info.dart';
import 'paywall.dart';

/// Launch onboarding (B1a, decisions.md 2026-11-03): health-first, no
/// account. Welcome → three numbers → connect Apple Health / Health
/// Connect → first read and source check → about you (prefilled from
/// Health) → goal, activities and days → morning call. The Mi Band is not
/// offered here; it lives behind You → Developer.
enum _Step { welcome, numbers, connect, check, profile, goal, notify }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  var _step = _Step.welcome;
  var _p = const Profile();
  final _source = DataSource.platformHealth;
  bool _connecting = false;

  /// First read: null before it starts, 0..1 while it runs.
  double? _progress;
  SourceCheck? _check;
  bool _weightFromHealth = false;
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

  void _goTo(_Step s) {
    TempoHaptics.selection();
    setState(() => _step = s);
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

  /// A backup with settings brings the profile and "onboarded" back, and
  /// Root moves on by itself. A plain export has no profile: carry on.
  Future<void> _restored() async {
    final db = ref.read(dbProvider);
    if (await db.setting(Keys.onboarded) == '1') return;
    if (await loadAppProfile(db) != null) {
      await db.putSetting(Keys.onboarded, '1');
    } else if (mounted) {
      setState(() => _step = _Step.profile);
    }
  }

  /// Asks for read access; on success reads 90 days and shows the check.
  Future<void> _connect() async {
    final db = ref.read(dbProvider);
    setState(() => _connecting = true);
    HealthConnectResult res;
    try {
      res = await PluginHealthReader().connect();
    } catch (_) {
      res = HealthConnectResult.unavailable;
    }
    if (!mounted) return;
    setState(() => _connecting = false);
    final why = switch (res) {
      HealthConnectResult.ok => null,
      HealthConnectResult.denied => 'Tempo needs heart rate, sleep and steps. Allow them, or choose “Not now” and allow them later from Today.',
      HealthConnectResult.needsInstall => 'Install or update Health Connect from the Play Store, then tap Connect again.',
      HealthConnectResult.unavailable =>
        '${_source.label} isn’t available on this phone. Choose “Not now” to carry on.',
    };
    if (why != null) {
      showTempoToast(context, why);
      return;
    }
    await saveDataSource(db, _source);
    _goTo(_Step.check);
    unawaited(_firstRead());
  }

  /// The first read with progress, then the source check and the profile
  /// prefill. A failed read still moves on: Today retries on open.
  Future<void> _firstRead() async {
    final db = ref.read(dbProvider);
    setState(() => _progress = 0);
    try {
      await HealthSyncService(db).run(
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      await afterSync(db);
    } catch (_) {}
    final check = await sourceCheck(db);
    final w = await db.healthRecordsBetween(
      DateTime.now().subtract(const Duration(days: 365)),
      DateTime.now(),
      kinds: const ['weight'],
    );
    if (!mounted) return;
    setState(() {
      _progress = 1;
      _check = check;
      if (w.isNotEmpty) {
        final kg = (w..sort((a, b) => a.endMs - b.endMs)).last.value;
        if (kg > 25 && kg < 300) {
          _wt.text = '${_p.metric ? kg.round() : (kg * 2.2046).round()}';
          _weightFromHealth = true;
        }
      }
    });
  }

  Future<void> _finish({required bool notify}) async {
    final db = ref.read(dbProvider);
    await saveAppProfile(db, _p);
    await CoachService(db).ensureWeek(DateTime.now(), rebuild: true);
    if (await db.setting(Keys.dataSource) == null) {
      await saveDataSource(db, _source);
    }
    if (notify) {
      try {
        await TempoNotifications.instance.requestPermission();
      } catch (_) {} // optional; never blocks finishing
    }
    // Store builds that can sell Pro end onboarding on the paywall, once.
    // Closing it goes straight to Today (launch plan §3, entry point 1).
    if (BuildInfo.store &&
        AccountService.instance.available &&
        !ref.read(proProvider) &&
        mounted) {
      await showPaywall(context, PaywallEntry.onboarding);
    }
    await db.putSetting(Keys.onboarded, '1');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top,
        bottom = MediaQuery.of(context).padding.bottom;
    final age = int.tryParse(_age.text) ?? 31;
    if (!_maxEdited) _mx.text = '${sc.maxHrFromAge(age)}';
    final reading = _step == _Step.check && (_progress ?? 0) < 1;
    final (cta, enabled) = switch (_step) {
      _Step.welcome => ('Get started', true),
      _Step.connect => (
        _connecting ? 'Connecting…' : 'Connect ${_source.label}',
        !_connecting,
      ),
      _Step.check => (reading ? 'Reading…' : 'Looks right', !reading),
      _Step.profile => ('Continue', _profileValid),
      _Step.goal => ('Continue', _p.likes.isNotEmpty && _p.days.isNotEmpty),
      _Step.notify => ('Turn on notifications', true),
      _ => ('Continue', true),
    };
    final secondary = switch (_step) {
      _Step.connect => 'Not now',
      _Step.notify => 'Not now',
      _ => null,
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
                    child: _i > 0 && !reading
                        ? TempoIconButton(
                            TempoIcons.back,
                            label: 'Back',
                            // Back from the profile skips the finished read.
                            onTap: () =>
                                _step == _Step.profile && _check == null
                                ? _goTo(_Step.connect)
                                : _go(-1),
                          )
                        : null,
                  ),
                  Expanded(
                    child: _i == 0
                        ? const SizedBox()
                        : Row(
                            children: [
                              for (var k = 1; k < _Step.values.length; k++)
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: TempoMotion.base,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: k <= _i ? c.text1 : c.trackOff,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 44),
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
                          switch (_step) {
                            case _Step.connect:
                              _connect();
                            case _Step.profile:
                              _readProfile();
                              _go(1);
                            case _Step.notify:
                              _finish(notify: true);
                            default:
                              _go(1);
                          }
                        },
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 4),
                  TempoButton(
                    secondary,
                    kind: ButtonKind.text,
                    expand: true,
                    onTap: () => _step == _Step.connect
                        ? _goTo(_Step.profile)
                        : _finish(notify: false),
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

  /// A score ring for the welcome and the three numbers.
  Widget _ring(String v, double fill, Color col, {double size = 88}) =>
      SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fill,
                strokeWidth: size * .1,
                strokeCap: StrokeCap.round,
                color: col,
                backgroundColor: context.c.trackOff,
              ),
            ),
            Text(
              v,
              style: TempoType.label.copyWith(
                fontSize: size * .26,
                color: context.c.text1,
              ),
            ),
          ],
        ),
      );

  Widget _body(BuildContext context) {
    final c = context.c, s = context.s;
    switch (_step) {
      case _Step.welcome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: TempoLockup(size: 34),
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                _ring('78', .78, s.recHigh),
                const SizedBox(width: 14),
                _ring('11.2', .53, s.strain[1]),
                const SizedBox(width: 14),
                _ring('91', .91, s.sleepChannel),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Know how ready you are, every morning.',
              style: TempoType.titleL.copyWith(
                fontSize: 34,
                height: 38 / 34,
                color: c.text1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recovery, strain and sleep from the watch or ring you already wear, measured against your own normal.',
              style: TempoType.body.c(c.text2),
            ),
            const SizedBox(height: 32),
            TempoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Used Tempo before?', style: TempoType.label.c(c.text1)),
                  const SizedBox(height: 4),
                  Text(
                    'Bring your history back from a backup.',
                    style: TempoType.bodyS.c(c.text2),
                  ),
                  const SizedBox(height: 12),
                  RestorePanel(onboarding: true, onRestored: _restored),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TempoIcon(TempoIcons.private, size: 18, color: c.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No account needed. Your health data stays on this phone.',
                    style: TempoType.bodyS.c(c.text2),
                  ),
                ),
              ],
            ),
          ],
        );
      case _Step.numbers:
        Widget card(Widget ring, String t, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TempoCard(
            child: Row(
              children: [
                ring,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t,
                        style: TempoType.label.copyWith(
                          fontSize: 17,
                          color: c.text1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: TempoType.bodyS.c(c.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Three numbers, one clear call',
              'Each morning Tempo turns last night and yesterday into what to do today.',
            ),
            const SizedBox(height: 24),
            card(
              _ring('78', .78, s.recHigh, size: 56),
              'Recovery',
              'How ready your body is, from sleep, resting heart rate and HRV.',
            ),
            card(
              _ring('11', .53, s.strain[1], size: 56),
              'Strain',
              'How much load your day added, 0 to 21, with a target sized to your recovery.',
            ),
            card(
              _ring('91', .91, s.sleepChannel, size: 56),
              'Sleep',
              'How well you slept against what you needed, and when to go to bed tonight.',
            ),
            const SizedBox(height: 6),
            Text(
              'The first 14 nights teach Tempo your normal. Nights already in ${_source.label} count, so you may start with real numbers.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ],
        );
      case _Step.connect:
        Widget row(String icon, Color col, String t, String sub) => Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TempoIcon(icon, size: 22, color: col),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: TempoType.body.c(c.text1)),
                    Text(sub, style: TempoType.bodyS.c(c.text2)),
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
              'Connect ${_source.label}',
              'Tempo reads what your watch, ring or other apps already save. It only reads, and nothing is uploaded.',
            ),
            const SizedBox(height: 24),
            CardList(
              children: [
                row(
                  TempoIcons.heartRate,
                  s.recLow,
                  'Heart rate and HRV',
                  'Strain, resting heart rate and recovery.',
                ),
                row(
                  TempoIcons.sleep,
                  s.sleepChannel,
                  'Sleep',
                  'Your nights and their stages.',
                ),
                row(
                  TempoIcons.hiit,
                  s.strain[1],
                  'Workouts and steps',
                  'Activity, your plan and Tempo Age.',
                ),
                row(
                  TempoIcons.spo2,
                  s.recHigh,
                  'Body signals · optional',
                  'SpO₂, breathing rate, temperature, weight and cycle.',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              DataSource.platformHealth == DataSource.appleHealth
                  ? 'On the next screen, turn on all categories. Apple doesn’t tell apps what you allowed, so Tempo checks what it can read right after.'
                  : 'Allow every category, plus past data and background access, so Tempo can learn from your history and stay current while closed.',
              style: TempoType.bodyS.c(c.text3),
            ),
          ],
        );
      case _Step.check:
        final check = _check;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              check == null ? 'Reading your history…' : 'Here’s what we found',
              check == null
                  ? 'Up to 90 days from ${_source.label}. This takes a moment the first time.'
                  : check.anything
                  ? 'From the last 90 days in ${_source.label}.'
                  : 'Nothing yet. Wear your watch today and tonight; Tempo reads it next time you open the app.',
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                color: s.recHigh,
                backgroundColor: c.trackOff,
              ),
            ),
            const SizedBox(height: 20),
            if (check != null) SourceCheckView(check: check),
          ],
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
              'A little about you',
              _weightFromHealth
                  ? 'For your heart-rate zones and strain. Weight is from ${_source.label}; check the rest.'
                  : 'For your heart-rate zones and strain. You can change these any time.',
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
                      'Max HR is estimated from your age. Tempo raises it if your watch sees higher in a hard effort; if you’ve seen a higher number yourself, enter it.',
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
      case _Step.goal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'What matters most?',
              'It shapes what Tempo suggests. Add a race or event any time in Plan → Goal.',
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                for (final g in sc.Goal.values)
                  Pressable(
                    selected: _p.goal == g,
                    label: goalLabel(g),
                    onTap: () => setState(() => _p = _p.copyWith(goal: g)),
                    child: AnimatedContainer(
                      duration: TempoMotion.fast,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surface1,
                        borderRadius: BorderRadius.circular(TempoRadii.lg),
                        border: Border.all(
                          color: _p.goal == g
                              ? s.strain[1]
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
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
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              goalSub(g),
                              overflow: TextOverflow.fade,
                              style: TempoType.caption.c(c.text2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            WorkoutsEditor(
              profile: _p,
              onChanged: (p) => setState(() => _p = p),
            ),
            const SizedBox(height: 28),
            AvailabilityEditor(
              profile: _p,
              onChanged: (p) => setState(() => _p = p),
            ),
            const SizedBox(height: 16),
          ],
        );
      case _Step.notify:
        Widget bubble(String time, Widget body) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: TempoMark(size: 22, color: c.text1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Tempo',
                          style: TempoType.caption.copyWith(
                            color: c.text1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(time, style: TempoType.caption.c(c.text3)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: TempoType.bodyS.c(c.text1),
                      child: body,
                    ),
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
              'One message a morning',
              'Your call for the day when you wake, and a nudge before bed. Nothing else, and you can turn either off in You → Notifications.',
            ),
            const SizedBox(height: 24),
            bubble(
              '7:02',
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Primed · 78%. ',
                      style: TextStyle(color: s.recHigh),
                    ),
                    const TextSpan(
                      text:
                          'Go for today’s tempo run, 35 min. In bed by 22:45.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Opacity(
              opacity: .8,
              child: bubble(
                '22:15',
                const Text(
                  'Wind down: in bed by 22:45 covers the 8 h 05 you need.',
                ),
              ),
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
        const SizedBox(height: 24),
        Text('Games you play', style: TempoType.label.c(c.text1)),
        const SizedBox(height: 4),
        Text(
          'Optional. Tempo suggests them on the right days, sized to how recovered you are.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final g in sc.Game.values)
              TempoChip(
                sc.gameName(g),
                height: 40,
                selected: _p.games.contains(g),
                onTap: () {
                  final games = {..._p.games};
                  games.contains(g) ? games.remove(g) : games.add(g);
                  setState(() => _p = _p.copyWith(games: games));
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
