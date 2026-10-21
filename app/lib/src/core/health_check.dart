import 'package:health_source/health_source.dart';
import 'package:store/store.dart';

import 'health_reader.dart';
import 'health_sync.dart';
import 'profile.dart' show Keys;

/// How one kind compares between Health and what Tempo stored.
enum KindVerdict {
  /// Every usable record Health has before the last read is stored.
  ok,

  /// Health has no records of this kind in the window.
  empty,

  /// Health has records Tempo didn't store (a read missed them).
  missing,

  /// Tempo stores records Health no longer has (not yet tombstoned).
  extra,

  /// Values outside what this kind can be: wrong unit or bad data.
  odd,

  /// The read threw.
  failed,
}

/// One kind's side-by-side count.
final class KindCheck {
  const KindCheck({
    required this.kind,
    required this.verdict,
    this.inHealth = 0,
    this.dropped = 0,
    this.stored = 0,
    this.missing = 0,
    this.extra = 0,
    this.newer = 0,
    this.odd = 0,
    this.latest,
    this.min,
    this.max,
    this.sources = const {},
    this.error,
  });
  final HealthKind kind;
  final KindVerdict verdict;

  /// Records Health returned for the window.
  final int inHealth;

  /// Of those, ones a read skips on purpose (Tempo's own, too long, NaN).
  final int dropped;

  /// Live records Tempo holds for the compared part of the window.
  final int stored;

  /// Usable in Health, not stored / stored, not in Health.
  final int missing, extra;

  /// Written after the last read: the next read picks them up.
  final int newer;

  /// Usable records whose value is outside [plausible].
  final int odd;
  final DateTime? latest;
  final double? min, max;

  /// Source app id → records, from Health.
  final Map<String, int> sources;
  final String? error;
}

final class HealthCheckReport {
  const HealthCheckReport({
    required this.from,
    required this.to,
    required this.lastRead,
    required this.access,
    required this.kinds,
  });
  final DateTime from, to;

  /// Records starting before this are compared; later ones are [KindCheck.newer].
  final DateTime? lastRead;
  final bool access;
  final List<KindCheck> kinds;

  bool get allOk => access && kinds.every((k) => k.verdict == KindVerdict.ok);

  /// Plain text, to paste into an issue or a chat.
  String text(String label, Map<String, String> names) {
    final b = StringBuffer()
      ..writeln('Tempo · $label data check')
      ..writeln('Window ${from.toIso8601String()} – ${to.toIso8601String()}')
      ..writeln('Last read ${lastRead?.toIso8601String() ?? 'never'}')
      ..writeln('Access ${access ? 'yes' : 'no'}');
    for (final k in kinds) {
      b.write(
        '${k.kind.name}: ${k.verdict.name} · health ${k.inHealth}'
        ' (dropped ${k.dropped}, newer ${k.newer}) · stored ${k.stored}',
      );
      if (k.missing > 0) b.write(' · missing ${k.missing}');
      if (k.extra > 0) b.write(' · extra ${k.extra}');
      if (k.odd > 0) b.write(' · odd ${k.odd}');
      if (k.min != null) b.write(' · range ${_n(k.min!)}–${_n(k.max!)}');
      if (k.latest != null) b.write(' · latest ${k.latest!.toIso8601String()}');
      if (k.sources.isNotEmpty) {
        b.write(
          ' · from ${[for (final e in k.sources.entries) '${sourceLabel(e.key, names)} ${e.value}'].join(', ')}',
        );
      }
      if (k.error != null) b.write(' · error ${k.error}');
      b.writeln();
    }
    return b.toString();
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// Values a kind can plausibly hold, as the plugin gives them. Wide on
/// purpose: it catches a wrong unit (SpO₂ as 97 where 0.97 was expected is
/// fine either way; 9700 isn't), not a merely unusual night. Null: no check.
/// TODO(verify): units per platform, against a real phone.
(double, double)? plausible(HealthKind k) => switch (k) {
  HealthKind.heartRate => (25, 250),
  HealthKind.restingHr => (25, 130),
  HealthKind.steps => (0, 60000),
  HealthKind.hrvSdnn || HealthKind.hrvRmssd => (1, 300),
  // iOS gives a fraction, Health Connect a percent.
  HealthKind.spo2 => (0.5, 100),
  HealthKind.respiratoryRate => (3, 60),
  HealthKind.water => (0, 10),
  HealthKind.caffeine => (0, 2),
  // iOS: absolute °C; Health Connect: change from baseline.
  HealthKind.wristTemp => (-10, 45),
  _ => null,
};

/// Reads the last [window] of every kind straight from Health and compares
/// it with `health_records`. Read-only: writes nothing to the database or
/// to Health.
///
/// Records starting before the last read are compared one by one (by
/// [HealthRecord.key]); later ones are only counted, since the sync hasn't
/// had a chance to see them.
Future<HealthCheckReport> checkHealth(
  TempoDb db,
  HealthReader reader, {
  Duration window = const Duration(days: 7),
  DateTime? now,
}) async {
  final to = now ?? DateTime.now();
  final from = to.subtract(window);
  final lastRead = DateTime.tryParse(await db.setting(Keys.lastSync) ?? '');
  final access = await reader.hasAccess();
  // Before the window or after now, a last read compares nothing.
  final cut = lastRead == null || lastRead.isBefore(from)
      ? from
      : lastRead.isAfter(to)
      ? to
      : lastRead;
  final storedByKind = <String, Set<String>>{};
  for (final r in await db.healthRecordsStarting(from, cut)) {
    storedByKind.putIfAbsent(r.kind, () => {}).add(r.key);
  }
  final kinds = reader.kinds.toList()..sort((a, b) => a.index - b.index);
  final out = <KindCheck>[];
  for (final kind in kinds) {
    List<HealthRecord> rs;
    try {
      rs = await reader.read(kind, from, to);
    } catch (e) {
      out.add(KindCheck(kind: kind, verdict: KindVerdict.failed, error: '$e'));
      continue;
    }
    final usable = [
      for (final r in rs)
        if (HealthSyncService.usable(r)) r,
    ];
    final before = {
      for (final r in usable)
        if (r.start.isBefore(cut)) r.key,
    };
    final stored = storedByKind[kind.name] ?? const <String>{};
    final range = plausible(kind);
    var odd = 0;
    double? lo, hi;
    DateTime? latest;
    final sources = <String, int>{};
    for (final r in usable) {
      if (range != null) {
        if (r.value < range.$1 || r.value > range.$2) odd++;
        lo = lo == null || r.value < lo ? r.value : lo;
        hi = hi == null || r.value > hi ? r.value : hi;
      }
      if (latest == null || r.end.isAfter(latest)) latest = r.end;
      sources[r.sourceApp] = (sources[r.sourceApp] ?? 0) + 1;
    }
    final missing = before.difference(stored).length;
    final extra = stored.difference(before).length;
    out.add(
      KindCheck(
        kind: kind,
        verdict: rs.isEmpty && stored.isEmpty
            ? KindVerdict.empty
            : missing > 0
            ? KindVerdict.missing
            : odd > 0
            ? KindVerdict.odd
            : extra > 0
            ? KindVerdict.extra
            : KindVerdict.ok,
        inHealth: rs.length,
        dropped: rs.length - usable.length,
        stored: stored.length,
        missing: missing,
        extra: extra,
        newer: usable.length - before.length,
        odd: odd,
        latest: latest,
        min: lo,
        max: hi,
        sources: sources,
      ),
    );
  }
  return HealthCheckReport(
    from: from,
    to: to,
    lastRead: lastRead,
    access: access,
    kinds: out,
  );
}
