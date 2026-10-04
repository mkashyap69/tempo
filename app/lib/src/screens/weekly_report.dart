import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:share_plus/share_plus.dart';
import 'package:store/store.dart' as st;

import '../core/coach_service.dart';
import '../core/format.dart';
import '../core/profile.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

class WeekReport {
  WeekReport({
    required this.monday,
    required this.rec,
    required this.strain,
    required this.sleep,
    required this.sessions,
    required this.minutes,
    required this.load,
    required this.inPlan,
    required this.changes,
  });
  final DateTime monday;
  final List<double?> rec, strain, sleep;
  final int sessions, minutes, inPlan;
  final sc.CardioLoad load;
  final List<st.PlanDay> changes;

  double? avg(List<double?> x) {
    final v = x.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  int get week =>
      ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
                  DateTime(monday.year, 1, 1).weekday +
                  6) /
              7)
          .floor();
  (int, double)? get best {
    (int, double)? b;
    for (final (i, v) in rec.indexed) {
      if (v != null && (b == null || v > b.$2)) b = (i, v);
    }
    return b;
  }

  /// "Your week in three lines".
  String summary() {
    final parts = <String>[];
    var worst = -1;
    for (final (i, v) in rec.indexed) {
      if (v != null && (worst < 0 || v < rec[worst]!)) worst = i;
    }
    if (worst >= 0 && rec[worst]! < 50) {
      final ch = changes
          .where((c) => DateTime.parse(c.date).weekday - 1 == worst)
          .firstOrNull;
      parts.add(
        '${_day(worst)}’s low morning pulled recovery to ${rec[worst]!.round()}%${ch == null ? '' : '; the plan adapted that day'}.',
      );
    } else if (avg(rec) != null) {
      parts.add(
        'Recovery averaged ${avg(rec)!.round()}% with no red mornings.',
      );
    }
    final days = strain.whereType<double>().length;
    if (days > 0) parts.add('Strain landed in plan $inPlan of $days days.');
    if (load.status != sc.LoadStatus.learning) {
      parts.add(
        'Load is ${loadWord(load.status).toLowerCase()}${switch (load.status) {
          sc.LoadStatus.building => ' — hold two hard days next week',
          sc.LoadStatus.overreaching => ' — start next week with two easy days',
          sc.LoadStatus.detraining => ' — add a session next week',
          _ => '',
        }}.',
      );
    }
    return parts.isEmpty
        ? 'Not enough data this week yet. Wear the band through the night and every session.'
        : parts.join(' ');
  }

  static String _day(int i) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][i];
}

final weekReportProvider = FutureProvider<WeekReport>((ref) async {
  ref.watch(dbTickProvider);
  final db = ref.watch(dbProvider);
  final mon = mondayOf(DateTime.now());
  final sun = mon.add(const Duration(days: 6));
  final scores = {for (final s in await db.scoresBetween(mon, sun)) s.date: s};
  final plan = await CoachService(db).ensureWeek(mon);
  final ws = await db.workoutsBetween(mon, sun.add(const Duration(days: 1)));
  var inPlan = 0;
  final rec = <double?>[], strain = <double?>[], sleep = <double?>[];
  for (var i = 0; i < 7; i++) {
    final s = scores[st.dateKey(mon.add(Duration(days: i)))];
    rec.add(s == null || s.calibrating ? null : s.recovery);
    strain.add(s?.strain);
    sleep.add(s?.sleptHours);
    if (s != null && i < plan.length) {
      final p = sc.Session.fromJson(
        jsonDecode(plan[i].session) as Map<String, dynamic>,
      );
      if (s.strain >= p.strainLo && s.strain <= p.strainHi + .5) inPlan++;
    }
  }
  return WeekReport(
    monday: mon,
    rec: rec,
    strain: strain,
    sleep: sleep,
    sessions: ws.length,
    minutes: ws.fold(0, (a, w) => a + ((w.end - w.start) / 60).round()),
    load: await loadFor(db, dayOf(DateTime.now())),
    inPlan: inPlan,
    changes: plan.where((p) => p.reason != null).toList(),
  );
});

class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key});
  @override
  ConsumerState<WeeklyReportScreen> createState() => _WeeklyReportState();
}

class _WeeklyReportState extends ConsumerState<WeeklyReportScreen> {
  final _key = GlobalKey();

  Future<File> _render() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getApplicationDocumentsDirectory();
    final r = ref.read(weekReportProvider).value!;
    final f = File('${dir.path}/tempo-week-${r.week}.png');
    await f.writeAsBytes(bytes!.buffer.asUint8List());
    return f;
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(weekReportProvider).value;
    final c = context.c;
    final cardTheme =
        ref.watch(settingProvider(Keys.reportCardTheme)).value ??
        (c.dark ? 'dark' : 'light');
    final exact =
        (ref.watch(settingProvider(Keys.reportExact)).value ?? '1') == '1';
    final db = ref.read(dbProvider);
    if (r == null) return Scaffold(backgroundColor: c.bg);
    return TempoPage(
      children: [
        const DetailHeader(
          title: 'Weekly report',
          leadingIcon: TempoIcons.close,
        ),
        Center(
          child: Container(
            width: 350,
            height: 437,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TempoRadii.lg),
              border: Border.all(color: c.lineStrong),
            ),
            child: FittedBox(
              child: RepaintBoundary(
                key: _key,
                child: Theme(
                  data: tempoTheme(
                    cardTheme == 'dark' ? Brightness.dark : Brightness.light,
                  ),
                  child: ShareCard(report: r, exact: exact),
                ),
              ),
            ),
          ),
        ),
        CardList(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Card style', style: TempoType.body.c(c.text1)),
                  ),
                  TempoSegmented<String>(
                    width: 134,
                    height: 36,
                    inverse: true,
                    values: const ['dark', 'light'],
                    labels: const ['Dark', 'Light'],
                    selected: cardTheme,
                    onChanged: (v) => db.putSetting(Keys.reportCardTheme, v),
                  ),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Show exact numbers',
                      style: TempoType.body.c(c.text1),
                    ),
                  ),
                  TempoSwitch(
                    label: 'Show exact numbers',
                    value: exact,
                    onChanged: (v) =>
                        db.putSetting(Keys.reportExact, v ? '1' : '0'),
                  ),
                ],
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Your week in three lines'),
            const SizedBox(height: 8),
            Text(r.summary(), style: TempoType.body.c(c.text2)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TempoButton(
                'Share image',
                icon: TempoIcons.share,
                expand: true,
                onTap: () async {
                  final f = await _render();
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(f.path, mimeType: 'image/png')],
                      text: 'My week on Tempo',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            TempoButton(
              'Save',
              kind: ButtonKind.ghost,
              onTap: () async {
                final f = await _render();
                if (context.mounted) {
                  showTempoToast(context, 'Saved ${f.uri.pathSegments.last}');
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 1080 × 1350 share card. Without [exact], numbers become states.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.report, this.exact = true});
  final WeekReport report;
  final bool exact;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    final r = report;
    final rec = r.avg(r.rec), strain = r.avg(r.strain), sleep = r.avg(r.sleep);
    TextStyle big(Color col) => TextStyle(
      fontFamily: TempoType.family,
      fontSize: 88,
      height: 1,
      fontWeight: FontWeight.w300,
      letterSpacing: -3.5,
      color: col,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = TextStyle(
      fontFamily: TempoType.family,
      fontSize: 28,
      color: c.text3,
    );
    final best = r.best;
    return Container(
      width: 1080,
      height: 1350,
      padding: const EdgeInsets.all(96),
      color: c.bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TempoLockup(size: 56, color: c.text1),
              const Spacer(),
              Text(
                'Week ${r.week} · ${dm(r.monday)} – ${dm(r.monday.add(const Duration(days: 6)))}',
                style: TextStyle(
                  fontFamily: TempoType.family,
                  fontSize: 30,
                  color: c.text2,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RECOVERY',
                style: TextStyle(
                  fontFamily: TempoType.family,
                  fontSize: 34,
                  letterSpacing: 2.7,
                  fontWeight: FontWeight.w600,
                  color: c.text2,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: rec == null
                              ? '—'
                              : exact
                              ? '${rec.round()}'
                              : recoveryGlyph(rec),
                        ),
                        if (rec != null && exact)
                          TextSpan(
                            text: '%',
                            style: TextStyle(fontSize: 96, color: c.text3),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: TempoType.family,
                      fontSize: 260,
                      height: 210 / 260,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -13,
                      color: rec == null || exact
                          ? c.text1
                          : s.recoveryFor(rec),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    child: SizedBox(
                      height: 210,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: r.rec[i] == null
                                        ? 8
                                        : r.rec[i]! * 1.7,
                                    decoration: BoxDecoration(
                                      color: r.rec[i] == null
                                          ? c.trackOff
                                          : s.recoveryFor(r.rec[i]!),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'MTWTFSS'[i],
                                    style: TextStyle(
                                      fontFamily: TempoType.family,
                                      fontSize: 26,
                                      color: c.text2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: 56),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line, width: 2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avg strain', style: label),
                          const SizedBox(height: 8),
                          Text(
                            strain == null
                                ? '—'
                                : exact
                                ? strain.toStringAsFixed(1)
                                : (strain < 10
                                      ? 'Light'
                                      : strain < 14
                                      ? 'Moderate'
                                      : 'High'),
                            style: big(s.strain[1]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avg sleep', style: label),
                          const SizedBox(height: 8),
                          Text(
                            sleep == null
                                ? '—'
                                : exact
                                ? hmShort(sleep)
                                : (sleep >= 7 ? 'Enough' : 'Short'),
                            style: big(s.sleepChannel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 56),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Training', style: label),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              exact
                                  ? '${r.sessions} · ${r.minutes ~/ 60}h ${(r.minutes % 60).toString().padLeft(2, '0')}m'
                                  : '${r.sessions} sessions',
                              style: big(c.text1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cardio load', style: label),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${loadGlyph(r.load.status)} ${loadWord(r.load.status)}',
                              style: big(_loadColor(s, r.load.status, c)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                best == null
                    ? 'Best morning · —'
                    : 'Best morning · ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][best.$1]}${exact ? ' ${best.$2.round()}%' : ''}',
                style: label,
              ),
              const Spacer(),
              Text('Mi Band 6 · tracked on-device', style: label),
            ],
          ),
        ],
      ),
    );
  }

  static Color _loadColor(TempoScales s, sc.LoadStatus l, TempoColors c) =>
      switch (l) {
        sc.LoadStatus.building => s.loadBuilding,
        sc.LoadStatus.overreaching => s.loadOverreaching,
        sc.LoadStatus.detraining => s.loadDetraining,
        sc.LoadStatus.maintaining => s.loadMaintaining,
        sc.LoadStatus.learning => c.text2,
      };
}
