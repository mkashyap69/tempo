import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:store/store.dart';

import '../account/account_service.dart';
import '../account/api_client.dart';
import '../core/profile.dart' show Keys;
import 'account_ids.dart';
import 'entitlement.dart';
import 'products.dart';

/// One choice on the paywall.
class ProOffer {
  const ProOffer(this.plan, this.details, {this.trialDays});
  final ProPlan plan;
  final ProductDetails details;

  /// A free trial on this offer (the yearly plan's 7 days), or null.
  final int? trialDays;

  String get price => details.price;
}

/// What a purchase ended in, for the paywall to say.
enum BuyResult { pro, pending, cancelled, otherAccount, failed, unavailable }

/// Buying and restoring Pro (Backend plan → Purchase flow). The store takes
/// the payment; `api` verifies it and owns the entitlement; the phone caches
/// that answer ([CachedEntitlement]) so Pro works offline.
class BillingService {
  BillingService(this.db, {InAppPurchase? iap, AccountService? account})
    : _iap = iap ?? InAppPurchase.instance,
      _account = account ?? AccountService.instance;

  final TempoDb db;
  final InAppPurchase _iap;
  final AccountService _account;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _results = StreamController<BuyResult>.broadcast();

  bool get _ios => Platform.isIOS;

  Stream<BuyResult> get results => _results.stream;

  /// Starts listening for purchases, including ones finished while the app
  /// was closed or verification failed offline (the store redelivers them
  /// until they're completed).
  void start() {
    if (!_account.available) return;
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _results.close();
  }

  Future<List<ProOffer>> offers() async {
    if (!_account.available || !await _iap.isAvailable()) return const [];
    final r = await _iap.queryProductDetails(ProProducts.ids(ios: _ios));
    final out = <ProOffer>[];
    for (final d in r.productDetails) {
      if (_ios) {
        final plan = ProProducts.applePlan(d.id);
        if (plan != null) {
          // Introductory offers aren't exposed by the plugin's details; the
          // yearly plan has the trial (set in App Store Connect).
          out.add(
            ProOffer(plan, d, trialDays: plan == ProPlan.yearly ? 7 : null),
          );
        }
      } else if (d is GooglePlayProductDetails) {
        if (d.id == ProProducts.playLifetime) {
          out.add(ProOffer(ProPlan.lifetime, d));
          continue;
        }
        final i = d.subscriptionIndex;
        final o = i == null
            ? null
            : d.productDetails.subscriptionOfferDetails?[i];
        if (o == null) continue;
        final plan = {
          for (final e in ProProducts.playBasePlans.entries) e.value: e.key,
        }[o.basePlanId];
        if (plan == null) continue;
        final trial =
            o.pricingPhases.isNotEmpty &&
                o.pricingPhases.first.priceAmountMicros == 0
            ? 7
            : null;
        // One offer per plan: prefer the trial offer, else the base plan.
        final existing = out.indexWhere((x) => x.plan == plan);
        if (existing == -1) {
          out.add(ProOffer(plan, d, trialDays: trial));
        } else if (trial != null && out[existing].trialDays == null) {
          out[existing] = ProOffer(plan, d, trialDays: trial);
        }
      }
    }
    out.sort((a, b) => a.plan.index.compareTo(b.plan.index));
    return out;
  }

  /// Starts a purchase. The result arrives on [results].
  Future<bool> buy(ProOffer offer) async {
    final uid = await _account.uid();
    if (uid == null) return false;
    final user = _ios ? appAccountToken(uid) : obfuscatedAccountId(uid);
    final param = !_ios && offer.details is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: offer.details,
            applicationUserName: user,
            offerToken: (offer.details as GooglePlayProductDetails).offerToken,
          )
        : PurchaseParam(
            productDetails: offer.details,
            applicationUserName: user,
          );
    // Subscriptions and the lifetime unlock are both non-consumable here.
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Asks the store for what this store account owns; each comes back on
  /// the purchase stream and is verified like a new purchase.
  Future<void> restore() async {
    final uid = await _account.uid();
    if (uid == null) return;
    await _iap.restorePurchases(
      applicationUserName: _ios
          ? appAccountToken(uid)
          : obfuscatedAccountId(uid),
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _results.add(BuyResult.pending);
        case PurchaseStatus.canceled:
          _results.add(BuyResult.cancelled);
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.error:
          _results.add(BuyResult.failed);
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    final api = await _account.api();
    if (api == null) return;
    try {
      final data = p.verificationData.serverVerificationData;
      final e = _ios
          ? await api.verifyApple(data)
          : await api.verifyGoogle(
              p.productID == ProProducts.playLifetime
                  ? ProProducts.playLifetime
                  : ProProducts.playSubscription,
              data,
            );
      await _save(CachedEntitlement.fromApi(e, DateTime.now()));
      // Completing only after our server has it: if this fails, the store
      // redelivers the purchase on the next start.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      _results.add(BuyResult.pro);
    } on ApiException catch (e) {
      if (e.code == 'other_account') {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        _results.add(BuyResult.otherAccount);
      } else {
        _results.add(BuyResult.failed);
      }
    } catch (_) {
      // Offline or the api is down: left pending, retried on next start.
      _results.add(BuyResult.failed);
    }
  }

  Future<void> _save(CachedEntitlement e) =>
      db.putSetting(Keys.proEntitlement, e.encode());

  /// Refreshes the cached entitlement from the api (on open, at most daily
  /// by the caller). Offline leaves the cache as it is. Does nothing until
  /// there is a user: an install that never bought or signed in never gets
  /// an account (L-O1).
  Future<CachedEntitlement?> refresh() async {
    if (!await _account.ensureReady() || _account.user == null) return null;
    try {
      final api = await _account.api();
      if (api == null) return null;
      final e = CachedEntitlement.fromApi(await api.init(), DateTime.now());
      await _save(e);
      return e;
    } catch (_) {
      return null;
    }
  }
}
