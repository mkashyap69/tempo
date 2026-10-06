// Runs the scoring engine over an Apple Health export and prints CSV.
//
//   dart run backtest path/to/export.xml [--source "Mi Fit|Zepp"] [--fill 10]
//
// With --calibrate it prints a strain calibration report instead: the k
// that puts your hardest days (99th percentile of daily TRIMP) at 18.5.
import 'dart:io';

import 'package:args/args.dart';
import 'package:backtest/calibrate.dart';
import 'package:backtest/health_export.dart';
import 'package:scoring/scoring.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'source',
      defaultsTo: r'Mi Fit|Zepp|Mi Fitness',
      help: 'sourceName regex',
    )
    ..addOption(
      'fill',
      defaultsTo: '10',
      help: 'forward-fill HR gaps up to N minutes',
    )
    ..addOption('from', help: 'YYYY-MM-DD')
    ..addOption('to', help: 'YYYY-MM-DD')
    ..addOption('hr-max', help: 'your max HR (default 190)')
    ..addFlag(
      'calibrate',
      negatable: false,
      help: 'print a strain k calibration report instead of CSV',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);
  if (args['help'] as bool || args.rest.length != 1) {
    stderr.writeln('usage: backtest <export.xml> [options]\n${parser.usage}');
    exit(64);
  }
  final grid = await readExport(
    fileLines(args.rest.single),
    RegExp(args['source'] as String),
  );
  final first = grid.first, last = grid.last;
  if (first == null || last == null) {
    stderr.writeln('No matching heart-rate records.');
    exit(1);
  }
  final fill = int.parse(args['fill'] as String);
  final calibrating = args['calibrate'] as bool;
  final params = args['hr-max'] == null
      ? const ScoringParams()
      : ScoringParams(defaultHrMax: int.parse(args['hr-max'] as String));
  final trimpByDay = <DateTime, double>{};
  var day = args['from'] != null
      ? DateTime.parse(args['from'] as String)
      : DateTime(first.year, first.month, first.day);
  final end = args['to'] != null
      ? DateTime.parse(args['to'] as String)
      : DateTime(last.year, last.month, last.day);

  if (!calibrating) {
    stdout.writeln(
      'date,strain,trimp,hr_max,slept_h,need_h,sleep_perf,rhr,recovery,calibrating,algo_version',
    );
  }
  final history = <DailyScore>[];
  String f(double? v, [int d = 1]) => v == null ? '' : v.toStringAsFixed(d);
  while (!day.isAfter(end)) {
    final minutes = grid.range(
      day.subtract(const Duration(hours: 12)),
      day.add(const Duration(hours: 36)),
      fillMinutes: fill,
    );
    final s = scoreDay(
      date: day,
      minutes: minutes,
      history: history,
      p: params,
    );
    history.insert(0, s);
    if (history.length > 60) history.removeLast();
    if (calibrating) {
      final dayEnd = day.add(const Duration(days: 1));
      final worn = minutes
          .where(
            (m) => m.hr != null && !m.ts.isBefore(day) && m.ts.isBefore(dayEnd),
          )
          .length;
      if (worn >= calibrationMinHrMinutes) trimpByDay[day] = s.trimp;
      day = DateTime(day.year, day.month, day.day + 1);
      continue;
    }
    stdout.writeln(
      [
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        f(s.strain),
        f(s.trimp),
        s.hrMax,
        f(s.sleptHours, 2),
        f(s.needHours, 2),
        f(s.sleepPerf, 0),
        f(s.rhr),
        f(s.recovery, 0),
        s.calibrating,
        s.algoVersion,
      ].join(','),
    );
    day = DateTime(day.year, day.month, day.day + 1);
  }
  if (calibrating) _report(calibrate(trimpByDay), params);
}

void _report(Calibration? c, ScoringParams p) {
  if (c == null) {
    stderr.writeln(
      'Not enough data: needs 30 days with $calibrationMinHrMinutes+ '
      'minutes of HR each.',
    );
    exit(1);
  }
  String d(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  String f(double v) => v.toStringAsFixed(1);
  final now = p.strain.k;
  double at(double t, double k) => strainFromTrimp(t, StrainParams(k: k));
  stdout
    ..writeln('Strain calibration over ${c.days} days with enough HR')
    ..writeln('  current k ${f(now)}  ->  suggested k ${f(c.k)}')
    ..writeln('')
    ..writeln('              TRIMP   strain now   strain at suggested k')
    ..writeln(
      '  median day  ${f(c.p50).padLeft(6)}   ${f(at(c.p50, now)).padLeft(10)}   ${f(c.strainAt(c.p50)).padLeft(10)}',
    )
    ..writeln(
      '  90th pct    ${f(c.p90).padLeft(6)}   ${f(at(c.p90, now)).padLeft(10)}   ${f(c.strainAt(c.p90)).padLeft(10)}',
    )
    ..writeln('')
    ..writeln('Hardest days (check these were your real hardest sessions):');
  for (final (day, t) in c.top) {
    stdout.writeln(
      '  ${d(day)}  TRIMP ${f(t).padLeft(6)}  now ${f(at(t, now)).padLeft(4)}  suggested ${f(c.strainAt(t)).padLeft(4)}',
    );
  }
}
