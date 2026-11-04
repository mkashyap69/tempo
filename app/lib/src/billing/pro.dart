import 'package:flutter_riverpod/flutter_riverpod.dart';

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
