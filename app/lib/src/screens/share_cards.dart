import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/share_card.dart';
import '../core/today.dart';
import '../design/components.dart';
import '../design/icons.dart';

/// Share cards for the day's three numbers (Recovery, Strain, Sleep).
abstract final class DayCards {
  static const _high = Color(0xFF3CCBC0),
      _mid = Color(0xFFF0C24B),
      _low = Color(0xFFEE4F6C),
      _strain = Color(0xFFFFB066),
      _sleep = Color(0xFF9AA4FF);

  static TempoShareCard recovery(TodayData t) {
    final r = t.recovery;
    final s = t.score;
    return TempoShareCard(
      kicker: 'Recovery',
      title: r == null ? 'Still learning your normal' : recoveryWord(r),
      date: t.day,
      hero: r == null ? '${t.nights}' : '${r.round()}',
      heroUnit: r == null ? 'of 14 nights' : '%',
      accent: r == null
          ? const Color(0xFFA9ADB4)
          : r >= 67
          ? _high
          : r >= 34
          ? _mid
          : _low,
      stats: [
        if (s?.rhr != null)
          ShareStat('Resting HR', '${s!.rhr!.round()}', unit: ' bpm'),
        if (s?.hrv != null) ShareStat('HRV', '${s!.hrv!.round()}', unit: ' ms'),
        if (t.sleepScore != null)
          ShareStat('Sleep', '${t.sleepScore!.round()}', unit: '%'),
        if (t.slept != null) ShareStat('Slept', hmShort(t.slept!)),
      ],
    );
  }

  static TempoShareCard strain(TodayData t) {
    final tg = t.target;
    return TempoShareCard(
      kicker: 'Strain',
      title: tg.cap
          ? 'Rest day · cap ${tg.hi.round()}'
          : tg.contains(t.strain)
          ? 'In today’s target'
          : 'Target ${tg.lo.round()}–${tg.hi.round()}',
      date: t.day,
      hero: t.strain.toStringAsFixed(1),
      heroUnit: '/ 21',
      accent: _strain,
      stats: [
        ShareStat(
          tg.cap ? 'Cap' : 'Target',
          tg.cap ? '${tg.hi.round()}' : '${tg.lo.round()}–${tg.hi.round()}',
        ),
        ShareStat('Workouts', '${t.workouts.length}'),
        if (t.score?.hrMax != null)
          ShareStat('Max HR set', '${t.score!.hrMax}'),
      ],
    );
  }

  static TempoShareCard sleep(TodayData t) {
    final sc = t.sleepScore;
    return TempoShareCard(
      kicker: 'Sleep',
      title: t.slept == null ? 'No night recorded' : 'Last night',
      date: t.day,
      hero: sc == null ? '—' : '${sc.round()}',
      heroUnit: sc == null ? null : '%',
      heroLabel: t.slept == null ? null : '${hmShort(t.slept!)} asleep',
      accent: _sleep,
      stats: [
        if (t.need != null) ShareStat('Needed', hmShort(t.need!)),
        ShareStat('Tonight', hmShort(t.needTonight)),
        ShareStat('In bed by', fmtHm(t.bedtimeMinute)),
      ],
    );
  }
}

/// The header's share button.
class ShareButton extends StatelessWidget {
  const ShareButton({super.key, required this.card, required this.name});
  final TempoShareCard Function() card;
  final String name;

  @override
  Widget build(BuildContext context) => TempoIconButton(
    TempoIcons.share,
    label: 'Share as a card',
    stroke: 1.75,
    onTap: () => shareCard(context, card(), name: name, text: 'From Tempo'),
  );
}
