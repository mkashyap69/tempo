import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/journal.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'insight_detail.dart';
import 'journal_customise.dart';
import 'nav.dart';

/// Check-ins needed before Insights show (the engine shrinks thin
/// evidence, so this can be lower than the old 30).
const journalInsightsAt = 14;

/// Days the impact engine looks back over.
const impactWindowDays = 180;

DateTime get _yesterday =>
    dayOf(DateTime.now()).subtract(const Duration(days: 1));

class JournalState {
  JournalState({
    required this.count,
    required this.config,
    required this.answered,
    required this.amounts,
    required this.checkedIn,
    required this.auto,
    required this.health,
    required this.fastHours,
    required this.experiment,
  });

  /// Days with a check-in.
  final int count;
  final JournalConfig config;

  /// Yesterday's yes/no answers and amounts or times (minutes of day).
  final Map<String, bool> answered;
  final Map<String, double> amounts;
  final bool checkedIn;

  /// Automatic entries for yesterday.
  final Map<String, bool> auto;

  /// Water and caffeine Health recorded yesterday, as suggestions.
  final Map<String, double> health;

  /// Overnight fast into yesterday (last meal the day before → first
  /// meal yesterday), when both are logged.
  final double? fastHours;
  final sc.Experiment? experiment;
}

final journalProvider = FutureProvider<JournalState>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final config = await loadJournalConfig(db);
  final y = _yesterday;
  final rows = await db.journalFor(y);
  final before = await db.journalFor(y.subtract(const Duration(days: 1)));
  final answered = <String, bool>{};
  final amounts = <String, double>{};
  for (final r in rows) {
    if (r.tag == sc.checkinTag) continue;
    final d = config.def(r.tag);
    if (d == null) continue;
    if (d.kind == sc.EntryKind.yesNo) {
      answered[r.tag] = r.value;
    } else if (r.amount != null) {
      amounts[r.tag] = r.amount!;
    }
  }
  final lastMeal = before
      .where((r) => r.tag == 'last_meal' && r.amount != null)
      .firstOrNull
      ?.amount;
  final days = await db.watchJournalDays().first;
  return JournalState(
    count: days,
    config: config,
    answered: answered,
    amounts: amounts,
    checkedIn: await journalCheckedIn(db, y),
    auto: await autoEntriesFor(db, y, config),
    health: await healthAmountsFor(db, y),
    fastHours: sc.overnightFastHours(
      lastMeal?.round(),
      amounts['first_meal']?.round(),
    ),
    experiment: await currentExperiment(db),
  );
});

/// Impact inputs over the window, loaded once per data change.
final impactDaysProvider = FutureProvider<List<sc.ImpactDay>>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final config = await loadJournalConfig(db);
  final to = _yesterday;
  return loadImpactDays(
    db,
    config,
    from: to.subtract(const Duration(days: impactWindowDays)),
    to: to,
  );
});

final impactsProvider =
    FutureProvider.family<(List<sc.Impact>, JournalConfig), sc.Outcome>((
      ref,
      outcome,
    ) async {
      final days = await ref.watch(impactDaysProvider.future);
      final config = await loadJournalConfig(ref.watch(dbProvider));
      final defs = [...config.asked, ...config.automatic];
      final list = sc.impacts(days, [
        for (final d in defs) behaviourFor(d),
      ], outcome);
      list.sort((a, b) {
        if (a.shown != b.shown) return a.shown ? -1 : 1;
        return b.effect.abs().compareTo(a.effect.abs());
      });
      return (list, config);
    });

String outcomeName(sc.Outcome o) => switch (o) {
  sc.Outcome.recovery => 'Recovery',
  sc.Outcome.sleepPerf => 'Sleep',
  sc.Outcome.hrv => 'HRV',
  sc.Outcome.rhr => 'Resting HR',
  sc.Outcome.sleptHours => 'Time asleep',
};

/// "−4 points", "+12 min", "−3 %".
String effectText(sc.Outcome o, double e) {
  final sign = e < 0 ? '−' : '+';
  final a = e.abs();
  return switch (o) {
    sc.Outcome.recovery || sc.Outcome.sleepPerf => '$sign${a.round()} points',
    sc.Outcome.hrv => '$sign${((math.exp(a) - 1) * 100).round()} %',
    sc.Outcome.rhr => '$sign${a.toStringAsFixed(1)} bpm',
    sc.Outcome.sleptHours => '$sign${(a * 60).round()} min',
  };
}

String confidenceWord(sc.ImpactConfidence c) => switch (c) {
  sc.ImpactConfidence.high => 'High confidence',
  sc.ImpactConfidence.moderate => 'Moderate confidence',
  sc.ImpactConfidence.low => 'Not consistent yet',
  sc.ImpactConfidence.none => 'No clear effect',
  sc.ImpactConfidence.notEnough => 'Not enough days',
};

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key, this.standalone = false});

  /// Pushed (back button) rather than a tab.
  final bool standalone;
  @override
  ConsumerState<JournalScreen> createState() => _JournalState();
}

class _JournalState extends ConsumerState<JournalScreen> {
  bool _insights = false;
  final _draft = <String, bool>{};
  final _amounts = <String, double?>{};

  @override
  Widget build(BuildContext context) {
    final j = ref.watch(journalProvider).value;
    final c = context.c;
    if (j == null) return Scaffold(backgroundColor: c.bg);
    final title = Row(
      children: [
        Expanded(
          child: Text(
            'Journal',
            style: widget.standalone
                ? TempoType.titleM.c(c.text1)
                : TempoType.pageTitle.c(c.text1),
          ),
        ),
        TempoBadge('${j.count} check-ins'),
      ],
    );
    return TempoPage(
      gap: 18,
      bottom: widget.standalone ? 48 : 100,
      children: [
        if (widget.standalone)
          DetailHeader(
            title: 'Journal',
            trailing: TempoBadge('${j.count} check-ins'),
          )
        else
          SizedBox(height: 44, child: title),
        TempoSegmented<bool>(
          values: const [false, true],
          labels: const ['Check-in', 'Insights'],
          selected: _insights,
          onChanged: (v) => setState(() => _insights = v),
        ),
        if (j.experiment != null) _ExperimentCard(j.experiment!, j.config),
        if (!_insights) ..._checkin(context, j) else _Insights(j),
      ],
    );
  }

  List<Widget> _checkin(BuildContext context, JournalState j) {
    final c = context.c;
    final answers = {...j.answered, ..._draft};
    final amounts = <String, double?>{
      for (final e in j.health.entries)
        if (!j.amounts.containsKey(e.key)) e.key: e.value,
      ...j.amounts,
      ..._amounts,
    };
    final asked = j.config.asked;
    final dirty = _draft.isNotEmpty || _amounts.isNotEmpty;
    final suggested = {
      for (final k in j.health.keys)
        if (!j.amounts.containsKey(k) && !_amounts.containsKey(k)) k,
    };
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yesterday, quickly', style: TempoType.titleM.c(c.text1)),
                const SizedBox(height: 4),
                Text(
                  'Tempo matches these against the night and morning after.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          TempoButton(
            'Customise',
            kind: ButtonKind.text,
            small: true,
            onTap: () => push(context, const JournalCustomiseScreen()),
          ),
        ],
      ),
      if (asked.isEmpty)
        const TempoEmpty('Nothing to ask. Switch entries on in Customise.')
      else
        CardList(
          children: [
            for (final d in asked)
              JournalEntryRow(
                d,
                answer: answers[d.key],
                amount: amounts[d.key],
                fromHealth: suggested.contains(d.key),
                onAnswer: (v) => setState(() => _draft[d.key] = v),
                onAmount: (v) => setState(() => _amounts[d.key] = v),
              ),
          ],
        ),
      if (j.fastHours != null)
        Text(
          'Overnight fast into yesterday: ${j.fastHours!.toStringAsFixed(1)} h',
          style: TempoType.bodyS.c(c.text2),
        ),
      if (j.auto.isNotEmpty) ...[
        const Overline('Automatic'),
        CardList(
          children: [
            for (final d in j.config.automatic)
              if (j.auto[d.key] case final v?)
                ListRow(
                  d.name,
                  sub: d.question,
                  chevron: false,
                  trailing: TempoIcon(
                    v ? TempoIcons.check : TempoIcons.close,
                    size: 18,
                    color: v ? context.s.recHigh : c.text3,
                    stroke: 2,
                  ),
                ),
          ],
        ),
        Text(
          'Filled in from your data, nothing to log.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
      TempoButton(
        j.checkedIn && !dirty ? 'Saved for yesterday' : 'Save check-in',
        expand: true,
        onTap: (j.checkedIn && !dirty) || (answers.isEmpty && amounts.isEmpty)
            ? null
            : () async {
                final db = ref.read(dbProvider);
                await saveCheckin(
                  db,
                  _yesterday,
                  j.config,
                  answers: {
                    for (final d in asked)
                      if (d.kind == sc.EntryKind.yesNo &&
                          answers[d.key] != null)
                        d.key: answers[d.key]!,
                  },
                  amounts: {
                    for (final d in asked)
                      if (d.kind != sc.EntryKind.yesNo &&
                          (amounts.containsKey(d.key) ||
                              j.amounts.containsKey(d.key)))
                        d.key: amounts[d.key],
                  },
                );
                setState(() {
                  _draft.clear();
                  _amounts.clear();
                });
                if (context.mounted) showTempoToast(context, 'Check-in saved');
              },
      ),
    ];
  }
}

String _hm(double m) {
  final x = m.round() % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

String _amountText(sc.JournalEntryDef d, double v) {
  final n = v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  return '$n ${d.unit ?? ''}'.trimRight();
}

/// One journal question: yes/no, an amount or a time (Journal, and the
/// morning check-in on Today).
class JournalEntryRow extends StatelessWidget {
  const JournalEntryRow(
    this.d, {
    super.key,
    required this.answer,
    required this.amount,
    required this.fromHealth,
    required this.onAnswer,
    required this.onAmount,
  });
  final sc.JournalEntryDef d;
  final bool? answer;
  final double? amount;
  final bool fromHealth;
  final ValueChanged<bool> onAnswer;
  final ValueChanged<double?> onAmount;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final Widget control = switch (d.kind) {
      sc.EntryKind.yesNo => YesNo(
        label: d.name,
        value: answer,
        onChanged: onAnswer,
      ),
      sc.EntryKind.amount => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TempoIconButton(
            TempoIcons.minus,
            label: 'Less ${d.name.toLowerCase()}',
            onTap: () {
              final v = (amount ?? 0) - d.step;
              onAmount(v <= 0 ? 0 : v);
            },
          ),
          SizedBox(
            width: 76,
            child: Text(
              amount == null ? '–' : _amountText(d, amount!),
              textAlign: TextAlign.center,
              style: TempoType.label.c(c.text1).tnum,
            ),
          ),
          TempoIconButton(
            TempoIcons.plus,
            label: 'More ${d.name.toLowerCase()}',
            onTap: () => onAmount(((amount ?? 0) + d.step).clamp(0, d.max)),
          ),
        ],
      ),
      sc.EntryKind.time => TempoButton(
        amount == null ? 'Set time' : _hm(amount!),
        kind: ButtonKind.secondary,
        small: true,
        onTap: () async {
          final init = amount == null
              ? const TimeOfDay(hour: 20, minute: 0)
              : TimeOfDay(
                  hour: amount!.round() ~/ 60 % 24,
                  minute: amount!.round() % 60,
                );
          final t = await showTimePicker(context: context, initialTime: init);
          if (t != null) onAmount((t.hour * 60 + t.minute).toDouble());
        },
      ),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: TempoType.body.c(c.text1)),
                Text(
                  fromHealth ? 'From Health · check and save' : d.question,
                  style: TempoType.caption.c(
                    fromHealth ? context.s.recHigh : c.text3,
                  ),
                ),
              ],
            ),
          ),
          control,
        ],
      ),
    );
  }
}

// ---- insights ---------------------------------------------------------------

class _Insights extends ConsumerStatefulWidget {
  const _Insights(this.j);
  final JournalState j;

  @override
  ConsumerState<_Insights> createState() => _InsightsState();
}

class _InsightsState extends ConsumerState<_Insights> {
  sc.Outcome _o = sc.Outcome.recovery;
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final j = widget.j;
    if (j.count < journalInsightsAt) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TempoCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TickRow(
                  count: journalInsightsAt,
                  filled: j.count,
                  color: c.text1,
                  height: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  'Insights unlock at $journalInsightsAt check-ins',
                  style: TempoType.titleM.c(c.text1),
                ),
                const SizedBox(height: 4),
                Text(
                  '${j.count} so far. Automatic entries count from day one.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TempoCard(
            color: Colors.transparent,
            border: c.line,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('What you’ll see'),
                const SizedBox(height: 10),
                Text(
                  '“After alcohol, recovery runs about 6 points lower (likely 3 to 9)” — adjusted for your other entries and the day’s strain, with how sure Tempo is.',
                  style: TempoType.body.c(c.text2),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final v = ref.watch(impactsProvider(_o)).value;
    final shown = v?.$1.where((i) => i.shown).toList() ?? const [];
    final rest = v?.$1.where((i) => !i.shown).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final o in sc.Outcome.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TempoChip(
                    outcomeName(o),
                    selected: o == _o,
                    height: 36,
                    onTap: () => setState(() => _o = o),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (v == null)
          const SizedBox(height: 200)
        else if (shown.isEmpty)
          TempoEmpty(
            'No clear patterns on ${outcomeName(_o).toLowerCase()} yet. Tempo only shows an effect when its likely range stays on one side of zero and both halves of your history agree.',
          )
        else
          for (final i in shown) ...[
            _ImpactCard(i, v.$2),
            const SizedBox(height: 12),
          ],
        if (v != null && rest.isNotEmpty) ...[
          const SizedBox(height: 6),
          TempoButton(
            _more ? 'Hide the rest' : 'Not clear yet (${rest.length})',
            kind: ButtonKind.text,
            onTap: () => setState(() => _more = !_more),
          ),
          if (_more)
            CardList(
              children: [
                for (final i in rest)
                  ListRow(
                    v.$2.def(i.key)?.name ?? i.key,
                    value: confidenceWord(i.confidence),
                    sub: '${i.nYes} with · ${i.nNo} without',
                    onTap: () => push(
                      context,
                      InsightDetailScreen(tag: i.key, outcome: _o),
                    ),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 12),
        Text(
          'Patterns, not proof: Tempo adjusts for your other entries, the day’s strain and weekends, but can’t rule out everything. An experiment is the surest test.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard(this.i, this.config);
  final sc.Impact i;
  final JournalConfig config;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = config.def(i.key);
    final name = d?.name ?? i.key;
    final tone = i.helps ? context.s.recHigh : context.s.recLow;
    final range =
        'likely ${effectText(i.outcome, i.low)} to ${effectText(i.outcome, i.high)}';
    return TempoCard(
      label: name,
      onTap: () =>
          push(context, InsightDetailScreen(tag: i.key, outcome: i.outcome)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Overline(name)),
              TempoBadge(confidenceWord(i.confidence)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${outcomeName(i.outcome)} ${effectText(i.outcome, i.effect)}${d == null ? '' : doseWords(d)}',
            style: TempoType.titleM.c(tone).tnum,
          ),
          const SizedBox(height: 2),
          Text(range, style: TempoType.bodyS.c(c.text2).tnum),
          const SizedBox(height: 10),
          EffectBar(i),
          const SizedBox(height: 6),
          Text(
            '${i.nYes} days with · ${i.nNo} without',
            style: TempoType.caption.c(c.text3).tnum,
          ),
        ],
      ),
    );
  }
}

/// The effect and its likely range on a bar centred on zero.
class EffectBar extends StatelessWidget {
  const EffectBar(this.i, {super.key});
  final sc.Impact i;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final span = [
      i.low.abs(),
      i.high.abs(),
      sc.minEffect(i.outcome) * 4,
    ].reduce((a, b) => a > b ? a : b);
    final tone = i.helps ? context.s.recHigh : context.s.recLow;
    return SizedBox(
      height: 16,
      child: LayoutBuilder(
        builder: (_, box) {
          final w = box.maxWidth;
          double x(double v) => w / 2 + v / span * w / 2;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                height: 4,
                child: ColoredBox(color: c.trackOff),
              ),
              Positioned(
                left: x(i.low),
                width: (x(i.high) - x(i.low)).clamp(2, w),
                top: 4,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Positioned(
                left: x(i.effect) - 2,
                width: 4,
                top: 1,
                height: 14,
                child: ColoredBox(color: tone),
              ),
              Positioned(
                left: w / 2 - .5,
                width: 1,
                top: 0,
                height: 16,
                child: ColoredBox(color: c.text2),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---- experiments --------------------------------------------------------------

class _ExperimentCard extends ConsumerWidget {
  const _ExperimentCard(this.e, this.config);
  final sc.Experiment e;
  final JournalConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final name = config.def(e.key)?.name ?? e.key;
    final day = e.dayOn(DateTime.now());
    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Experiment')),
              TempoBadge('Day $day of ${e.days}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(experimentTitle(e, name), style: TempoType.titleM.c(c.text1)),
          const SizedBox(height: 4),
          Text(
            'Log it each morning. Tempo compares these ${e.days} days with the ${e.days} before, adjusted for strain and weekends.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TempoButton(
              'Stop early',
              kind: ButtonKind.text,
              small: true,
              onTap: () async {
                final ok = await confirmSheet(
                  context,
                  title: 'Stop this experiment?',
                  body: 'The days so far are kept and analysed.',
                  action: 'Stop',
                );
                if (ok) await stopExperiment(ref.read(dbProvider));
              },
            ),
          ),
        ],
      ),
    );
  }
}

String experimentTitle(sc.Experiment e, String name) => e.doIt
    ? '${e.days} days of ${name.toLowerCase()}'
    : '${e.days} days without ${name.toLowerCase()}';

/// Offers a 14-day experiment on [d] (do it or skip it).
Future<void> offerExperiment(
  BuildContext context,
  WidgetRef ref,
  sc.JournalEntryDef d, {
  required bool suggestAvoid,
}) async {
  final doIt = await pickOption<bool>(
    context,
    title: 'Try 14 days…',
    options: [!suggestAvoid, suggestAvoid],
    selected: !suggestAvoid,
    label: (v) => v
        ? 'With ${d.name.toLowerCase()} every day'
        : 'Without ${d.name.toLowerCase()}',
  );
  if (doIt == null) return;
  await startExperiment(ref.read(dbProvider), d.key, doIt);
  if (context.mounted) showTempoToast(context, 'Experiment started');
}
