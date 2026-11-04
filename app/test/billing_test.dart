import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/billing/account_ids.dart';
import 'package:tempo/src/billing/entitlement.dart';
import 'package:tempo/src/billing/products.dart';

void main() {
  // Same reference values as backend/test/account_ids.test.ts (Python uuid5
  // and hashlib), so app and server agree on who bought what.
  test('account ids match the backend', () {
    expect(appAccountToken('uid-123'), 'b74411ce-5581-53d0-82ad-f3dad3b4f929');
    expect(
      obfuscatedAccountId('uid-123'),
      '23481502b4881b15d1cc3216f86b19af5373e9a3c4ec2e91edd9dd0f00a8b414',
    );
  });

  test('product ids per platform', () {
    expect(ProProducts.ids(ios: true), {
      'tempo.pro.monthly',
      'tempo.pro.yearly',
      'tempo.pro.lifetime',
    });
    expect(ProProducts.ids(ios: false), {'pro', 'pro_lifetime'});
    expect(ProProducts.applePlan('tempo.pro.yearly'), ProPlan.yearly);
  });

  group('proOpen', () {
    final now = DateTime(2026, 11, 4, 8);
    CachedEntitlement e({
      bool pro = true,
      String source = 'ios_sub',
      DateTime? expiresAt,
      Duration checkedAgo = Duration.zero,
    }) => CachedEntitlement(
      pro: pro,
      source: source,
      expiresAt: expiresAt,
      inGrace: false,
      checkedAt: now.subtract(checkedAgo),
    );

    test('development builds are always Pro', () {
      expect(proOpen(null, now, storeBuild: false), isTrue);
    });
    test('store build with nothing cached is Free', () {
      expect(proOpen(null, now, storeBuild: true), isFalse);
      expect(proOpen(e(pro: false), now, storeBuild: true), isFalse);
    });
    test('an active subscription is Pro', () {
      expect(
        proOpen(
          e(expiresAt: now.add(const Duration(days: 20))),
          now,
          storeBuild: true,
        ),
        isTrue,
      );
    });
    test('offline up to 7 days keeps Pro, then it locks', () {
      final sub = e(
        expiresAt: now.add(const Duration(days: 1)),
        checkedAgo: const Duration(days: 6),
      );
      expect(proOpen(sub, now, storeBuild: true), isTrue);
      final stale = e(
        expiresAt: now.add(const Duration(days: 30)),
        checkedAgo: const Duration(days: 8),
      );
      expect(proOpen(stale, now, storeBuild: true), isFalse);
    });
    test('a period that ended over 7 days ago locks', () {
      expect(
        proOpen(
          e(expiresAt: now.subtract(const Duration(days: 8))),
          now,
          storeBuild: true,
        ),
        isFalse,
      );
    });
    test('lifetime never times out offline', () {
      expect(
        proOpen(
          e(source: 'lifetime_ios', checkedAgo: const Duration(days: 400)),
          now,
          storeBuild: true,
        ),
        isTrue,
      );
    });
    test('the cache round-trips; garbage reads as nothing', () {
      final c = e(
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      final back = CachedEntitlement.decode(c.encode())!;
      expect(back.expiresAt, c.expiresAt);
      expect(back.source, 'ios_sub');
      expect(CachedEntitlement.decode('{nope'), isNull);
    });
    test('api JSON', () {
      final c = CachedEntitlement.fromApi({
        'pro': true,
        'source': 'beta_grant',
        'expiresAt': null,
        'inGrace': false,
      }, now);
      expect(c.pro, isTrue);
      expect(c.expiresAt, isNull);
      expect(c.checkedAt, now);
    });
  });
}
