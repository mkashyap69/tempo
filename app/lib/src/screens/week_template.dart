import 'package:flutter/material.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Long Sun · lift Mon, Thu · 2 hard" for You → Training.
String templateSummary(Profile p) {
  final parts = [
    if (p.longDay != null) 'long ${_dayShort[p.longDay! - 1]}',
    if (p.liftDays.isNotEmpty)
      'lift ${[for (final d in p.liftDays.toList()..sort()) _dayShort[d - 1]].join(', ')}',
    if (p.hardSessions != null) '${p.hardSessions} hard',
    if (p.dayMinutes.isNotEmpty) 'own minutes',
  ];
  if (parts.isEmpty) return 'Tempo’s choice';
  final s = parts.join(' · ');
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

/// You → Training → Week template (U3): which day is long, which days
/// are lifting, how many hard sessions, and minutes per day. Pops the
/// edited profile.
class WeekTemplateEditor extends StatefulWidget {
  const WeekTemplateEditor({super.key, required this.profile});
  final Profile profile;

  @override
  State<WeekTemplateEditor> createState() => _WeekTemplateState();
}

class _WeekTemplateState extends State<WeekTemplateEditor> {
  late var _p = widget.profile;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = [
      for (var d = 1; d <= 7; d++)
        if (_p.days.contains(d)) d,
    ];
    Widget section(String title, String sub, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(title, style: TempoType.label.c(c.text1)),
        const SizedBox(height: 2),
        Text(sub, style: TempoType.caption.c(c.text3)),
        const SizedBox(height: 10),
        child,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Week template', style: TempoType.titleL.c(c.text1)),
        const SizedBox(height: 6),
        Text(
          'Fix what matters to you; Tempo plans the rest and still adapts '
          'each morning to how you recovered.',
          style: TempoType.bodyS.c(c.text2),
        ),
        section(
          'Long session',
          'The long run or ride. Its neighbours stay easy.',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TempoChip(
                'Auto',
                height: 36,
                selected: _p.longDay == null,
                onTap: () =>
                    setState(() => _p = _p.copyWith(longDay: () => null)),
              ),
              for (final d in days)
                TempoChip(
                  _dayShort[d - 1],
                  height: 36,
                  selected: _p.longDay == d,
                  onTap: () => setState(
                    () => _p = _p.copyWith(
                      longDay: () => d,
                      liftDays: {..._p.liftDays}..remove(d),
                    ),
                  ),
                ),
            ],
          ),
        ),
        section(
          'Lifting days',
          'Always strength. Upper body the day before a hard or long session.',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in days)
                TempoChip(
                  _dayShort[d - 1],
                  height: 36,
                  selected: _p.liftDays.contains(d),
                  onTap: () => setState(() {
                    final l = {..._p.liftDays};
                    l.contains(d) ? l.remove(d) : l.add(d);
                    _p = _p.copyWith(
                      liftDays: l,
                      longDay: _p.longDay == d ? () => null : null,
                    );
                  }),
                ),
            ],
          ),
        ),
        section(
          'Hard sessions a week',
          'Intervals or tempo, never two days running. Auto follows your priority.',
          TempoSegmented<int>(
            values: const [-1, 0, 1, 2, 3],
            labels: const ['Auto', '0', '1', '2', '3'],
            selected: _p.hardSessions ?? -1,
            onChanged: (v) => setState(
              () => _p = _p.copyWith(hardSessions: () => v < 0 ? null : v),
            ),
          ),
        ),
        section(
          'Minutes per day',
          'Up to ${_p.maxMinutes} min unless you change a day. The long session may run longer for a race.',
          Column(
            children: [
              for (final d in days)
                _MinutesRow(
                  day: _dayNames[d - 1],
                  minutes: _p.prefs.minutesOn(d),
                  own: _p.dayMinutes.containsKey(d),
                  onChanged: (m) => setState(() {
                    final dm = {..._p.dayMinutes};
                    m == _p.maxMinutes ? dm.remove(d) : dm[d] = m;
                    _p = _p.copyWith(dayMinutes: dm);
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TempoButton(
          'Save',
          expand: true,
          onTap: () => Navigator.pop(context, _p),
        ),
      ],
    );
  }
}

class _MinutesRow extends StatelessWidget {
  const _MinutesRow({
    required this.day,
    required this.minutes,
    required this.own,
    required this.onChanged,
  });
  final String day;
  final int minutes;
  final bool own;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(day, style: TempoType.bodyS.c(c.text1))),
          TempoIconButton(
            TempoIcons.minus,
            label: '$day fewer minutes',
            onTap: minutes <= 15 ? null : () => onChanged(minutes - 15),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$minutes min',
              textAlign: TextAlign.center,
              style: TempoType.label.c(own ? c.text1 : c.text3).tnum,
            ),
          ),
          TempoIconButton(
            TempoIcons.plus,
            label: '$day more minutes',
            onTap: minutes >= 240 ? null : () => onChanged(minutes + 15),
          ),
        ],
      ),
    );
  }
}

/// You → Training → Injury (U3): what the plan should leave out.
Future<sc.TrainingLimit?> pickLimit(
  BuildContext context,
  sc.TrainingLimit current,
) => showTempoSheet<sc.TrainingLimit>(
  context,
  builder: (ctx) {
    final c = ctx.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Training around an injury', style: TempoType.titleL.c(c.text1)),
        const SizedBox(height: 6),
        Text(
          'Unlike a pause, your scores and baselines carry on: you’re well, '
          'just limited. The plan holds its size until you’re back. See a '
          'professional for anything that hurts.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const SizedBox(height: 16),
        for (final l in sc.TrainingLimit.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TempoCard(
              onTap: () => Navigator.pop(ctx, l),
              label: sc.limitName(l),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l == sc.TrainingLimit.none
                              ? 'No injury'
                              : sc.limitName(l),
                          style: TempoType.label.c(c.text1),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sc.limitDetail(l),
                          style: TempoType.caption.c(c.text2),
                        ),
                      ],
                    ),
                  ),
                  if (l == current) ...[
                    const SizedBox(width: 8),
                    TempoIcon(TempoIcons.check, size: 18, color: c.text1),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  },
);

/// "21:30" or "1:45:00" → seconds; null when it doesn't parse.
int? parseRaceTime(String s) {
  final parts = s.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final n = [for (final p in parts) int.tryParse(p)];
  if (n.any((x) => x == null || x < 0)) return null;
  final v = n.cast<int>();
  if (v.skip(1).any((x) => x >= 60)) return null;
  return v.length == 2 ? v[0] * 60 + v[1] : v[0] * 3600 + v[1] * 60 + v[2];
}

/// You → Training → Race time for paces (U5). Pops (metres, seconds), or
/// (0, 0) to clear.
Future<(double, int)?> pickRaceTime(BuildContext context, Profile p) {
  var metres = p.paceMetres ?? 5000;
  final ctl = TextEditingController(
    text: p.paceSeconds == null
        ? ''
        : sc.durationText(p.paceSeconds!.toDouble()),
  );
  return showTempoSheet<(double, int)>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        final secs = parseRaceTime(ctl.text);
        final vdot = secs == null || secs < 600
            ? null
            : sc.vdotFromRace(metres, secs.toDouble());
        final ok = vdot != null && vdot >= 20 && vdot <= 90;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('A recent race', style: TempoType.titleL.c(c.text1)),
            const SizedBox(height: 6),
            Text(
              'A race or all-out time trial from the last few months sets '
              'your paces for each heart-rate zone (Daniels’ VDOT). Heart rate '
              'stays the guide on hot, hilly or tired days.',
              style: TempoType.bodyS.c(c.text2),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in sc.raceMetres.entries)
                  TempoChip(
                    e.key,
                    height: 36,
                    selected: metres == e.value,
                    onTap: () => set(() => metres = e.value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TempoField(
              controller: ctl,
              label: 'Time (mm:ss or h:mm:ss)',
              keyboardType: TextInputType.datetime,
              error: ctl.text.isNotEmpty && !ok,
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              ok
                  ? 'Easy ${sc.paceText(sc.zonePace(2, vdot).slow, miles: !p.metric)}–${sc.paceText(sc.zonePace(2, vdot).fast, miles: !p.metric)}, threshold ${sc.paceText(sc.zonePace(4, vdot).fast, miles: !p.metric)} ${p.metric ? '/km' : '/mi'} · marathon about ${sc.durationText(sc.raceSeconds(vdot, 42195))}'
                  : 'For example 24:30 for a 5K.',
              style: TempoType.caption.c(c.text3).tnum,
            ),
            const SizedBox(height: 20),
            TempoButton(
              'Save',
              expand: true,
              onTap: ok ? () => Navigator.pop(ctx, (metres, secs)) : null,
            ),
            if (p.paceSeconds != null) ...[
              const SizedBox(height: 8),
              TempoButton(
                'Don’t show paces',
                kind: ButtonKind.ghost,
                expand: true,
                onTap: () => Navigator.pop(ctx, (0.0, 0)),
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// "5K 24:30" for the settings row.
String raceTimeSummary(Profile p) {
  if (p.paceMetres == null || p.paceSeconds == null) return 'Not set';
  final name = sc.raceMetres.entries
      .firstWhere(
        (e) => e.value == p.paceMetres,
        orElse: () => MapEntry(
          '${(p.paceMetres! / 1000).toStringAsFixed(1)} km',
          p.paceMetres!,
        ),
      )
      .key;
  return '$name ${sc.durationText(p.paceSeconds!.toDouble())}';
}
