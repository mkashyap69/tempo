import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

/// Where the backend is, fixed at compile time with `--dart-define`s (no
/// Firebase config files in the repo). Without them the app runs as it
/// always has: on the phone, no account, no purchases, every Pro feature
/// open in development builds.
///
///   TEMPO_API_URL                 https://api-…a.run.app (Terraform output api_url)
///   TEMPO_FIREBASE_PROJECT        tempo-prod
///   TEMPO_FIREBASE_API_KEY        from the Firebase console
///   TEMPO_FIREBASE_SENDER_ID      project number
///   TEMPO_FIREBASE_IOS_APP_ID     Terraform output ios_app_id
///   TEMPO_FIREBASE_ANDROID_APP_ID Terraform output android_app_id
///   TEMPO_GOOGLE_IOS_CLIENT_ID    for Google sign-in on iOS
///   TEMPO_GOOGLE_SERVER_CLIENT_ID the web client id, for the Firebase credential
///   TEMPO_EMAIL_LINK_URL          `https://<domain>/signin` (an app link)
abstract final class BackendConfig {
  static const apiUrl = String.fromEnvironment('TEMPO_API_URL');
  static const _project = String.fromEnvironment('TEMPO_FIREBASE_PROJECT');
  static const _apiKey = String.fromEnvironment('TEMPO_FIREBASE_API_KEY');
  static const _sender = String.fromEnvironment('TEMPO_FIREBASE_SENDER_ID');
  static const _iosApp = String.fromEnvironment('TEMPO_FIREBASE_IOS_APP_ID');
  static const _androidApp = String.fromEnvironment(
    'TEMPO_FIREBASE_ANDROID_APP_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'TEMPO_GOOGLE_IOS_CLIENT_ID',
  );
  static const googleServerClientId = String.fromEnvironment(
    'TEMPO_GOOGLE_SERVER_CLIENT_ID',
  );
  static const emailLinkUrl = String.fromEnvironment('TEMPO_EMAIL_LINK_URL');

  /// Terms and privacy policy, shown on the paywall (guideline 3.1.2).
  /// TODO(launch): the real domain (L0).
  static const termsUrl = String.fromEnvironment(
    'TEMPO_TERMS_URL',
    defaultValue: 'https://tempo.app/terms',
  );
  static const privacyUrl = String.fromEnvironment(
    'TEMPO_PRIVACY_URL',
    defaultValue: 'https://tempo.app/privacy',
  );

  static bool get configured =>
      apiUrl.isNotEmpty &&
      _project.isNotEmpty &&
      _apiKey.isNotEmpty &&
      (Platform.isIOS ? _iosApp : _androidApp).isNotEmpty;

  static FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: _apiKey,
    appId: Platform.isIOS ? _iosApp : _androidApp,
    messagingSenderId: _sender,
    projectId: _project,
    storageBucket: '$_project-sync',
    iosBundleId: Platform.isIOS ? 'dev.tempo.tempo' : null,
  );
}
