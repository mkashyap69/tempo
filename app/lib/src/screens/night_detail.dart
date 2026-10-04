import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../design/chart.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'sleep.dart';

class NightDetailScreen extends ConsumerWidget {
  const NightDetailScreen({super.key, required this.morning});
  final DateTime morning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(nightProvider(morning)).value;
    if (n == null) return Scaffold(backgroundColor: context.c.bg);
    final c = context.c, s = context.s;
    final eve = morning.subtract(const Duration(days: 1));
    final header = DetailHeader(
      title: 'Night detail',
      subtitle:
          '${dayShort(eve).substring(0, 3)} ${eve.day} → ${dayShort(morning)}',
    );
    if (n.empty) {
      return TempoPage(
        children: [header, const TempoEmpty('No sleep found for this night.')],
      );
    }
    final total = n.minutes.length;
    final rows = [
      ('Awake', n.awake, sc.Stage.wake, s.sleepAwake),
      ('REM', n.stage(sc.Stage.rem), sc.Stage.rem, s.sleepRem),
      ('Light', n.stage(sc.Stage.light), sc.Stage.light, s.sleepLight),
      ('Deep', n.stage(sc.Stage.deep), sc.Stage.deep, s.sleepDeep),
    ];
    final hrs = [for (final m in n.minutes) m.hr];
    int? low;
    DateTime? lowAt;
    for (final m in n.minutes) {
      if (m.hr != null && (low == null || m.hr! < low)) {
        low = m.hr;
        lowAt = m.ts;
      }
    }
    final spo2 = n.spo2;
    return TempoPage(
      children: [
        header,
        Section(
          title: 'Stages · vs your typical night',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardList(
                children: [
                  for (final (name, d, stg, col) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              name,
                              style: TempoType.label.c(c.text1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final share = d.inMinutes / total;
                                final typ = n.typical[stg];
                                return SizedBox(
                                  height: 18,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        top: 4,
                                        height: 10,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: c.trackOff,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 0,
                                        top: 4,
                                        height: 10,
                                        width:
                                            (share / .6).clamp(0, 1) *
                                            box.maxWidth,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: col,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (typ != null)
                                        Positioned(
                                          left:
                                              (typ / .6).clamp(0, 1) *
                                                  box.maxWidth -
                                              1,
                                          top: 0,
                                          width: 2,
                                          height: 18,
                                          child: Container(color: c.text2),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 64,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  hmShort(d.inMinutes / 60),
                                  style: TempoType.label.c(c.text1).tnum,
                                ),
                                Text(
                                  '${(d.inMinutes / total * 100).round()}%',
                                  style: TempoType.caption.c(c.text3).tnum,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                n.typical.isEmpty
                    ? 'Your typical night appears after a few nights.'
                    : 'Tick = your 30-night typical. Stages are estimated from motion and heart rate.',
                style: TempoType.caption.c(c.text3),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final (i, (k, v, u)) in [
              ('Fell asleep', '${n.latency}', ' min'),
              ('Wake-ups', '${n.wakeUps.length}', ''),
              ('Awake', '${n.awake.inMinutes}', ' min'),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: TempoCard(
                  padding: const EdgeInsets.all(14),
                  child: Stat(k, v, unit: u),
                ),
              ),
            ],
          ],
        ),
        CardList(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Wake-ups', style: TempoType.label.c(c.text1)),
            ),
            if (n.wakeUps.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Text(
                  'None longer than 2 minutes.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ),
            for (final w in n.wakeUps)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      clockOf(w.start),
                      style: TempoType.bodyS.c(c.text1).tnum,
                    ),
                    const Spacer(),
                    Text(
                      '${w.minutes} min · ${w.moved ? 'movement' : 'after ${switch (w.afterStage) {
                              sc.Stage.rem => 'REM',
                              sc.Stage.deep => 'deep',
                              _ => 'light',
                            }}'}',
                      style: TempoType.bodyS.c(c.text2).tnum,
                    ),
                  ],
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
                      'Overnight heart rate',
                      style: TempoType.label.c(c.text1),
                    ),
                  ),
                  if (low != null)
                    Text(
                      'lowest $low at ${clockOf(lowAt!)}',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SvgChart(
                height: 140,
                semantics: 'Overnight heart rate',
                draw: (ink, box) {
                  final known = hrs.whereType<int>();
                  if (known.isEmpty) return;
                  final lo = known.reduce((a, b) => a < b ? a : b) - 4.0,
                      hi = known.reduce((a, b) => a > b ? a : b) + 4.0;
                  double y(num b) => 134 - (b - lo) / (hi - lo) * 128;
                  double x(int i) => i / (hrs.length - 1) * 520;
                  if (n.hrBand != null) {
                    ink.rect(
                      Rect.fromLTRB(
                        0,
                        y(n.hrBand!.$2.clamp(lo, hi)),
                        520,
                        y(n.hrBand!.$1.clamp(lo, hi)),
                      ),
                      ink.c.surface3,
                      opacity: .7,
                    );
                  }
                  ink.gappedLine(
                    [
                      for (final (i, h) in hrs.indexed)
                        h == null ? null : Offset(x(i), y(h)),
                    ],
                    ink.c.text1,
                    w: 2.5,
                  );
                  final li = hrs.indexOf(low);
                  if (li >= 0) ink.dot(Offset(x(li), y(low!)), 6, ink.c.text1);
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(clockOf(n.start), style: TempoType.caption.c(c.text3)),
                  if (n.hrBand != null)
                    Text(
                      'band = your normal ${n.hrBand!.$1.round()}–${n.hrBand!.$2.round()}',
                      style: TempoType.caption.c(c.text3).tnum,
                    ),
                  Text(clockShort(n.end), style: TempoType.caption.c(c.text3)),
                ],
              ),
            ],
          ),
        ),
        TempoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Blood oxygen', style: TempoType.label.c(c.text1)),
                  const SizedBox(width: 8),
                  const TempoBadge('Est.', small: true),
                  const Spacer(),
                  if (spo2.isNotEmpty)
                    Text(
                      'avg ${(spo2.map((e) => e.value).reduce((a, b) => a + b) / spo2.length).round()}% · ${spo2.length} readings',
                      style: TempoType.caption.c(c.text2).tnum,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (spo2.isEmpty)
                Text(
                  'No readings last night. The band takes spot readings when it can.',
                  style: TempoType.bodyS.c(c.text2),
                )
              else
                SizedBox(
                  height: 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final o in spo2.take(12))
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${o.value}',
                                style: TempoType.caption.c(c.text3).tnum,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 8,
                                height: ((o.value - 90).clamp(1, 10) * 4.0),
                                decoration: BoxDecoration(
                                  color: c.text2,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Spot readings from the band, not continuous. For wellness only.',
                style: TempoType.caption.c(c.text3),
              ),
            ],
          ),
        ),
        Text(
          'Night of ${dm(st.fromTs(st.toTs(n.start)))}',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}
