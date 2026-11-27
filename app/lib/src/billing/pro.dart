import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';

import '../core/build_info.dart';
import '../core/profile.dart' show Keys;
import '../state/providers.dart';
import 'billing_service.dart';
import 'entitlement.dart';

/// The cached entitlement, or null before the first answer.
final entitlementProvider = Provider<CachedEntitlement?>(
  (ref) => CachedEntitlement.decode(
    ref.watch(settingProvider(Keys.proEntitlement)).value,
  ),
);

/// Whether Pro features are open (billing/entitlement.dart → proOpen).
/// Development builds are always Pro.
final proProvider = Provider<bool>(
  (ref) => proOpen(
    ref.watch(entitlementProvider),
    DateTime.now(),
    storeBuild: BuildInfo.store,
  ),
);

final billingProvider = Provider<BillingService>((ref) {
  final b = BillingService(ref.watch(dbProvider))..start();
  ref.onDispose(b.dispose);
  return b;
});

/// [proProvider] for code outside the widget tree (background sync,
/// notification planning, home widgets).
Future<bool> proOpenInDb(TempoDb db) async => proOpen(
  CachedEntitlement.decode(await db.setting(Keys.proEntitlement)),
  DateTime.now(),
  storeBuild: BuildInfo.store,
);

/// Coach notifications that are Pro (launch plan §3: "nudges beyond the
/// morning call"). Free keeps the morning call, the bedtime nudge, body
/// signals, the weekly report, the journal check-in and the post-workout
/// effort question.
const proNudgeKinds = {
  sc.NudgeKind.session,
  sc.NudgeKind.missed,
  sc.NudgeKind.lever,
  sc.NudgeKind.win,
  sc.NudgeKind.weekGoal,
  sc.NudgeKind.insight,
  sc.NudgeKind.comeback,
};
