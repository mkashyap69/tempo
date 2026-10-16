import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/longevity_service.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

final labsProvider = FutureProvider<(List<LabTest>, Profile)>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  return (await loadLabs(db), await loadAppProfile(db) ?? const Profile());
});

/// PhenoAge at the time of [t], for [p] whose age is today's.
double? phenoAt(LabTest t, Profile p) => sc.phenoAge(
  t.labs,
  p.age - DateTime.now().difference(t.date).inDays / 365.25,
);

/// Longevity → Blood tests: the nine routine markers PhenoAge uses.
class LabsScreen extends ConsumerWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final v = ref.watch(labsProvider).value;
    final db = ref.read(dbProvider);
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Blood tests'),
        Text(
          'Nine routine markers from a standard blood panel give a PhenoAge '
          '(Levine 2018). It joins Tempo Age as the Blood group: full weight '
          'for 6 months, then less until it drops out at 2 years.',
          style: TempoType.bodyS.c(c.text2),
        ),
        if (v != null && v.$1.isNotEmpty)
          CardList(
            children: [
              for (final t in v.$1)
                ListRow(
                  _date(t.date),
                  value: switch (phenoAt(t, v.$2)) {
                    final a? => 'PhenoAge ${a.toStringAsFixed(1)}',
                    null => 'Out of range',
                  },
                  onTap: () => _edit(context, db, t),
                ),
            ],
          ),
        TempoButton(
          'Add a blood test',
          expand: true,
          onTap: () => _edit(context, db, null),
        ),
        Text(
          'Stored only on this phone. A wellness estimate, not a diagnosis: '
          'talk to your doctor about your results.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, st.TempoDb db, LabTest? t) async {
    final r = await Navigator.of(context)
        .push<_LabResult>(MaterialPageRoute(builder: (_) => _LabForm(t)));
    if (r == null) return;
    if (r.delete && t != null) {
      await deleteLab(db, t.date);
    } else if (r.test != null) {
      await saveLab(db, r.test!);
    }
    await updateLongevity(db);
  }
}

String _date(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

final class _LabResult {
  const _LabResult({this.test, this.delete = false});
  final LabTest? test;
  final bool delete;
}

/// Plausible ranges, to catch unit mix-ups (e.g. glucose in mg/dL).
const _bounds = {
  'albumin': (20.0, 60.0),
  'creatinine': (20.0, 500.0),
  'glucose': (2.0, 30.0),
  'crp': (.01, 300.0),
  'lymphocytePct': (2.0, 80.0),
  'mcv': (60.0, 130.0),
  'rdw': (9.0, 30.0),
  'alp': (10.0, 1000.0),
  'wbc': (1.0, 50.0),
};

class _LabForm extends StatefulWidget {
  const _LabForm(this.initial);
  final LabTest? initial;

  @override
  State<_LabForm> createState() => _LabFormState();
}

class _LabFormState extends State<_LabForm> {
  late DateTime _date = widget.initial?.date ?? DateTime.now();
  late final _ctl = {
    for (final (k, _, _) in LabTest.fields)
      k: TextEditingController(
        text: widget.initial == null ? '' : '${widget.initial!.values[k]}',
      ),
  };

  double? _v(String k) =>
      double.tryParse(_ctl[k]!.text.trim().replaceAll(',', '.'));

  bool _ok(String k) {
    final v = _v(k);
    final (lo, hi) = _bounds[k]!;
    return v != null && v >= lo && v <= hi;
  }

  @override
  void dispose() {
    for (final t in _ctl.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = LabTest.fields.every((f) => _ok(f.$1));
    return TempoPage(
      gap: 14,
      children: [
        DetailHeader(
          title: widget.initial == null ? 'Add a blood test' : 'Blood test',
        ),
        CardList(
          children: [
            ListRow(
              'Date of the test',
              value: _date.toString().substring(0, 10),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ],
        ),
        for (final (k, name, unit) in LabTest.fields)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TempoType.label.c(c.text1)),
              const SizedBox(height: 6),
              TempoField(
                controller: _ctl[k]!,
                suffix: unit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                error: _ctl[k]!.text.isNotEmpty && !_ok(k),
                onChanged: (_) => setState(() {}),
              ),
              if (_ctl[k]!.text.isNotEmpty && !_ok(k))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '⚠ Expected ${_bounds[k]!.$1}–${_bounds[k]!.$2} $unit. Check the unit on your report.',
                    style: TempoType.caption.c(context.s.recLow),
                  ),
                ),
            ],
          ),
        TempoButton(
          'Save',
          expand: true,
          onTap: all
              ? () => Navigator.pop(
                  context,
                  _LabResult(
                    test: LabTest(
                      DateTime(_date.year, _date.month, _date.day),
                      LabTest.labsFrom({
                        for (final (k, _, _) in LabTest.fields) k: _v(k)!,
                      }),
                    ),
                  ),
                )
              : null,
        ),
        if (widget.initial != null)
          TempoButton(
            'Delete this test',
            kind: ButtonKind.text,
            expand: true,
            onTap: () => Navigator.pop(context, const _LabResult(delete: true)),
          ),
      ],
    );
  }
}
