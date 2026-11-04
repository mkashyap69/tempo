import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_service.dart';
import '../billing/pro.dart';
import '../core/build_info.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'paywall.dart';

/// "Tempo Pro · Yearly, renews 4 Nov 2027" and the like, for You.
String proStatusLine(WidgetRef ref) {
  if (!BuildInfo.store) return 'On · development build';
  final e = ref.watch(entitlementProvider);
  if (!ref.watch(proProvider) || e == null) return 'Free';
  String date(DateTime d) =>
      '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  return switch (e.source) {
    'lifetime_ios' || 'lifetime_android' => 'Lifetime',
    'beta_grant' =>
      e.expiresAt == null ? 'Beta' : 'Beta · until ${date(e.expiresAt!)}',
    _ when e.inGrace => 'Payment issue · fix it in the store',
    _ => e.expiresAt == null ? 'On' : 'Renews or ends ${date(e.expiresAt!)}',
  };
}

/// You → Account (launch plan L-O1). An account is optional: it carries
/// Pro to your other phones and platforms and, when backup ships, restores
/// your history on a new phone. Health data never goes to the account.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _a = AccountService.instance;
  final _email = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;
  bool _linkSent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _a.ensureReady().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      await ref.read(billingProvider).refresh();
      if (mounted && done != null) showTempoToast(context, done);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'That didn’t work. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!_a.available) {
      return Scaffold(
        backgroundColor: c.bg,
        body: TempoPage(
          children: [
            const DetailHeader(title: 'Account'),
            Text(
              'This build has no account service. Everything works on this phone as before.',
              style: TempoType.body.c(c.text2),
            ),
          ],
        ),
      );
    }
    final signedIn = _a.signedIn;
    return Scaffold(
      backgroundColor: c.bg,
      body: TempoPage(
        children: [
          const DetailHeader(title: 'Account'),
          Text(
            signedIn
                ? 'Signed in as ${_a.email ?? 'your Apple or Google account'}.'
                : 'An account is optional. It keeps Tempo Pro with you on a new phone or on the other platform. Your health data stays on this phone either way.',
            style: TempoType.body.c(c.text2),
          ),
          CardList(
            children: [
              ListRow(
                'Tempo Pro',
                value: proStatusLine(ref),
                onTap: ref.watch(proProvider)
                    ? null
                    : () => showPaywall(context, PaywallEntry.settings),
              ),
              ListRow(
                'Restore purchases',
                sub:
                    'Finds Pro bought with this ${Platform.isIOS ? 'Apple ID' : 'Google account'}',
                onTap: _busy
                    ? null
                    : () => _run(
                        () => ref.read(billingProvider).restore(),
                        done: 'Checked your purchases',
                      ),
              ),
              ListRow(
                'Manage subscription',
                sub: 'Cancel or change plans in the store',
                onTap: () => launchUrl(
                  Uri.parse(
                    Platform.isIOS
                        ? 'https://apps.apple.com/account/subscriptions'
                        : 'https://play.google.com/store/account/subscriptions',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          if (!signedIn) ...[
            if (Platform.isIOS)
              TempoButton(
                'Continue with Apple',
                expand: true,
                onTap: _busy
                    ? null
                    : () => _run(_a.signInWithApple, done: 'Signed in'),
              ),
            TempoButton(
              'Continue with Google',
              expand: true,
              kind: ButtonKind.secondary,
              onTap: _busy
                  ? null
                  : () => _run(_a.signInWithGoogle, done: 'Signed in'),
            ),
            Section(
              title: 'Or with email',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  TempoField(
                    controller: _email,
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (!_linkSent)
                    TempoButton(
                      'Email me a sign-in link',
                      kind: ButtonKind.secondary,
                      expand: true,
                      onTap: _busy
                          ? null
                          : () => _run(() async {
                              await _a.sendEmailLink(_email.text.trim());
                              if (mounted) setState(() => _linkSent = true);
                            }),
                    )
                  else ...[
                    Text(
                      'Open the link in the email on this phone. If it opens a browser instead, paste it here.',
                      style: TempoType.bodyS.c(c.text2),
                    ),
                    TempoField(controller: _link, hint: 'Paste the link'),
                    TempoButton(
                      'Sign in',
                      expand: true,
                      onTap: _busy
                          ? null
                          : () => _run(() async {
                              final ok = await _a.completeEmailLink(
                                _email.text.trim(),
                                _link.text.trim(),
                              );
                              if (!ok && mounted) {
                                setState(
                                  () => _error =
                                      'That isn’t a Tempo sign-in link.',
                                );
                              }
                            }, done: 'Signed in'),
                    ),
                  ],
                ],
              ),
            ),
          ] else
            CardList(
              children: [
                ListRow(
                  'Sign out',
                  sub: 'Your data stays on this phone',
                  onTap: _busy
                      ? null
                      : () => _run(_a.signOut, done: 'Signed out'),
                ),
                ListRow(
                  'Delete account',
                  color: context.s.recLow,
                  sub: 'Removes your account and anything stored with it',
                  onTap: _busy
                      ? null
                      : () async {
                          final ok = await confirmSheet(
                            context,
                            title: 'Delete your account?',
                            body: 'Your account and its backup are deleted from Tempo’s servers, usually within minutes. Your data on this phone stays. A subscription isn’t cancelled by this: cancel it in the store.',
                            action: 'Delete account',
                            danger: true,
                          );
                          if (ok) {
                            await _run(
                              _a.deleteAccount,
                              done: 'Account deleted',
                            );
                          }
                        },
                ),
              ],
            ),
          if (_error != null)
            Text(_error!, style: TempoType.bodyS.c(context.s.recLow)),
        ],
      ),
    );
  }
}
