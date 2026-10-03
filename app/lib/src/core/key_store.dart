import 'package:band_ble/band_ble.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The auth key lives only in flutter_secure_storage.
///
/// Dev convenience: a debug build run with `--dart-define-from-file=../.env`
/// seeds secure storage from `BAND_AUTH_KEY` on first launch. Release builds
/// ignore it; the key is pasted in the UI instead.
class KeyStore {
  KeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Background sync runs while the phone is locked.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;
  static const _slot = 'band_auth_key';
  static const _devKey = String.fromEnvironment('BAND_AUTH_KEY');

  Future<AuthKey?> load() async {
    var raw = await _storage.read(key: _slot);
    if (raw == null && kDebugMode && _devKey.isNotEmpty) {
      AuthKey.parse(_devKey); // validate before storing
      await _storage.write(key: _slot, value: _devKey);
      raw = _devKey;
    }
    return raw == null ? null : AuthKey.parse(raw);
  }

  Future<AuthKey> save(String input) async {
    final key = AuthKey.parse(input);
    await _storage.write(key: _slot, value: input.trim());
    return key;
  }

  Future<void> clear() => _storage.delete(key: _slot);
}
