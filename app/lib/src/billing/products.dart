/// Store product ids. backend/src/products.ts holds the same.
enum ProPlan { monthly, yearly, lifetime }

abstract final class ProProducts {
  /// iOS: subscriptions in group "Pro", plus a non-consumable.
  static const apple = {
    ProPlan.monthly: 'tempo.pro.monthly',
    ProPlan.yearly: 'tempo.pro.yearly',
    ProPlan.lifetime: 'tempo.pro.lifetime',
  };

  /// Play: subscription `pro` with base plans `monthly` and `yearly`, and a
  /// one-time product.
  static const playSubscription = 'pro';
  static const playLifetime = 'pro_lifetime';
  static const playBasePlans = {
    ProPlan.monthly: 'monthly',
    ProPlan.yearly: 'yearly',
  };

  /// The ids to query from the store on this platform.
  static Set<String> ids({required bool ios}) =>
      ios ? apple.values.toSet() : {playSubscription, playLifetime};

  static ProPlan? applePlan(String productId) =>
      {for (final e in apple.entries) e.value: e.key}[productId];
}
