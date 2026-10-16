/// Journal impact v2: what each behaviour does to the next night and
/// morning, adjusted for the others and for the day's strain, with a likely
/// range in real units. Pure Dart, deterministic (seeded bootstrap).
library;

import 'dart:math';

/// What a behaviour on day D is compared against: the night after it and
/// the morning of D + 1.
enum Outcome { recovery, sleepPerf, hrv, rhr, sleptHours }

/// Smallest change worth reporting, in the outcome's units.
double minEffect(Outcome o) => switch (o) {
  Outcome.recovery => 2, // points
  Outcome.sleepPerf => 2, // points
  Outcome.hrv => .03, // ln ms, ≈ 3 %
  Outcome.rhr => .5, // bpm
  Outcome.sleptHours => .1, // 6 min
};

/// Higher is better for the outcome.
bool higherIsBetter(Outcome o) => o != Outcome.rhr;

/// One day: behaviours (1/0 for yes/no, a number for amounts), the
/// covariates and the outcomes that followed. Missing behaviours are
/// unknown, not "no".
final class ImpactDay {
  const ImpactDay({
    required this.date,
    required this.x,
    required this.y,
    this.strain,
    this.weekend = false,
  });
  final DateTime date;
  final Map<String, double> x;
  final Map<Outcome, double> y;

  /// Day D's strain (hard days lower the next morning whatever else).
  final double? strain;

  /// D + 1 is a Saturday or Sunday (sleep-ins).
  final bool weekend;
}

/// How a behaviour is coded: yes/no, or an amount reported per [dose]
/// (e.g. per drink, per 100 mg).
final class Behaviour {
  const Behaviour(this.key, {this.binary = true, this.dose = 1});
  final String key;
  final bool binary;
  final double dose;
}

enum ImpactConfidence { notEnough, none, low, moderate, high }

final class Impact {
  const Impact({
    required this.key,
    required this.outcome,
    required this.effect,
    required this.low,
    required this.high,
    required this.nYes,
    required this.nNo,
    required this.confidence,
  });
  final String key;
  final Outcome outcome;

  /// Change in the outcome per yes (or per dose), adjusted.
  final double effect;

  /// 80 % bootstrap range.
  final double low, high;

  /// Days with the behaviour (non-zero) and without it (zero).
  final int nYes, nNo;
  final ImpactConfidence confidence;

  /// Good or bad for you, by the outcome's direction.
  bool get helps => higherIsBetter(outcome) ? effect > 0 : effect < 0;

  bool get shown =>
      confidence == ImpactConfidence.moderate ||
      confidence == ImpactConfidence.high;
}

/// Days of each kind a behaviour needs before it is judged.
const impactMinEach = 5;

/// Ridge penalty on standardised behaviour columns: like this many days
/// of "no effect" added to every behaviour, so a handful of days can't
/// produce a big number.
const impactRidge = 4.0;

/// Bootstrap resamples for the range.
const impactBoot = 200;

/// Effects of every behaviour with enough data on [outcome].
List<Impact> impacts(
  List<ImpactDay> days,
  List<Behaviour> behaviours,
  Outcome outcome, {
  int seed = 1,
}) {
  final rows = [
    for (final d in days)
      if (d.y[outcome] != null) d,
  ]..sort((a, b) => a.date.compareTo(b.date));
  final out = <Impact>[];
  final usable = <Behaviour>[];
  final counts = <String, (int, int)>{};
  for (final b in behaviours) {
    var yes = 0, no = 0;
    for (final r in rows) {
      final v = r.x[b.key];
      if (v == null) continue;
      v != 0 ? yes++ : no++;
    }
    counts[b.key] = (yes, no);
    if (yes >= impactMinEach && no >= impactMinEach) usable.add(b);
  }
  if (usable.isEmpty) {
    return [
      for (final b in behaviours)
        Impact(
          key: b.key,
          outcome: outcome,
          effect: 0,
          low: 0,
          high: 0,
          nYes: counts[b.key]!.$1,
          nNo: counts[b.key]!.$2,
          confidence: ImpactConfidence.notEnough,
        ),
    ];
  }
  final full = _fit(rows, usable, outcome);
  final rng = Random(seed);
  final boots = <List<double>>[];
  for (var i = 0; i < impactBoot; i++) {
    final sample = [
      for (var k = 0; k < rows.length; k++) rows[rng.nextInt(rows.length)],
    ];
    final f = _fit(sample, usable, outcome);
    if (f != null) boots.add(f);
  }
  final half = rows.length ~/ 2;
  final early = _fit(rows.sublist(0, half), usable, outcome);
  final late = _fit(rows.sublist(half), usable, outcome);
  for (final b in behaviours) {
    final j = usable.indexOf(b);
    final (yes, no) = counts[b.key]!;
    if (j < 0 || full == null) {
      out.add(
        Impact(
          key: b.key,
          outcome: outcome,
          effect: 0,
          low: 0,
          high: 0,
          nYes: yes,
          nNo: no,
          confidence: ImpactConfidence.notEnough,
        ),
      );
      continue;
    }
    final scale = b.binary ? 1.0 : b.dose;
    final e = full[j] * scale;
    final bs = [for (final f in boots) f[j] * scale]..sort();
    double q(double p) => bs.isEmpty
        ? e
        : bs[(p * (bs.length - 1)).round().clamp(0, bs.length - 1)];
    final lo = q(.1), hi = q(.9);
    final lo95 = q(.025), hi95 = q(.975);
    final excludes = lo > 0 || hi < 0;
    final big = e.abs() >= minEffect(outcome) * (b.binary ? 1 : .5);
    final halvesAgree =
        early != null &&
        late != null &&
        early[j].sign == e.sign &&
        late[j].sign == e.sign;
    final c = !excludes || !big
        ? ImpactConfidence.none
        : !halvesAgree
        ? ImpactConfidence.low
        : (lo95 > 0 || hi95 < 0) && yes + no >= 30
        ? ImpactConfidence.high
        : ImpactConfidence.moderate;
    out.add(
      Impact(
        key: b.key,
        outcome: outcome,
        effect: e,
        low: lo,
        high: hi,
        nYes: yes,
        nNo: no,
        confidence: c,
      ),
    );
  }
  return out;
}

/// Ridge fit on standardised columns; returns each behaviour's slope in
/// raw units (per 1 of its column), or null when the data can't support a
/// fit. Covariates (strain, weekend) are in the model but not returned.
/// Unknown behaviours on a day are filled with that column's mean, so they
/// add nothing either way.
List<double>? _fit(List<ImpactDay> rows, List<Behaviour> bs, Outcome o) {
  final n = rows.length;
  if (n < 6) return null;
  final cols = <List<double>>[];
  for (final b in bs) {
    final known = [
      for (final r in rows)
        if (r.x[b.key] != null) r.x[b.key]!,
    ];
    if (known.isEmpty) return null;
    final m = known.reduce((a, c) => a + c) / known.length;
    cols.add([for (final r in rows) r.x[b.key] ?? m]);
  }
  final strains = [
    for (final r in rows)
      if (r.strain != null) r.strain!,
  ];
  final sMean = strains.isEmpty
      ? 0.0
      : strains.reduce((a, c) => a + c) / strains.length;
  cols.add([for (final r in rows) r.strain ?? sMean]);
  cols.add([for (final r in rows) r.weekend ? 1.0 : 0.0]);
  final p = cols.length;
  final y = [for (final r in rows) r.y[o]!];
  final yMean = y.reduce((a, c) => a + c) / n;
  final means = <double>[], sds = <double>[];
  final z = <List<double>>[];
  for (final c in cols) {
    final m = c.reduce((a, v) => a + v) / n;
    final v = c.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / n;
    final sd = sqrt(v);
    means.add(m);
    sds.add(sd);
    z.add([for (final x in c) sd < 1e-9 ? 0.0 : (x - m) / sd]);
  }
  // (ZᵀZ + λI) β = Zᵀ(y − ȳ); covariates get a token penalty.
  final a = List.generate(p, (_) => List.filled(p, 0.0));
  final rhs = List.filled(p, 0.0);
  for (var i = 0; i < p; i++) {
    for (var j = i; j < p; j++) {
      var s = 0.0;
      for (var k = 0; k < n; k++) {
        s += z[i][k] * z[j][k];
      }
      a[i][j] = s;
      a[j][i] = s;
    }
    a[i][i] += i < bs.length ? impactRidge : .1;
    var r = 0.0;
    for (var k = 0; k < n; k++) {
      r += z[i][k] * (y[k] - yMean);
    }
    rhs[i] = r;
  }
  final beta = _solve(a, rhs);
  if (beta == null) return null;
  return [
    for (var i = 0; i < bs.length; i++) sds[i] < 1e-9 ? 0.0 : beta[i] / sds[i],
  ];
}

/// Gaussian elimination with partial pivoting; null if singular.
List<double>? _solve(List<List<double>> a0, List<double> b0) {
  final n = b0.length;
  final a = [
    for (final r in a0) [...r],
  ];
  final b = [...b0];
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    if (a[piv][c].abs() < 1e-12) return null;
    if (piv != c) {
      final t = a[c];
      a[c] = a[piv];
      a[piv] = t;
      final tb = b[c];
      b[c] = b[piv];
      b[piv] = tb;
    }
    for (var r = c + 1; r < n; r++) {
      final f = a[r][c] / a[c][c];
      if (f == 0) continue;
      for (var k = c; k < n; k++) {
        a[r][k] -= f * a[c][k];
      }
      b[r] -= f * b[c];
    }
  }
  final x = List.filled(n, 0.0);
  for (var r = n - 1; r >= 0; r--) {
    var s = b[r];
    for (var k = r + 1; k < n; k++) {
      s -= a[r][k] * x[k];
    }
    x[r] = s / a[r][r];
  }
  return x;
}

// ---- N-of-1 experiments -----------------------------------------------------

/// "Try 14 days without late caffeine": the change, kept for [days] days
/// from [start], compared with the [days] before it.
final class Experiment {
  const Experiment({
    required this.key,
    required this.doIt,
    required this.start,
    this.days = 14,
  });

  /// Behaviour key from the journal catalogue.
  final String key;

  /// true = do it every day; false = avoid it every day.
  final bool doIt;
  final DateTime start;
  final int days;

  DateTime get end => start.add(Duration(days: days));

  bool runningOn(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// 1-based day of the experiment on [d] (clamped).
  int dayOn(DateTime d) =>
      (DateTime(d.year, d.month, d.day).difference(start).inDays + 1).clamp(
        1,
        days,
      );
}

final class ExperimentResult {
  const ExperimentResult({
    required this.outcome,
    required this.effect,
    required this.low,
    required this.high,
    required this.daysBefore,
    required this.daysDuring,
    required this.adherence,
    required this.confidence,
  });
  final Outcome outcome;

  /// Change during the experiment vs before, adjusted for strain and
  /// weekends.
  final double effect, low, high;
  final int daysBefore, daysDuring;

  /// Share of logged experiment days that kept to the change.
  final double adherence;
  final ImpactConfidence confidence;
}

/// Days needed on each side before a result is shown.
const experimentMinDays = 7;

ExperimentResult experimentResult(
  Experiment e,
  List<ImpactDay> days,
  Outcome outcome, {
  int seed = 1,
}) {
  final before = e.start.subtract(Duration(days: e.days));
  final rows = <ImpactDay>[];
  var kept = 0, logged = 0;
  for (final d in days) {
    if (d.y[outcome] == null) continue;
    final during = e.runningOn(d.date);
    final pre = !d.date.isBefore(before) && d.date.isBefore(e.start);
    if (!during && !pre) continue;
    if (during) {
      final v = d.x[e.key];
      if (v != null) {
        logged++;
        if ((v != 0) == e.doIt) kept++;
      }
    }
    rows.add(
      ImpactDay(
        date: d.date,
        x: {'_during': during ? 1 : 0},
        y: d.y,
        strain: d.strain,
        weekend: d.weekend,
      ),
    );
  }
  final nDuring = rows.where((r) => r.x['_during'] == 1).length;
  final nBefore = rows.length - nDuring;
  final i = impacts(
    rows,
    const [Behaviour('_during')],
    outcome,
    seed: seed,
  ).single;
  final enough = nBefore >= experimentMinDays && nDuring >= experimentMinDays;
  return ExperimentResult(
    outcome: outcome,
    effect: i.effect,
    low: i.low,
    high: i.high,
    daysBefore: nBefore,
    daysDuring: nDuring,
    adherence: logged == 0 ? 0 : kept / logged,
    confidence: enough ? i.confidence : ImpactConfidence.notEnough,
  );
}
