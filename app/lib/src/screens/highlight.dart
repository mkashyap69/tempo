import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart' show dayOf;
import '../core/everyday.dart' show signalName;
import '../core/home_widgets.dart';
import '../core/journal.dart';
import '../core/profile.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'baselines.dart';
import 'coach.dart' show CoachTab, openCoachAt;
import 'everyday_cards.dart';
import 'journal.dart';
import 'longevity.dart';
import 'nav.dart';
import 'recovery.dart';
import 'sleep.dart';
import 'strain.dart';
import 'strength_log.dart';
import 'weekly_review.dart';

/// One shown insight as kept in [Keys.highlightLog].
typedef ShownInsight = ({String kind, String key, DateTime day, String title});

Future<List<ShownInsight>> loadInsightLog(st.TempoDb db) async {
  try {
    final raw = await db.setting(Keys.highlightLog);
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final e in (jsonDecode(raw) as List).cast<List<dynamic>>())
        (
          kind: e[0] as String,
          key: e[1] as String,
          day: DateTime.parse(e[2] as String),
          title: e.length > 3 ? e[3] as String : '',
        ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _logInsight(st.TempoDb db, sc.Highlight h, DateTime day) async {
  final log = [...await loadInsightLog(db)];
  if (log.any((s) => s.key == h.key && st.dateKey(s.day) == st.dateKey(day))) {
    return;
  }
  log.add((kind: h.kind.name, key: h.key, day: day, title: h.title));
  final keep = log.length > 60 ? log.sublist(log.length - 60) : log;
  await db.putSetting(
    Keys.highlightLog,
    jsonEncode([
      for (final s in keep) [s.kind, s.key, st.dateKey(s.day), s.title],
    ]),
  );
}

/// Today's facts for the insight ranker, from what the app already loads.
Future<sc.HighlightFacts> highlightFacts(
  st.TempoDb db,
  Ref ref,
  TodayData t,
) async {
  final body = await ref.watch(bodySignalsProvider.future);
  final rhythm = await ref.watch(rhythmProvider.future);
  final move = await ref.watch(movementProvider.future);
  final now = DateTime.now();

  ({String key, String name, String effect, bool hurts})? impact;
  try {
    final (list, config) = await ref.watch(
      impactsProvider(sc.Outcome.recovery).future,
    );
    final top = list.where(
      (i) =>
          i.shown &&
          (i.confidence == sc.ImpactConfidence.high ||
              i.confidence == sc.ImpactConfidence.moderate),
    );
    if (top.isNotEmpty) {
      final i = top.first;
      impact = (
        key: i.key,
        name: config.def(i.key)?.name ?? i.key,
        effect: '${effectText(i.outcome, i.effect)} on Recovery',
        hurts: !i.helps,
      );
    }
  } catch (_) {}

  ({String key, String name, String result})? done;
  final past = await loadPastExperiments(db);
  if (past.isNotEmpty) {
    final e = past.first;
    final since = dayOf(now).difference(dayOf(e.end)).inDays;
    if (since >= 0 && since <= 3) {
      final config = await loadJournalConfig(db);
      done = (
        key: e.key,
        name: config.def(e.key)?.name ?? e.key,
        result:
            '14 days of ${e.doIt ? 'doing it' : 'going without'} are in. See what it did to your recovery and sleep.',
      );
    }
  }

  double? ageDelta;
  String? ageLever;
  try {
    final d = await ref.watch(longevityProvider.future);
    final w = d.weekAgo, l = d.latest;
    if (w != null && l != null) {
      ageDelta = l.tempoAge - w.tempoAge;
      if (d.changes.isNotEmpty) ageLever = leverName(d.changes.first.$1);
    }
  } catch (_) {}

  final prior = t.history.take(90);
  double? lowest(Iterable<double?> xs) {
    final v = xs.whereType<double>();
    return v.length < 30 ? null : v.reduce((a, b) => a < b ? a : b);
  }

  double? highest(Iterable<double?> xs) {
    final v = xs.whereType<double>();
    return v.length < 30 ? null : v.reduce((a, b) => a > b ? a : b);
  }

  int? strengthGap;
  if (t.profile.likes.contains(sc.Sport.strength)) {
    final ws = await db.workoutsBetween(
      now.subtract(const Duration(days: 30)),
      now,
    );
    final last = ws
        .where((w) => w.sport == 'strength')
        .map((w) => st.fromTs(w.start))
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    strengthGap = last == null ? 30 : dayOf(now).difference(dayOf(last)).inDays;
  }

  return sc.HighlightFacts(
    bodyOff: body.level == sc.BodyLevel.rest
        ? const []
        : [for (final r in body.off) signalName(r.key)],
    debtHours: t.debt,
    sri: rhythm.sri,
    jetlagMinutes: rhythm.jetlag?.minutes,
    stillMinutes: move.still?.minutes,
    briskAvg: move.briskAvg,
    weekday: now.weekday,
    impact: impact,
    experimentDone: done,
    load: t.load.status,
    loadPercent: t.load.status == sc.LoadStatus.learning
        ? null
        : t.load.percentVsNormal,
    ageDelta: ageDelta,
    ageLever: ageLever,
    rhr: t.score?.rhr,
    rhrLow: lowest(prior.map((d) => d.rhr)),
    hrv: t.score?.hrv,
    hrvHigh: highest(prior.map((d) => d.hrv)),
    strengthGapDays: strengthGap,
  );
}

/// Today's one insight, or null (rest days, Mondays, nothing new).
final todayHighlightProvider = FutureProvider<sc.Highlight?>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final t = await ref.watch(todayProvider.future);
  if (t.firstDay || t.calibrating || t.stale) return null;
  final now = DateTime.now();
  final facts = await highlightFacts(db, ref, t);
  final log = await loadInsightLog(db);
  final pick = sc.pickHighlight(
    sc.highlightCandidates(facts),
    [for (final s in log) (kind: s.kind, key: s.key, day: s.day)],
    now,
    restDay: t.restDay || t.state == sc.DayState.rest,
    monday: now.weekday == DateTime.monday,
  );
  if (pick != null) await _logInsight(db, pick, dayOf(now));
  return pick;
});

Color _tagColor(BuildContext context, sc.HighlightKind k) => switch (k) {
  sc.HighlightKind.sleepDebt ||
  sc.HighlightKind.regularity ||
  sc.HighlightKind.socialJetlag => context.s.sleepChannel,
  sc.HighlightKind.bodySignal => context.s.recMid,
  sc.HighlightKind.load => context.s.loadBuilding,
  sc.HighlightKind.stillStretch ||
  sc.HighlightKind.brisk => context.s.strain[2],
  sc.HighlightKind.personalBest => context.s.recHigh,
  _ => context.c.text2,
};

/// Runs a card's action: every insight lands somewhere real.
Future<void> runInsightAction(
  BuildContext context,
  WidgetRef ref,
  sc.HighlightAction a,
) async {
  switch (a) {
    case sc.HighlightAction.signals:
      await push(context, const RecoveryScreen());
    case sc.HighlightAction.tonight || sc.HighlightAction.sleep:
      await push(context, const SleepScreen());
    case sc.HighlightAction.experiment || sc.HighlightAction.tryExperiment:
      await push(context, const JournalScreen(standalone: true));
    case sc.HighlightAction.week:
      openCoachAt(context, CoachTab.week);
    case sc.HighlightAction.bedtimeNudge:
      final db = ref.read(dbProvider);
      await db.putSetting(Keys.bedtimeNudge, '30');
      await rescheduleNotifications(db);
      if (context.mounted) {
        showTempoToast(context, 'Bedtime nudge on, 30 min before bed');
      }
    case sc.HighlightAction.tempoAge:
      await push(context, const LongevityScreen(standalone: true));
    case sc.HighlightAction.day:
      await push(context, const StrainScreen());
    case sc.HighlightAction.picks:
      await openLive(context, ref, plan: sc.sessionTemplate('easy_walk'));
    case sc.HighlightAction.trend:
      await push(context, const BaselinesScreen());
    case sc.HighlightAction.logStrength:
      await push(context, const StrengthLogScreen());
  }
}

/// Today's insight: one card, one action.
class TodayInsightCard extends ConsumerWidget {
  const TodayInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(todayHighlightProvider).value;
    if (h == null) return const SizedBox.shrink();
    final c = context.c;
    final tag = _tagColor(context, h.kind);
    return TempoCard(
      label: 'Today’s insight: ${h.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Today’s insight')),
              TempoBadge(h.tag, color: tag),
            ],
          ),
          const SizedBox(height: 10),
          Text(h.title, style: TempoType.titleM.c(c.text1).tnum),
          const SizedBox(height: 4),
          Text(h.body, style: TempoType.bodyS.c(c.text2).tnum),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TempoButton(
              h.actionLabel,
              small: true,
              onTap: () => runInsightAction(context, ref, h.action),
            ),
          ),
        ],
      ),
    );
  }
}

/// Monday on Today: last week in review, until opened or put away.
class WeekReviewCard extends ConsumerWidget {
  const WeekReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    if (now.weekday != DateTime.monday) return const SizedBox.shrink();
    final seen = ref.watch(settingProvider(Keys.weekCardDone));
    if (!seen.hasValue || seen.value == st.dateKey(now)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    Future<void> open() async {
      await ref.read(dbProvider).putSetting(Keys.weekCardDone, st.dateKey(now));
      if (context.mounted) await push(context, const WeeklyReviewScreen());
    }

    return TempoCard(
      label: 'Last week in review',
      onTap: open,
      child: Row(
        children: [
          TempoIcon(TempoIcons.calendar, size: 22, color: c.text1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Monday'),
                const SizedBox(height: 4),
                Text('Your week in review', style: TempoType.titleM.c(c.text1)),
                const SizedBox(height: 2),
                Text(
                  'How last week went, what Tempo Age did, and next week’s plan.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 18, color: c.text3, stroke: 2),
        ],
      ),
    );
  }
}

/// Progress: what your journal and Tempo have found, newest first.
class DiscoveriesSection extends ConsumerWidget {
  const DiscoveriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impacts = ref.watch(impactsProvider(sc.Outcome.recovery)).value;
    final j = ref.watch(journalProvider).value;
    final log = ref.watch(_logProvider).value ?? const [];
    final c = context.c, s = context.s;
    final found = [
      if (impacts != null)
        for (final i in impacts.$1.where((i) => i.shown).take(3))
          (i, impacts.$2.def(i.key)?.name ?? i.key),
    ];
    final earlier = log.reversed
        .where((e) => e.title.isNotEmpty)
        .take(found.isEmpty ? 4 : 2)
        .toList();
    final rows = <Widget>[
      for (final (i, name) in found)
        ListRow(
          name,
          sub: confidenceWord(i.confidence),
          trailing: Text(
            '${effectText(i.outcome, i.effect)} recovery',
            style: TempoType.bodyS.c(i.helps ? s.recHigh : s.recLow).tnum,
          ),
          onTap: () => push(context, const JournalScreen(standalone: true)),
        ),
      if (j?.experiment case final e?)
        ListRow(
          'Experiment: ${j!.config.def(e.key)?.name ?? e.key}',
          sub: 'Day ${e.dayOn(DateTime.now())} of ${e.days}',
          onTap: () => push(context, const JournalScreen(standalone: true)),
        ),
      for (final e in earlier)
        ListRow(e.title, sub: 'Insight · ${_ago(e.day)}', chevron: false),
    ];
    return Section(
      title: 'Discoveries',
      trailing: Pressable(
        label: 'Journal',
        onTap: () => push(context, const JournalScreen(standalone: true)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('Journal ›', style: TempoType.bodyS.c(c.text2)),
        ),
      ),
      child: rows.isEmpty
          ? TempoCard(
              child: Text(
                (j?.count ?? 0) < journalInsightsAt
                    ? 'Check in each morning: after $journalInsightsAt check-ins (${j?.count ?? 0} so far) Tempo shows what your habits do to your sleep and recovery.'
                    : 'Nothing clear yet. Keep checking in; patterns firm up over weeks.',
                style: TempoType.bodyS.c(c.text2),
              ),
            )
          : CardList(
              children: [
                for (final (k, r) in rows.indexed) ...[
                  if (k > 0) const Hair(),
                  r,
                ],
              ],
            ),
    );
  }

  static String _ago(DateTime d) {
    final n = dayOf(DateTime.now()).difference(dayOf(d)).inDays;
    return n == 0
        ? 'today'
        : n == 1
        ? 'yesterday'
        : '$n days ago';
  }
}

final _logProvider = dbQuery((db, _) => loadInsightLog(db));
