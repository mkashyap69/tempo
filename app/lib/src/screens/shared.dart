import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/format.dart';
import '../core/today.dart';
import '../design/tokens.dart';

/// One recovery input against its 30-day baseline.
class Contributor {
  const Contributor({
    required this.key,
    required this.name,
    required this.proxy,
    required this.value,
    required this.base,
    required this.verdict,
    required this.glyph,
    required this.color,
    required this.left,
    required this.width,
    required this.effect,
  });
  final String key, name, value, base, verdict, glyph;
  final bool proxy;
  final Color color;
  final double left, width;

  /// Signed weighted z: + helped, − hurt. 0 when unknown.
  final double effect;
}

List<Contributor> contributors(BuildContext context, TodayData t) {
  final s = context.s, c = context.c;
  final score = t.score;
  final calib = t.calibrating;
  Contributor make(
    String key,
    String name,
    bool proxy,
    double? v,
    sc.Baseline? b,
    double weight,
    bool lowerBetter,
    String Function(double) fmt,
    String Function(double z, double diff) say,
  ) {
    if (v == null) {
      return Contributor(
        key: key,
        name: name,
        proxy: proxy,
        value: '—',
        base: b == null ? 'learning' : fmt(b.mean),
        verdict: 'No data last night',
        glyph: '',
        color: c.text3,
        left: .5,
        width: 0,
        effect: 0,
      );
    }
    if (calib || b == null || b.sd == 0) {
      return Contributor(
        key: key,
        name: name,
        proxy: proxy,
        value: fmt(v),
        base: 'learning',
        verdict: '${t.nights} of 14 nights',
        glyph: '',
        color: c.text3,
        left: .5,
        width: 0,
        effect: 0,
      );
    }
    var z = (v - b.mean) / b.sd;
    if (lowerBetter) z = -z;
    final w = math.min(.42, z.abs() * .14);
    final color = z > .4
        ? s.recHigh
        : z < -.4
        ? s.recLow
        : s.recMid;
    final glyph = z > .4
        ? '▲'
        : z < -.4
        ? '▼'
        : '■';
    return Contributor(
      key: key,
      name: name,
      proxy: proxy,
      value: fmt(v),
      base: fmt(b.mean),
      verdict: say(z, v - b.mean),
      glyph: glyph,
      color: color,
      left: z >= 0 ? .5 : .5 - w,
      width: w,
      effect: z * weight,
    );
  }

  // Band: the stress index stands in for HRV. Health: real HRV when the
  // watch measures it; neither on a Health source without HRV.
  final health = t.source != sc.bandSource;
  final list = [
    if (!health)
      make(
        'stress',
        'Stress index, overnight',
        true,
        score?.hrvProxy,
        t.stressBase,
        .4,
        true,
        (x) => '${x.round()}',
        (z, d) => z > .4
            ? 'Calmer than usual · helped'
            : z < -.4
            ? 'Higher than usual · hurt'
            : 'About usual',
      ),
    if (health && (score?.hrv != null || t.hrvBase != null))
      make(
        'hrv',
        score?.hrvKind == 'rmssd' ? 'HRV (RMSSD), overnight' : 'HRV, overnight',
        false,
        score?.hrv,
        t.hrvBase,
        .4,
        false,
        (x) => '${x.round()} ms',
        (z, d) => z > .4
            ? '${d.abs().round()} ms above · helped'
            : z < -.4
            ? '${d.abs().round()} ms below · hurt'
            : 'Near baseline',
      ),
    make(
      'rhr',
      'Resting heart rate',
      false,
      score?.rhr,
      t.rhrBase,
      .3,
      true,
      (x) => '${x.round()} bpm',
      (z, d) => z > .4
          ? '${d.abs().round()} bpm below · helped'
          : z < -.4
          ? '${d.abs().round()} bpm above · hurt'
          : 'Near baseline',
    ),
    make(
      'sleep',
      'Sleep',
      false,
      score?.sleepPerf,
      t.sleepBase,
      .3,
      false,
      (x) => '${x.round()}%',
      (z, d) {
        final short = t.need != null && t.slept != null && t.slept! < t.need!
            ? hmSpaced(t.need! - t.slept!)
            : null;
        if (z < -.4) {
          return short == null
              ? 'Below your usual · hurt'
              : '$short short · hurt';
        }
        if (z > .4) return 'More than usual · helped';
        return short == null ? 'About usual' : 'Slightly short · held it back';
      },
    ),
  ];
  final si = list.indexWhere((x) => x.key == 'sleep');
  if (score?.sleepPerf != null && !calib && si >= 0) {
    final sl = list[si];
    list[si] = Contributor(
      key: sl.key,
      name: sl.name,
      proxy: false,
      value: '${score!.sleepPerf!.round()}% of need',
      base: sl.base,
      verdict: sl.verdict,
      glyph: sl.glyph,
      color: sl.color,
      left: sl.left,
      width: sl.width,
      effect: sl.effect,
    );
  }
  // Name the biggest mover.
  if (!calib) {
    final top = list.reduce((a, b) => a.effect.abs() >= b.effect.abs() ? a : b);
    if (top.effect.abs() > .2) {
      final i = list.indexOf(top);
      list[i] = Contributor(
        key: top.key,
        name: top.name,
        proxy: top.proxy,
        value: top.value,
        base: top.base,
        verdict: top.verdict.replaceFirst(
          RegExp(r'· (helped|hurt)$'),
          '· ${top.effect > 0 ? 'helped' : 'hurt'} most',
        ),
        glyph: top.glyph,
        color: top.color,
        left: top.left,
        width: top.width,
        effect: top.effect,
      );
    }
  }
  return list;
}

/// Plain-language "why" for a recovery score.
String recoveryWhy(TodayData t, List<Contributor> cs) {
  final health = t.source != sc.bandSource;
  if (t.calibrating) {
    return 'Tempo needs 14 nights to learn your normal resting HR, ${health ? 'HRV' : 'stress'} and sleep. Until then there’s no recovery score — anything else would be a guess.';
  }
  if (t.recovery == null) {
    return health
        ? 'No recovery yet for today. Once your watch has synced last night to Health, open Tempo again.'
        : 'No recovery yet for today. Sync after waking so Tempo can read last night.';
  }
  final parts = <String>[];
  final rhr = t.rhrDelta, st = t.stressDelta;
  final hrv = t.score?.hrv, hb = t.hrvBase;
  if (hrv != null && hb != null && hb.sd > 0) {
    final z = (hrv - hb.mean) / hb.sd;
    parts.add(
      z > .4
          ? 'your overnight HRV was higher than usual'
          : z < -.4
          ? 'your overnight HRV was lower than usual'
          : 'your overnight HRV was about usual',
    );
  }
  if (rhr != null) {
    parts.add(
      rhr.abs() < 1
          ? 'your resting heart rate was right on your baseline'
          : 'your resting heart rate was ${rhr.abs().round()} bpm ${rhr < 0 ? 'below' : 'above'} your baseline',
    );
  }
  if (st != null) {
    parts.add(
      st < -2
          ? 'the band’s overnight stress index was calmer than usual'
          : st > 2
          ? 'overnight stress ran high'
          : 'overnight stress was about usual',
    );
  }
  var s = parts.isEmpty
      ? 'Recovery uses last night against your 30-day baseline'
      : parts.join(' and ');
  s = s[0].toUpperCase() + s.substring(1);
  s += '.';
  if (t.sleepPerf != null && t.slept != null && t.need != null) {
    s += t.sleepPerf! >= 100
        ? ' You slept your full need.'
        : ' You slept ${t.sleepPerf!.round()}% of your need (${hmShort(t.slept!)} against ${hmShort(t.need!)}).';
  }
  return s;
}

/// Today's one-line coaching: (lead, lead colour, rest).
(String, Color, String) coachLine(
  BuildContext context,
  TodayData t, {
  bool noBand = false,
  bool noPermission = false,
  bool health = false,
}) {
  final c = context.c, s = context.s;
  final target = t.target;
  final device = health ? 'watch' : 'band';
  if (noBand || noPermission) {
    return (
      health ? 'Connect Health' : 'Connect your band',
      c.text1,
      ' to see today’s recovery, strain and sleep.',
    );
  }
  if (t.stale) {
    return (
      'Yesterday’s data',
      c.text2,
      health
          ? ' — let your watch sync to Health before you train so today’s plan uses last night’s sleep.'
          : ' — sync before you train so today’s plan uses last night’s sleep.',
    );
  }
  if (t.firstDay) {
    return (
      'Welcome to Tempo.',
      c.text1,
      ' Wear your $device tonight — your first sleep and recovery arrive tomorrow morning.',
    );
  }
  if (t.calibrating) {
    return (
      'Night ${t.nights} of 14',
      c.text1,
      ' — still learning your baseline. Moderate effort today; general target ${target.lo.round()}–${target.hi.round()}.',
    );
  }
  final r = t.recovery;
  if (r == null) {
    return (
      'Last night isn’t in yet',
      c.text1,
      health
          ? ' — once your watch syncs last night to Health, recovery appears here.'
          : ' — sync near your band to see today’s recovery.',
    );
  }
  final lead = 'Recovery ${r.round()}%';
  final col = s.recoveryFor(r);
  if (target.cap) {
    return (
      lead,
      col,
      ' — rest day. Keep strain under ${target.hi.round()} and be in bed by ${clock12(t.bedtimeMinute)}.',
    );
  }
  if (r >= 67) {
    final plan = t.plan;
    final what = plan == null || plan.isRest
        ? 'a hard session'
        : plan.isHard
        ? plan.title.toLowerCase()
        : 'a solid session';
    return (
      lead,
      col,
      ' — you’re primed. A good day for $what; aim for ${target.lo.round()}–${target.hi.round()} strain.',
    );
  }
  if (r < 50) {
    return (lead, col, ' — keep strain under ${target.hi.round()} today.');
  }
  return (
    lead,
    col,
    ' — a steady day. Keep it moderate; aim for ${target.lo.round()}–${target.hi.round()} strain.',
  );
}

/// Strain status against today's target.
(String, String) strainStatus(TodayData t, {double? planAdds}) {
  final s = t.strain, tg = t.target;
  if (tg.cap) {
    return s <= tg.hi
        ? (
            'Under cap',
            '${(tg.hi - s).toStringAsFixed(1)} left before the cap. A walk adds about 2.',
          )
        : ('Over cap', 'Past today’s cap — keep the rest of the day easy.');
  }
  if (s < tg.lo) {
    final adds = planAdds == null
        ? ''
        : ' Today’s ${t.plan?.isHard == true ? 'intervals' : 'session'} add about ${planAdds.round()}.';
    return (
      'Below range',
      '${(tg.lo - s).toStringAsFixed(1)} to reach your ${tg.general ? 'general ' : ''}range.$adds',
    );
  }
  if (s <= tg.hi) {
    return (
      'In range',
      'Inside today’s ${tg.lo.round()}–${tg.hi.round()}. Anything more is optional.',
    );
  }
  return ('Above range', 'Above today’s range — take it easy from here.');
}

double planAdds(TodayData t) {
  final p = t.plan;
  if (p == null || p.isRest) return 0;
  return sc.sessionStrain(
    p,
    hrMax: t.hrMax,
    hrRest: t.score?.rhr ?? 60,
    dayTrimp: t.score?.trimp ?? 0,
  );
}

Color loadColor(BuildContext context, sc.LoadStatus s) => switch (s) {
  sc.LoadStatus.learning => context.c.text2,
  sc.LoadStatus.detraining => context.s.loadDetraining,
  sc.LoadStatus.maintaining => context.s.loadMaintaining,
  sc.LoadStatus.building => context.s.loadBuilding,
  sc.LoadStatus.overreaching => context.s.loadOverreaching,
};

/// "7-day load 12% above your 28-day"
String loadSub(sc.CardioLoad l) {
  if (l.status == sc.LoadStatus.learning) return 'Ready after 14 days of wear';
  final p = l.percentVsNormal;
  if (p.abs() < 3) return '7-day load matches your 28-day';
  return '7-day load ${p.abs()}% ${p > 0 ? 'above' : 'below'} your 28-day';
}
