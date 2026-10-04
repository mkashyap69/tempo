import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/profile.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/meter.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'nav.dart';
import 'shared.dart';

/// Suggested workout for today: structure, where it lands, why, and the
/// easier / harder alternatives.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key});

  Future<void> _replace(WidgetRef ref, sc.Session to, String why) async {
    final db = ref.read(dbProvider);
    final day = dayOf(DateTime.now());
    final row = await db.planDay(day);
    await db.putPlanDay(
      st.PlanDaysCompanion.insert(
        date: st.dateKey(day),
        session: jsonEncode(to.toJson()),
        original: Value(row?.original ?? row?.session),
        reason: Value('· $why'),
        adaptedAt: Value(st.toTs(DateTime.now())),
        general: row?.general ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todayProvider).value;
    if (t == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final p = t.plan ?? sc.sessionTemplate('rest');
    final general = t.planRow?.general ?? t.calibrating;
    final adds = planAdds(t);
    final hrMax = t.hrMax;
    final rest = t.score?.rhr ?? 60;
    String bpm(int z) {
      final r = sc.zoneRange(z, hrMax);
      return '${r.lo}–${r.hi} bpm';
    }

    // Collapse the structure into rows (warm-up, reps, recover, cool-down).
    final rows = <(String, String, int, String)>[];
    final segs = p.segments;
    if (segs.isNotEmpty) {
      final reps = <sc.Segment>[];
      for (var i = 1; i < segs.length - 1; i++) {
        reps.add(segs[i]);
      }
      final work = reps.where((x) => x.zone >= 3).toList();
      final easy = reps.where((x) => x.zone < 3).toList();
      if (segs.length >= 3) {
        rows.add((
          'Warm-up',
          '${segs.first.minutes}′',
          segs.first.zone,
          bpm(segs.first.zone),
        ));
        if (work.isNotEmpty) {
          rows.add((
            '${work.length} × Work',
            '${work.first.minutes}′ each',
            work.first.zone,
            bpm(work.first.zone),
          ));
        }
        if (easy.isNotEmpty && work.isNotEmpty) {
          rows.add((
            '${easy.length} × Recover',
            '${easy.first.minutes}′ each',
            easy.first.zone,
            bpm(easy.first.zone),
          ));
        }
        if (work.isEmpty) {
          rows.add((
            'Main set',
            '${reps.fold(0, (a, x) => a + x.minutes)}′',
            reps.first.zone,
            bpm(reps.first.zone),
          ));
        }
        rows.add((
          'Cool-down',
          '${segs.last.minutes}′',
          segs.last.zone,
          bpm(segs.last.zone),
        ));
      } else {
        for (final x in segs) {
          rows.add(('Main set', '${x.minutes}′', x.zone, bpm(x.zone)));
        }
      }
    }
    final easierKey = sc.easierKeyFor(p);
    final harderKey = sc.harderKeyFor(p);
    final easier = easierKey == p.key
        ? null
        : sc.fitMinutes(sc.sessionTemplate(easierKey), t.profile.maxMinutes);
    final harder = harderKey == null || harderKey == p.key
        ? null
        : sc.fitMinutes(sc.sessionTemplate(harderKey), t.profile.maxMinutes);
    double est(sc.Session x) => sc.sessionStrain(
      x,
      hrMax: hrMax,
      hrRest: rest,
      dayTrimp: t.score?.trimp ?? 0,
    );
    final lo = (adds - 1).clamp(0.5, 21.0), hi = adds + 1;

    Widget alt(String label, sc.Session x) => Expanded(
      child: TempoCard(
        padding: const EdgeInsets.all(14),
        onTap: () async {
          await _replace(ref, x, 'Swapped to ${x.title.toLowerCase()} by you.');
          if (context.mounted) {
            showTempoToast(context, 'Today is now ${x.title.toLowerCase()}');
          }
        },
        label: '$label: ${x.title}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(label),
            const SizedBox(height: 8),
            Text(x.title, style: TempoType.label.c(c.text1)),
            const SizedBox(height: 8),
            IntervalBars(
              segments: [for (final g in x.segments) (g.minutes, g.zone)],
              height: 20,
              base: 8,
              step: 2.5,
            ),
            const SizedBox(height: 8),
            Text(
              '${x.minutes} min · +${(est(x) - 1).clamp(1, 21).round()} to +${(est(x) + 1).round()}',
              style: TempoType.caption.c(c.text2).tnum,
            ),
          ],
        ),
      ),
    );

    return TempoPage(
      gap: 22,
      bottom: 24,
      footer: p.isRest
          ? null
          : TempoButton(
              'Start ${p.title.toLowerCase()}',
              icon: TempoIcons.play,
              expand: true,
              onTap: () => openLive(context, ref, plan: p),
            ),
      children: [
        DetailHeader(
          title: '',
          center: TempoBadge(general ? 'General · calibrating' : 'Personal'),
          trailing: TempoIconButton(
            TempoIcons.swap,
            label: 'Swap workout type',
            stroke: 1.75,
            onTap: () async {
              final sport = await pickOption<sc.Sport>(
                context,
                title: 'Swap to',
                options: sportOrder,
                label: sportLabel,
                selected: p.sport,
              );
              if (sport == null) return;
              final key = p.isHard
                  ? (sc.hardKeyFor(sport) ?? _easy(sport))
                  : _easy(sport);
              await _replace(
                ref,
                sc.fitMinutes(sc.sessionTemplate(key), t.profile.maxMinutes),
                'Swapped to ${sportLabel(sport).toLowerCase()} by you.',
              );
            },
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline('Suggested · ${sportLabel(p.sport)}'),
            const SizedBox(height: 6),
            Text(
              p.title,
              style: TempoType.titleL.copyWith(
                fontSize: 30,
                height: 36 / 30,
                color: c.text1,
              ),
            ),
          ],
        ),
        if (p.isRest)
          const TempoEmpty(
            'Today is a rest day. A walk is fine; keep strain under the cap.',
          )
        else ...[
          Row(
            children: [
              Expanded(child: Stat('Duration', '${p.minutes}', unit: ' min')),
              Expanded(
                child: Stat(
                  'Zones',
                  p.zones.replaceAll('Z1–', 'Z2–').replaceAll('Z2–Z2', 'Z2'),
                ),
              ),
              Expanded(
                child: Stat(
                  'Adds strain',
                  '+${lo.round()}–${hi.round()}',
                  color: s.strain[2],
                ),
              ),
            ],
          ),
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Interval structure',
                        style: TempoType.caption.c(c.text3),
                      ),
                    ),
                    Text(
                      '${p.minutes}′',
                      style: TempoType.caption.c(c.text3).tnum,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                IntervalBars(
                  segments: [for (final g in p.segments) (g.minutes, g.zone)],
                  height: 56,
                  base: 12,
                  step: 10,
                ),
                const SizedBox(height: 6),
                for (final (name, dur, z, range) in rows)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TempoType.label.c(c.text1),
                              ),
                            ),
                            Text(dur, style: TempoType.label.c(c.text1).tnum),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: s.zoneColor(z),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Z$z ${sc.zoneNames[z - 1]}',
                                style: TempoType.bodyS.c(c.text2),
                              ),
                            ),
                            Text(range, style: TempoType.bodyS.c(c.text3).tnum),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TempoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Where it lands today'),
                const SizedBox(height: 12),
                TargetStrip(
                  value: t.strain,
                  max: 21,
                  lo: t.target.lo,
                  hi: t.target.hi,
                  color: s.strain[0],
                  extra: adds,
                  extraColor: s.strain[2],
                  height: 16,
                  marker: false,
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: n1(t.strain),
                        style: TextStyle(color: c.text1),
                      ),
                      const TextSpan(text: ' now + session ≈ '),
                      TextSpan(
                        text: '${n1(t.strain + lo)}–${n1(t.strain + hi)}',
                        style: TextStyle(color: c.text1),
                      ),
                      TextSpan(
                        text: t.target.cap
                            ? ', against today’s cap of ${t.target.hi.round()}.'
                            : t.strain + adds >= t.target.lo &&
                                  t.strain + adds <= t.target.hi + .5
                            ? ', inside today’s ${t.target.lo.round()}–${t.target.hi.round()} target.'
                            : ', against today’s ${t.target.lo.round()}–${t.target.hi.round()} target.',
                      ),
                    ],
                  ),
                  style: TempoType.bodyS.c(c.text2).tnum,
                ),
              ],
            ),
          ),
        ],
        Section(
          title: 'Why this, today',
          child: CardList(
            children: [
              for (final (g, col, text) in _whyRows(context, t, general))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        child: Text(
                          g,
                          style: TextStyle(fontSize: 12, color: col),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(text, style: TempoType.body.c(c.text1)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (!p.isRest && (easier != null || harder != null))
          Section(
            title: 'Not feeling it?',
            child: Row(
              children: [
                if (easier != null) alt('Easier', easier),
                if (easier != null && harder != null) const SizedBox(width: 10),
                if (harder != null) alt('Harder', harder),
              ],
            ),
          ),
      ],
    );
  }

  static String _easy(sc.Sport s) => switch (s) {
    sc.Sport.running => 'easy_run',
    sc.Sport.cycling => 'easy_ride',
    sc.Sport.walking => 'easy_walk',
    sc.Sport.strength => 'strength_full',
    sc.Sport.yoga => 'yoga',
    sc.Sport.hiit => 'hiit',
    sc.Sport.sport => 'sport',
  };

  static List<(String, Color, String)> _whyRows(
    BuildContext context,
    TodayData t,
    bool general,
  ) {
    final c = context.c, s = context.s;
    final out = <(String, Color, String)>[];
    final r = t.recovery;
    if (general) {
      out.add((
        '·',
        c.text2,
        'Night ${t.nights} of 14 — sessions stay general and moderate',
      ));
    } else if (r != null) {
      out.add((
        recoveryGlyph(r),
        s.recoveryFor(r),
        'Recovery ${r.round()}% — ${recoveryWord(r).toLowerCase()}',
      ));
    }
    final l = t.load;
    if (l.status != sc.LoadStatus.learning) {
      out.add((
        loadGlyph(l.status),
        loadColor(context, l.status),
        switch (l.status) {
          sc.LoadStatus.building => 'Load building, with room for one hard day',
          sc.LoadStatus.overreaching => 'Load overreaching — intensity waits',
          sc.LoadStatus.detraining => 'Load below normal — time to build back',
          _ => 'Load steady at your normal',
        },
      ));
    }
    final since = t.daysSinceHard;
    out.add((
      '${since ?? '–'}',
      c.text2,
      since == null
          ? 'No Z4+ work in the last two weeks'
          : since == 0
          ? 'Z4+ work already today'
          : 'No Z4+ work for $since ${since == 1 ? 'day' : 'days'}',
    ));
    final prof = t.profile;
    out.add((
      '◎',
      c.text2,
      'Goal: ${goalLabel(prof.goal).toLowerCase()}${prof.likes.isEmpty ? '' : ' · you prefer ${sportLabel(prof.likes.first).toLowerCase()}'}',
    ));
    return out;
  }
}
