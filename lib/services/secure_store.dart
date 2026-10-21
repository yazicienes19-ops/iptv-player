import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Verschlüsselter Speicher für Zugangsdaten: Apple-Schlüsselbund (macOS/iOS),
/// Android Keystore, Windows Credential Manager bzw. libsecret unter Linux.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage}) : _storage = storage ?? _create(dataProtection: true);

  FlutterSecureStorage _storage;
  bool _fellBack = false;

  static FlutterSecureStorage _create({required bool dataProtection}) => FlutterSecureStorage(
    iOptions: const IOSOptions(
      // Nur auf diesem Gerät, nicht über iCloud synchronisiert.
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      usesDataProtectionKeychain: dataProtection,
    ),
  );

  /// Die moderne Data-Protection-Keychain braucht unter macOS die Berechtigung
  /// `keychain-access-groups` (setzt ein Provisioning-Profil voraus). Fehlt sie
  /// (errSecMissingEntitlement, -34018), nutzen wir den klassischen
  /// Schlüsselbund; dank fester Signatur ohne Passwort-Dialoge.
  Future<T> _run<T>(Future<T> Function(FlutterSecureStorage s) action) async {
    try {
      return await action(_storage);
    } on PlatformException catch (e) {
      final missingEntitlement = '${e.code} ${e.message} ${e.details}'.contains('-34018');
      if (!missingEntitlement || _fellBack) rethrow;
      _fellBack = true;
      _storage = _create(dataProtection: false);
      return action(_storage);
    }
  }

  static const _prefix = 'pulse.';

  Future<String?> read(String key) => _run((s) => s.read(key: '$_prefix$key'));

  Future<void> write(String key, String value) => _run((s) => s.write(key: '$_prefix$key', value: value));

  Future<void> delete(String key) => _run((s) => s.delete(key: '$_prefix$key'));

  /// Entfernt alle Einträge dieser App aus dem Schlüsselbund.
  Future<void> deleteAll() => _run((s) => s.deleteAll());
}
