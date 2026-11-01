import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../core/manual_activity.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// (+) → Add activity (U4): a session the watch didn't record. Its strain
/// is an estimate from how hard it felt, labelled as such.
class AddActivityScreen extends ConsumerStatefulWidget {
  const AddActivityScreen({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<AddActivityScreen> createState() => _AddState();
}

class _AddState extends ConsumerState<AddActivityScreen> {
  var _sport = sc.Sport.walking;
  var _daysAgo = 0;
  late TimeOfDay _at;
  var _minutes = 30;
  var _rpe = 4;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.now ?? DateTime.now();
    final t = n.subtract(const Duration(minutes: 30));
    _at = TimeOfDay(hour: t.hour, minute: (t.minute ~/ 5) * 5);
  }

  static const _rpeWords = {
    1: 'Very easy',
    2: 'Easy',
    3: 'Easy, could chat',
    4: 'Comfortable',
    5: 'Steady, a little breathless',
    6: 'Getting hard',
    7: 'Hard, short sentences',
    8: 'Very hard',
    9: 'Near max',
    10: 'All out',
  };

  DateTime get _start {
    final n = widget.now ?? DateTime.now();
    final d = DateTime(n.year, n.month, n.day - _daysAgo);
    return DateTime(d.year, d.month, d.day, _at.hour, _at.minute);
  }

  Future<void> _save() async {
    final start = _start;
    final now = widget.now ?? DateTime.now();
    if (start.add(Duration(minutes: _minutes)).isAfter(now)) {
      showTempoToast(context, 'That ends in the future: pick an earlier time');
      return;
    }
    setState(() => _saving = true);
    await addManualActivity(
      ref.read(dbProvider),
      sport: _sport,
      start: start,
      minutes: _minutes,
      rpe: _rpe,
    );
    ref.invalidate(todayProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    showTempoToast(context, '${sportLabel(_sport)} added · strain estimated');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final est = sc.strainFromTrimp(sc.trimpFromRpe(_rpe, _minutes));
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Add an activity'),
        Text(
          'For a session your watch didn’t record. Tempo estimates its strain '
          'from how long it was and how hard it felt, and counts any heart '
          'rate it did catch only once.',
          style: TempoType.bodyS.c(c.text2),
        ),
        const Overline('What'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in sportOrder)
              TempoChip(
                sportLabel(s),
                height: 36,
                selected: _sport == s,
                onTap: () => setState(() => _sport = s),
              ),
          ],
        ),
        const Overline('When'),
        TempoSegmented<int>(
          values: const [0, 1, 2],
          labels: const ['Today', 'Yesterday', '2 days ago'],
          selected: _daysAgo,
          onChanged: (v) => setState(() => _daysAgo = v),
        ),
        ListRow(
          'Started at',
          value: clockOf(_start),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _at);
            if (t != null) setState(() => _at = t);
          },
        ),
        Row(
          children: [
            Expanded(
              child: Text('How long', style: TempoType.label.c(c.text1)),
            ),
            TempoIconButton(
              TempoIcons.minus,
              label: 'Fewer minutes',
              onTap: _minutes <= 5 ? null : () => setState(() => _minutes -= 5),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '$_minutes min',
                textAlign: TextAlign.center,
                style: TempoType.label.c(c.text1).tnum,
              ),
            ),
            TempoIconButton(
              TempoIcons.plus,
              label: 'More minutes',
              onTap: _minutes >= 360
                  ? null
                  : () => setState(() => _minutes += 5),
            ),
          ],
        ),
        const Overline('How hard did it feel?'),
        Row(
          children: [
            Expanded(
              child: Text(
                '$_rpe · ${_rpeWords[_rpe]}',
                style: TempoType.label.c(c.text1),
              ),
            ),
            Text(
              '~${est.toStringAsFixed(1)} strain',
              style: TempoType.caption.c(c.text3).tnum,
            ),
          ],
        ),
        Slider(
          min: 1,
          max: 10,
          divisions: 9,
          value: _rpe.toDouble(),
          label: '$_rpe',
          semanticFormatterCallback: (v) => 'Effort ${v.round()} of 10',
          onChanged: (v) => setState(() => _rpe = v.round()),
        ),
        TempoButton(
          _saving ? 'Saving…' : 'Add activity',
          expand: true,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}
