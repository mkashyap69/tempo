import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for an api answer other than success; [code] is the api's
/// `error` (e.g. `other_account`, `not_opted_in`) or the HTTP status.
class ApiException implements Exception {
  const ApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'ApiException($status, $code)';
}

/// Tokens for one call: the Firebase ID token and an App Check token.
typedef TokenSource = Future<({String idToken, String? appCheck})> Function();

/// Calls to `api` (backend/src/app.ts; docs/network.md). Every call carries
/// the user's Firebase ID token and an App Check token. Nothing here sends
/// health data.
class ApiClient {
  ApiClient(this.baseUrl, this.tokens, {http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final TokenSource tokens;
  final http.Client _http;

  Future<Map<String, Object?>> _call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final t = await tokens();
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'authorization': 'Bearer ${t.idToken}',
        if (t.appCheck != null) 'x-firebase-appcheck': t.appCheck!,
        'content-type': 'application/json',
      });
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 20)),
    );
    Map<String, Object?> j = const {};
    if (res.body.isNotEmpty) {
      try {
        j = (jsonDecode(res.body) as Map).cast<String, Object?>();
      } catch (_) {}
    }
    if (res.statusCode >= 300) {
      throw ApiException(res.statusCode, '${j['error'] ?? res.statusCode}');
    }
    return j;
  }

  /// Creates the account record on first call; returns the entitlement.
  Future<Map<String, Object?>> init() async =>
      ((await _call('POST', '/account/init'))['entitlement']! as Map)
          .cast<String, Object?>();

  Future<Map<String, Object?>> entitlement() =>
      _call('GET', '/billing/entitlement');

  Future<Map<String, Object?>> verifyApple(String jws, {bool move = false}) =>
      _call('POST', '/billing/apple/verify', {
        'signedTransaction': jws,
        if (move) 'move': true,
      });

  Future<Map<String, Object?>> verifyGoogle(
    String productId,
    String token, {
    bool move = false,
  }) => _call('POST', '/billing/google/verify', {
    'productId': productId,
    'purchaseToken': token,
    if (move) 'move': true,
  });

  Future<void> consent({required bool diagnostics, required bool events}) =>
      _call('POST', '/account/consent', {
        'diagnostics': diagnostics,
        'events': events,
      });

  Future<void> deleteAccount() => _call('POST', '/account/delete');

  Future<String> feedback({
    required String text,
    required String appVersion,
    required String platform,
    String? screenshotBase64,
    String? report,
  }) async =>
      (await _call('POST', '/feedback', {
            'text': text,
            'appVersion': appVersion,
            'platform': platform,
            'screenshot': ?screenshotBase64,
            'report': ?report,
          }))['id']!
          as String;
}
