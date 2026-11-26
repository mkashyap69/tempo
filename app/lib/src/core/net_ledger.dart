import 'dart:convert';

import 'package:store/store.dart' as st;

/// v3 privacy ledger: every network call Tempo makes, counted on the phone
/// by kind. Nothing about a call leaves the phone; only its kind and time
/// are kept, for 30 days.
const netLedgerKey = 'net_ledger';
const netLedgerDays = 30;

/// The kinds Tempo can make, in the order the ledger lists them, with the
/// words You → Privacy uses. Every allowed call is one of these
/// (CLAUDE.md: sign-in, billing, encrypted sync, diagnostics, feedback; plus
/// the opt-in weather lookup for Today).
const netKinds = {
  'weather': ('Weather for Today', 'location rounded to about 10 km'),
  'sync': ('Encrypted backup', 'sealed before it leaves the phone'),
  'signin': ('Sign-in', 'account only, no health data'),
  'diagnostics': ('Diagnostics', 'only if you opt in'),
  'feedback': ('Feedback you sent', 'you read it before it goes'),
};

/// [raw] with a call of [kind] at [at] added and anything older than
/// [netLedgerDays] dropped.
String addNetCall(String? raw, String kind, DateTime at) {
  final cut = at.subtract(const Duration(days: netLedgerDays));
  final rows = [
    for (final r in _rows(raw))
      if (r.$2.isAfter(cut)) r,
    (kind, at),
  ];
  return jsonEncode([
    for (final r in rows) {'k': r.$1, 'at': r.$2.toIso8601String()},
  ]);
}

/// Calls per kind since [since]; every known kind is present (0 if none).
Map<String, int> netCounts(String? raw, DateTime since) {
  final out = {for (final k in netKinds.keys) k: 0};
  for (final r in _rows(raw)) {
    if (!r.$2.isBefore(since)) out[r.$1] = (out[r.$1] ?? 0) + 1;
  }
  return out;
}

List<(String, DateTime)> _rows(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [
      for (final m in jsonDecode(raw) as List)
        if (DateTime.tryParse('${(m as Map)['at']}') case final at?)
          ('${m['k']}', at),
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> recordNetCall(st.TempoDb db, String kind, {DateTime? at}) async {
  final raw = await db.setting(netLedgerKey);
  await db.putSetting(
    netLedgerKey,
    addNetCall(raw, kind, at ?? DateTime.now()),
  );
}

Future<Map<String, int>> netCountsLastWeek(
  st.TempoDb db, {
  DateTime? now,
}) async => netCounts(
  await db.setting(netLedgerKey),
  (now ?? DateTime.now()).subtract(const Duration(days: 7)),
);
