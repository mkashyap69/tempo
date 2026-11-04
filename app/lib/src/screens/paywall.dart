import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/backend_config.dart';
import '../billing/billing_service.dart';
import '../billing/pro.dart';
import '../billing/products.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'nav.dart';

/// Where the paywall was opened from (the `paywall_view` event's `entry`).
enum PaywallEntry {
  onboarding,
  coach,
  goal,
  trends,
  longevity,
  weekReview,
  settings,
  other,
}

/// What Pro adds (launch plan §3). Free keeps the day's scores, sleep, live
/// workouts, widgets, 30 days of Trends, journal logging and backup.
const proBenefits = [
  (
    'Your coach',
    'A plan that adapts to your recovery every morning, with Move or skip and the reasons why.',
  ),
  (
    'Goals that progress',
    'Get fitter, run faster, Get stronger: blocks that build, tune up and set the next goal.',
  ),
  (
    'The long view',
    'Every trend past 30 days, cardio load and your full week story.',
  ),
  (
    'What works for you',
    'Journal impact: which habits move your recovery and sleep.',
  ),
  ('Tempo Age', 'Your longevity estimate, with blood work.'),
  ('Sleep plan', 'The 21-day plan built around your sleep type.'),
];

/// Opens the paywall; returns true when Pro is open afterwards.
Future<bool> showPaywall(BuildContext context, PaywallEntry entry) async =>
    await push<bool>(context, PaywallScreen(entry: entry)) ?? false;

/// The Pro paywall. Meets App Store guideline 3.1.2 and Play's subscription
/// rules: price per period, what the trial turns into and when, how to
/// cancel, Restore, and the terms and privacy links, all on this screen.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, required this.entry});
  final PaywallEntry entry;
  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  List<ProOffer>? _offers;
  ProPlan _plan = ProPlan.yearly;
  bool _busy = false;
  String? _note;
  StreamSubscription<BuyResult>? _sub;

  @override
  void initState() {
    super.initState();
    final b = ref.read(billingProvider);
    _sub = b.results.listen(_onResult);
    b.offers().then((o) {
      if (mounted) setState(() => _offers = o);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onResult(BuyResult r) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = switch (r) {
        BuyResult.pro => null,
        BuyResult.pending => 'Waiting for the store to confirm the payment. Pro opens when it does.',
        BuyResult.cancelled => null,
        BuyResult.otherAccount => 'This purchase belongs to another Tempo account. Sign in to that account in You → Account to use it.',
        BuyResult.failed => 'The purchase didn’t go through. You haven’t been charged twice; try again, or Restore if you already paid.',
        BuyResult.unavailable =>
          'Purchases aren’t available on this phone right now.',
      };
    });
    if (r == BuyResult.pro) {
      showTempoToast(context, 'Tempo Pro is on');
      Navigator.of(context).pop(true);
    }
  }

  ProOffer? get _selected => _offers?.where((o) => o.plan == _plan).firstOrNull;

  Future<void> _buy() async {
    final o = _selected;
    if (o == null) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    final started = await ref.read(billingProvider).buy(o);
    if (!started && mounted) _onResult(BuyResult.unavailable);
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    await ref.read(billingProvider).restore();
    await ref.read(billingProvider).refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref.read(proProvider)) {
      showTempoToast(context, 'Tempo Pro restored');
      Navigator.of(context).pop(true);
    } else {
      setState(
        () => _note =
            'No Tempo Pro purchase found for this ${Platform.isIOS ? 'Apple ID' : 'Google account'}.',
      );
    }
  }

  String _cta(ProOffer o) => switch (o.plan) {
    ProPlan.yearly when o.trialDays != null =>
      'Start ${o.trialDays}-day free trial',
    ProPlan.lifetime => 'Buy for ${o.price}',
    _ => 'Subscribe for ${o.price}',
  };

  String _terms(ProOffer o) {
    final store = Platform.isIOS ? 'Apple ID' : 'Google Play account';
    final manage = Platform.isIOS
        ? 'Settings → your name → Subscriptions'
        : 'Google Play → Payments & subscriptions';
    return switch (o.plan) {
      ProPlan.lifetime =>
        'One payment of ${o.price}, charged to your $store. Pro stays on for good, on iPhone and Android with your Tempo account.',
      ProPlan.yearly when o.trialDays != null =>
        'Free for ${o.trialDays} days, then ${o.price} a year, charged to your $store when the trial ends. Renews every year unless cancelled at least 24 hours before the period ends. Cancel any time in $manage.',
      ProPlan.yearly =>
        '${o.price} a year, charged to your $store. Renews every year unless cancelled at least 24 hours before the period ends. Cancel any time in $manage.',
      ProPlan.monthly =>
        '${o.price} a month, charged to your $store. Renews every month unless cancelled at least 24 hours before the period ends. Cancel any time in $manage.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final offers = _offers;
    final o = _selected;
    return Scaffold(
      backgroundColor: c.bg,
      body: TempoPage(
        children: [
          DetailHeader(
            title: 'Tempo Pro',
            leadingIcon: TempoIcons.close,
            onBack: () => Navigator.of(context).pop(false),
          ),
          Text(
            'Your scores stay free. Pro adds the coach that tells you what to do about them, and the long view.',
            style: TempoType.body.c(c.text2),
          ),
          CardList(
            children: [
              for (final (t, s) in proBenefits)
                ListRow(t, sub: s, chevron: false),
            ],
          ),
          if (offers == null)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (offers.isEmpty)
            Text(
              'Tempo Pro isn’t available to buy in this build or on this phone yet.',
              style: TempoType.body.c(c.text2),
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final x in offers)
                  _PlanCard(
                    offer: x,
                    selected: x.plan == _plan,
                    yearlySaving: _saving(offers),
                    onTap: () => setState(() => _plan = x.plan),
                  ),
              ],
            ),
            if (o != null) ...[
              TempoButton(_cta(o), expand: true, onTap: _busy ? null : _buy),
              Text(_terms(o), style: TempoType.caption.c(c.text3)),
            ],
          ],
          if (_note != null) Text(_note!, style: TempoType.bodyS.c(c.text2)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TempoButton(
                'Restore purchases',
                kind: ButtonKind.text,
                small: true,
                onTap: _busy ? null : _restore,
              ),
              Row(
                children: [
                  TempoButton(
                    'Terms',
                    kind: ButtonKind.text,
                    small: true,
                    onTap: () => launchUrl(Uri.parse(BackendConfig.termsUrl)),
                  ),
                  TempoButton(
                    'Privacy',
                    kind: ButtonKind.text,
                    small: true,
                    onTap: () => launchUrl(Uri.parse(BackendConfig.privacyUrl)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Save 44 %" on the yearly plan against twelve months, when both have prices.
  static int? _saving(List<ProOffer> offers) {
    final m = offers.where((o) => o.plan == ProPlan.monthly).firstOrNull;
    final y = offers.where((o) => o.plan == ProPlan.yearly).firstOrNull;
    if (m == null || y == null || m.details.rawPrice <= 0) return null;
    final s = 1 - y.details.rawPrice / (m.details.rawPrice * 12);
    return s > 0.05 ? (s * 100).round() : null;
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.onTap,
    this.yearlySaving,
  });
  final ProOffer offer;
  final bool selected;
  final VoidCallback onTap;
  final int? yearlySaving;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = offer.details;
    final (title, sub) = switch (offer.plan) {
      ProPlan.yearly => (
        'Yearly',
        [
          '${d.price} a year · ${d.currencySymbol}${(d.rawPrice / 12).toStringAsFixed(2)} a month',
          if (offer.trialDays != null) '${offer.trialDays} days free',
          if (yearlySaving != null) 'save $yearlySaving %',
        ].join(' · '),
      ),
      ProPlan.monthly => ('Monthly', '${d.price} a month'),
      ProPlan.lifetime => ('Lifetime', '${d.price} once'),
    };
    return TempoCard(
      onTap: onTap,
      label: '$title, $sub',
      border: selected ? c.text1 : c.line,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TempoType.titleM.c(c.text1)),
                const SizedBox(height: 2),
                Text(sub, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
          TempoIcon(
            selected ? TempoIcons.check : TempoIcons.dot,
            color: c.text1,
          ),
        ],
      ),
    );
  }
}

/// A locked Pro feature: what it is, and the way in. Shown instead of the
/// feature in store builds without Pro.
class ProLock extends StatelessWidget {
  const ProLock({
    super.key,
    required this.title,
    required this.body,
    required this.entry,
  });
  final String title, body;
  final PaywallEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TempoCard(
      label: '$title, Tempo Pro',
      onTap: () => showPaywall(context, entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              TempoIcon(TempoIcons.private, size: 18, color: c.text2),
              Overline('Tempo Pro', color: c.text2),
            ],
          ),
          Text(title, style: TempoType.titleM.c(c.text1)),
          Text(body, style: TempoType.body.c(c.text2)),
          TempoButton(
            'See Tempo Pro',
            small: true,
            kind: ButtonKind.secondary,
            onTap: () => showPaywall(context, entry),
          ),
        ],
      ),
    );
  }
}

/// Shows [child] when Pro is open; otherwise a page with [ProLock].
/// [tab] pages have no back button (the Plan tab).
class ProGate extends ConsumerWidget {
  const ProGate({
    super.key,
    required this.child,
    required this.title,
    required this.lockTitle,
    required this.body,
    required this.entry,
    this.tab = false,
  });
  final Widget child;
  final String title, lockTitle, body;
  final PaywallEntry entry;
  final bool tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(proProvider)) return child;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: TempoPage(
        children: [
          if (tab)
            Text(title, style: TempoType.pageTitle.c(c.text1))
          else
            DetailHeader(title: title),
          ProLock(title: lockTitle, body: body, entry: entry),
        ],
      ),
    );
  }
}
