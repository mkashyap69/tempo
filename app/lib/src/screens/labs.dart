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
          _LatestRead(test: v.$1.first, male: v.$2.male)
        else
          TempoEmpty(
            'Add your last blood test: Tempo shows which markers are in '
            'range, which to recheck and which to raise with your doctor, '
            'and adds a PhenoAge to Tempo Age.',
            kind: EmptyKind.trend,
          ),
        const _AskTheLab(),
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

/// What to ask for so one blood draw covers all nine markers (U1).
class _AskTheLab extends StatelessWidget {
  const _AskTheLab();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget row(String panel, String gives) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(panel, style: TempoType.label.c(c.text1)),
          const SizedBox(height: 2),
          Text(gives, style: TempoType.bodyS.c(c.text2)),
        ],
      ),
    );
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('What to ask the lab for'),
          row(
            'Complete blood count with differential',
            'White cells, lymphocytes %, MCV, RDW',
          ),
          row(
            'Metabolic panel, fasting',
            'Albumin, creatinine, glucose, alkaline phosphatase (ALP)',
          ),
          row(
            'High-sensitivity CRP (hs-CRP)',
            'A standard CRP often reads "under 5", which PhenoAge can’t use',
          ),
        ],
      ),
    );
  }
}

/// The newest test's nine markers by how far each sits from common adult
/// ranges (D2). A wellness read, not a diagnosis.
class _LatestRead extends StatelessWidget {
  const _LatestRead({required this.test, required this.male});
  final LabTest test;
  final bool male;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final reads = sc.readLabs(test.labs, male: male);
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    Widget bucket(sc.LabBucket b, String title, String sub, Color color) {
      final xs = [
        for (final r in reads)
          if (r.bucket == b) r,
      ];
      if (xs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$title · ${xs.length}',
                  style: TempoType.label.c(c.text1),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(sub, style: TempoType.caption.c(c.text3)),
            for (final r in xs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: TempoType.bodyS.c(c.text1)),
                          Text(r.note, style: TempoType.caption.c(c.text2)),
                        ],
                      ),
                    ),
                    Text(
                      '${fmt(r.value)} ${r.unit}',
                      style: TempoType.bodyS.c(c.text1).tnum,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final ask = reads.where((r) => r.bucket == sc.LabBucket.askDoctor).length;
    final recheck = reads.where((r) => r.bucket == sc.LabBucket.recheck).length;
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline('Latest test · ${_date(test.date)}'),
          const SizedBox(height: 8),
          Text(
            ask == 0 && recheck == 0
                ? 'All nine markers are in range.'
                : '${9 - ask - recheck} of 9 in range'
                      '${ask == 0 ? '' : ' · $ask to ask your doctor about'}'
                      '${recheck == 0 ? '' : ' · $recheck to recheck'}',
            style: TempoType.titleM.c(c.text1),
          ),
          bucket(
            sc.LabBucket.askDoctor,
            'Ask your doctor',
            'Well outside the usual adult range.',
            s.recLow,
          ),
          bucket(
            sc.LabBucket.recheck,
            'Recheck',
            'Just outside the usual range. Look again at your next test.',
            s.recMid,
          ),
          bucket(
            sc.LabBucket.inRange,
            'In range',
            'Inside the usual adult range.',
            s.recHigh,
          ),
          const SizedBox(height: 12),
          Text(
            'Typical adult ranges; where your lab’s report gives its own '
            'range, go by that. A wellness read, not a diagnosis.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}
