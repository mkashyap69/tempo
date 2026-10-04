import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'day_timeline.dart';
import 'nav.dart';

final _calProvider = FutureProvider<Map<String, st.DailyScore>>((ref) async {
  ref.watch(dbTickProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month - 1, 1);
  return {
    for (final s in await ref.watch(dbProvider).scoresBetween(from, dayOf(now)))
      s.date: s,
  };
});

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_calProvider).value;
    final c = context.c, s = context.s;
    final now = DateTime.now();
    final months = [
      DateTime(now.year, now.month - 1),
      DateTime(now.year, now.month),
    ];
    return TempoPage(
      gap: 18,
      children: [
        const DetailHeader(title: 'Calendar'),
        Wrap(
          spacing: 14,
          children: [
            Legend(s.recHigh, '▲ Primed', width: 12, height: 12),
            Legend(s.recMid, '■ Steady', width: 12, height: 12),
            Legend(s.recLow, '▼ Low', width: 12, height: 12),
          ],
        ),
        if (data != null)
          for (final m in months) _month(context, m, data, now),
        Text(
          'Tap a day to open its timeline. Grey days were calibrating or had no data.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }

  Widget _month(
    BuildContext context,
    DateTime m,
    Map<String, st.DailyScore> data,
    DateTime now,
  ) {
    final c = context.c, s = context.s;
    final days = DateUtils.getDaysInMonth(m.year, m.month);
    final lead = DateTime(m.year, m.month, 1).weekday - 1;
    final vals = [
      for (var d = 1; d <= days; d++)
        if (data[st.dateKey(DateTime(m.year, m.month, d))] case final sc?
            when !sc.calibrating && sc.recovery != null)
          sc.recovery!,
    ];
    final current = m.month == now.month && m.year == now.year;
    final sum = vals.isEmpty
        ? 'no scores yet'
        : '${current ? 'so far' : 'avg'} ${(vals.reduce((a, b) => a + b) / vals.length).round()}% · ${vals.where((v) => v >= 67).length} ▲ · ${vals.where((v) => v >= 34 && v < 67).length} ■ · ${vals.where((v) => v < 34).length} ▼';
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        Builder(
          builder: (context) {
            final date = DateTime(m.year, m.month, d);
            final sc = data[st.dateKey(date)];
            final future = date.isAfter(now);
            final r = sc == null || sc.calibrating ? null : sc.recovery;
            final today = DateUtils.isSameDay(date, now);
            final bg = r == null ? null : s.recoveryFor(r);
            return Pressable(
              label: r == null ? '$d, no score' : '$d, recovery ${r.round()}%',
              onTap: future
                  ? null
                  : () => push(context, DayTimelineScreen(day: date)),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: bg ?? (future ? null : c.surface2),
                  borderRadius: BorderRadius.circular(10),
                  border: future ? Border.all(color: c.line) : null,
                  boxShadow: today
                      ? [
                          BoxShadow(color: c.bg, spreadRadius: 2),
                          BoxShadow(color: c.text1, spreadRadius: 4),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$d',
                      style: TempoType.label
                          .c(
                            bg != null
                                ? const Color(0xFF0A0B0D)
                                : (future ? c.text3 : c.text2),
                          )
                          .tnum,
                    ),
                    if (r != null)
                      Text(
                        '${recoveryGlyph(r)} ${r.round()}',
                        style: const TextStyle(
                          fontFamily: TempoType.family,
                          fontSize: 10,
                          height: 1.2,
                          color: Color(0xFF0A0B0D),
                        ).tnum,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                DateFormat('MMMM y').format(m),
                style: TempoType.titleM.c(c.text1),
              ),
            ),
            Text(sum, style: TempoType.caption.c(c.text3).tnum),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final l in 'MTWTFSS'.split(''))
              Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: TempoType.caption.c(c.text3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 46 / 52,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }
}
