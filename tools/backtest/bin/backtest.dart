// Runs the scoring engine over an Apple Health export and prints CSV.
//
//   dart run backtest path/to/export.xml [--source "Mi Fit|Zepp"] [--fill 10]
import 'dart:io';

import 'package:args/args.dart';
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
  var day = args['from'] != null
      ? DateTime.parse(args['from'] as String)
      : DateTime(first.year, first.month, first.day);
  final end = args['to'] != null
      ? DateTime.parse(args['to'] as String)
      : DateTime(last.year, last.month, last.day);

  stdout.writeln(
    'date,strain,trimp,hr_max,slept_h,need_h,sleep_perf,rhr,recovery,calibrating,algo_version',
  );
  final history = <DailyScore>[];
  String f(double? v, [int d = 1]) => v == null ? '' : v.toStringAsFixed(d);
  while (!day.isAfter(end)) {
    final minutes = grid.range(
      day.subtract(const Duration(hours: 12)),
      day.add(const Duration(hours: 36)),
      fillMinutes: fill,
    );
    final s = scoreDay(date: day, minutes: minutes, history: history);
    history.insert(0, s);
    if (history.length > 60) history.removeLast();
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
}
