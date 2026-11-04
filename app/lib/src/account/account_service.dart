import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';
import 'backend_config.dart';

/// Who the user is to the backend (launch plan L-O1).
///
/// Accounts are optional. Until the user signs in, the app holds an
/// anonymous Firebase user, created the first time something needs one (a
/// purchase), so a purchase still has an owner. Signing in with Apple,
/// Google or an email link links that anonymous user, keeping its uid and
/// so its purchases. Nothing about the account touches the health data on
/// the phone.
class AccountService {
  AccountService._();
  static final instance = AccountService._();

  bool _ready = false;
  ApiClient? _api;

  /// False when this build has no backend configured ([BackendConfig]).
  bool get available => BackendConfig.configured;

  Future<bool> ensureReady() async {
    if (!available) return false;
    if (_ready) return true;
    await Firebase.initializeApp(options: BackendConfig.firebaseOptions);
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _api = ApiClient(BackendConfig.apiUrl, _tokens);
    _ready = true;
    return true;
  }

  Future<({String idToken, String? appCheck})> _tokens() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException(401, 'signed_out');
    final id = await user.getIdToken();
    String? ac;
    try {
      ac = await FirebaseAppCheck.instance.getToken();
    } catch (_) {
      // The api answers 401 without it; surfaced to the caller there.
    }
    return (idToken: id!, appCheck: ac);
  }

  User? get user => _ready ? FirebaseAuth.instance.currentUser : null;

  /// True once the user signed in with Apple, Google or email (not anonymous).
  bool get signedIn => !(user?.isAnonymous ?? true);

  String? get email => user?.email;

  Stream<User?> get changes => _ready
      ? FirebaseAuth.instance.userChanges()
      : const Stream<User?>.empty();

  /// The api, with a user (anonymous if none yet) and the account record.
  /// Null when the build has no backend.
  Future<ApiClient?> api() async {
    if (!await ensureReady()) return null;
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    return _api;
  }

  /// The current uid, creating the anonymous user if needed.
  Future<String?> uid() async {
    await api();
    return user?.uid;
  }

  Future<UserCredential> _linkOrSignIn(
    Future<UserCredential> Function(User) link,
    Future<UserCredential> Function() signIn,
  ) async {
    await ensureReady();
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && u.isAnonymous) {
      try {
        return await link(u);
      } on FirebaseAuthException catch (e) {
        // The provider already has its own account (signed in before on
        // another phone): switch to it. Purchases made anonymously here
        // are offered for moving by Restore.
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
      }
    }
    return signIn();
  }

  Future<void> signInWithApple() async {
    final p = AppleAuthProvider()..addScope('email');
    await _linkOrSignIn(
      (u) => u.linkWithProvider(p),
      () => FirebaseAuth.instance.signInWithProvider(p),
    );
    await _api?.init();
  }

  Future<void> signInWithGoogle() async {
    await ensureReady();
    final g = GoogleSignIn.instance;
    await g.initialize(
      clientId: Platform.isIOS && BackendConfig.googleIosClientId.isNotEmpty
          ? BackendConfig.googleIosClientId
          : null,
      serverClientId: BackendConfig.googleServerClientId.isEmpty
          ? null
          : BackendConfig.googleServerClientId,
    );
    final account = await g.authenticate();
    final cred = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    await _linkOrSignIn(
      (u) => u.linkWithCredential(cred),
      () => FirebaseAuth.instance.signInWithCredential(cred),
    );
    await _api?.init();
  }

  /// Sends the sign-in link (decision G-O3). The link opens the app, which
  /// calls [completeEmailLink].
  Future<void> sendEmailLink(String email) async {
    await ensureReady();
    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: BackendConfig.emailLinkUrl,
        handleCodeInApp: true,
        iOSBundleId: 'dev.tempo.tempo',
        androidPackageName: 'dev.tempo.tempo',
        androidInstallApp: false,
      ),
    );
  }

  Future<bool> completeEmailLink(String email, String link) async {
    await ensureReady();
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return false;
    final cred = EmailAuthProvider.credentialWithLink(
      email: email,
      emailLink: link,
    );
    await _linkOrSignIn(
      (u) => u.linkWithCredential(cred),
      () => FirebaseAuth.instance.signInWithCredential(cred),
    );
    await _api?.init();
    return true;
  }

  /// Signs out; the phone's data stays. The next purchase or sign-in starts
  /// from a fresh anonymous user.
  Future<void> signOut() async {
    if (!_ready) return;
    await FirebaseAuth.instance.signOut();
  }

  /// Deletes the account on the server (Backend plan → Delete account) and
  /// signs out. Subscriptions are cancelled in the store, not here.
  Future<void> deleteAccount() async {
    final api = await this.api();
    await api?.deleteAccount();
    await signOut();
  }
}
