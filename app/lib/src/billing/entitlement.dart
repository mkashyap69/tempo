import 'dart:convert';

/// The account's Pro state as the backend last said it
/// (`entitlements/{uid}`), cached on the phone so Tempo works offline.
class CachedEntitlement {
  const CachedEntitlement({
    required this.pro,
    required this.source,
    required this.expiresAt,
    required this.inGrace,
    required this.checkedAt,
  });

  final bool pro;

  /// lifetime_ios, lifetime_android, ios_sub, android_sub, beta_grant, none.
  final String source;
  final DateTime? expiresAt;
  final bool inGrace;

  /// When the phone last heard from the backend.
  final DateTime checkedAt;

  bool get lifetime => source.startsWith('lifetime');

  /// From the api's JSON (epoch ms times).
  factory CachedEntitlement.fromApi(Map<String, Object?> j, DateTime now) =>
      CachedEntitlement(
        pro: j['pro'] == true,
        source: (j['source'] as String?) ?? 'none',
        expiresAt: j['expiresAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(j['expiresAt']! as int)
            : null,
        inGrace: j['inGrace'] == true,
        checkedAt: now,
      );

  String encode() => jsonEncode({
    'pro': pro,
    'source': source,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
    'inGrace': inGrace,
    'checkedAt': checkedAt.millisecondsSinceEpoch,
  });

  static CachedEntitlement? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s) as Map<String, Object?>;
      return CachedEntitlement(
        pro: j['pro'] == true,
        source: (j['source'] as String?) ?? 'none',
        expiresAt: j['expiresAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(j['expiresAt']! as int)
            : null,
        inGrace: j['inGrace'] == true,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(j['checkedAt']! as int),
      );
    } catch (_) {
      return null;
    }
  }
}

/// How long Pro stays on without hearing from the backend (Backend plan →
/// Accounts → Offline).
const offlineGrace = Duration(days: 7);

/// Whether Pro features are open.
///
/// Builds that aren't store builds (development, the band build) are always
/// Pro. A store build is Pro when the cached entitlement says so, it was
/// checked within [offlineGrace], and it hasn't ended more than
/// [offlineGrace] ago. A lifetime purchase never times out offline. Free
/// features and the user's data are never locked either way.
bool proOpen(CachedEntitlement? c, DateTime now, {required bool storeBuild}) {
  if (!storeBuild) return true;
  if (c == null || !c.pro) return false;
  if (c.lifetime) return true;
  if (now.difference(c.checkedAt) > offlineGrace) return false;
  final end = c.expiresAt;
  return end == null || now.isBefore(end.add(offlineGrace));
}
