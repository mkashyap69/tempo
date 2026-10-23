/// Validation numbers for a backtest run (docs/research/Algorithm review.md
/// §11): how scores spread, how noisy they are day to day, how a new algo
/// moves them against an earlier run, and how they agree with a reference
/// (another app's scores, copied by hand).
library;

import 'package:scoring/scoring.dart';

export 'package:scoring/scoring.dart'
    show
        Agreement,
        Noise,
        Series,
        Shift,
        Spread,
        agreement,
        colourChanges,
        colours,
        noise,
        shift,
        spread;

/// Reads a CSV with a `date` column into one [Series] per other column.
Map<String, Series> readCsv(List<String> lines) {
  if (lines.isEmpty) return {};
  final head = lines.first.split(',').map((h) => h.trim()).toList();
  final di = head.indexOf('date');
  if (di < 0) throw const FormatException('CSV needs a date column');
  final out = {
    for (final h in head)
      if (h != 'date') h: <String, double?>{},
  };
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = line.split(',');
    if (cells.length <= di) continue;
    final date = cells[di].trim();
    for (var i = 0; i < head.length && i < cells.length; i++) {
      if (i == di) continue;
      out[head[i]]![date] = double.tryParse(cells[i].trim());
    }
  }
  return out;
}

/// The report as text.
String report({
  required List<String> dates,
  required Map<String, Series> now,
  Map<String, Series>? before,
  Series? reference,
  String referenceColumn = 'sleep_score',
}) {
  final b = StringBuffer();
  String f(double v) => v.toStringAsFixed(1);
  b.writeln('Score         n     p10    p50    p90    TE   MDC95');
  for (final k in ['sleep_score', 'recovery', 'strain', 'sleep_perf']) {
    final s = now[k];
    if (s == null) continue;
    final sp = spread(s.values);
    final nz = noise(dates, s);
    if (sp == null) continue;
    b.writeln(
      '${k.padRight(12)} ${'${sp.n}'.padLeft(4)}  ${f(sp.p10).padLeft(6)} '
      '${f(sp.p50).padLeft(6)} ${f(sp.p90).padLeft(6)}  '
      '${nz == null ? '   —' : f(nz.typicalError).padLeft(4)}  '
      '${nz == null ? '   —' : f(nz.mdc95).padLeft(5)}',
    );
  }
  final rec = now['recovery'];
  if (rec != null) {
    final c = colours(rec.values);
    b.writeln(
      'Recovery colours: green ${(c[RecoveryColor.green]! * 100).round()} %, '
      'yellow ${(c[RecoveryColor.yellow]! * 100).round()} %, '
      'red ${(c[RecoveryColor.red]! * 100).round()} %',
    );
  }
  if (before != null) {
    b.writeln('\nAgainst the earlier run:');
    for (final k in ['sleep_score', 'recovery', 'strain', 'need_h']) {
      final x = before[k], y = now[k];
      if (x == null || y == null) continue;
      final sh = shift(x, y);
      if (sh == null) continue;
      b.writeln(
        '  ${k.padRight(12)} ${sh.n} days, mean change ${f(sh.meanDelta)}, '
        'mean size ${f(sh.meanAbsDelta)}',
      );
    }
    if (before['recovery'] != null && rec != null) {
      b.writeln(
        '  recovery colour changed on '
        '${colourChanges(before['recovery']!, rec)} days',
      );
    }
  }
  if (reference != null && now[referenceColumn] != null) {
    final a = agreement(reference, now[referenceColumn]!);
    b.writeln('\nAgainst the reference ($referenceColumn):');
    b.writeln(
      a == null
          ? '  fewer than 3 shared days'
          : '  ${a.n} days, bias ${f(a.bias)}, 95 % limits '
                '${f(a.loaLow)} to ${f(a.loaHigh)}',
    );
  }
  return b.toString();
}
