import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Verschlüsselter Speicher für Zugangsdaten: Apple-Schlüsselbund (macOS/iOS),
/// Android Keystore, Windows Credential Manager bzw. libsecret unter Linux.
class SecureStore {
  SecureStore();

  /// Moderne Data-Protection-Keychain und klassischer Mac-Schlüsselbund.
  final _modern = _create(dataProtection: true);
  final _classic = _create(dataProtection: false);

  /// Wird beim ersten Zugriff einmal festgelegt, siehe [_backend].
  Future<FlutterSecureStorage>? _chosen;

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

  /// Die moderne Keychain braucht unter macOS die Berechtigung
  /// `keychain-access-groups` (setzt ein Provisioning-Profil voraus). Ohne sie
  /// schlägt das Schreiben fehl, das Lesen meldet aber nur „nicht gefunden“.
  /// Deshalb einmal pro Start mit einem Testeintrag prüfen, statt auf Fehler
  /// zu reagieren; sonst gingen gespeicherte Zugangsdaten nach einem Neustart
  /// scheinbar verloren.
  Future<FlutterSecureStorage> _backend() => _chosen ??= () async {
    const probe = '${_prefix}probe';
    try {
      await _modern.write(key: probe, value: '1');
      final ok = await _modern.read(key: probe) == '1';
      await _modern.delete(key: probe);
      if (ok) return _modern;
    } on PlatformException {
      // Berechtigung fehlt: klassischer Schlüsselbund.
    }
    return _classic;
  }();

  FlutterSecureStorage _other(FlutterSecureStorage storage) => identical(storage, _modern) ? _classic : _modern;

  static const _prefix = 'pulse.';

  /// Fehlt der Eintrag im gewählten Schlüsselbund, wird zur Sicherheit im
  /// anderen gesucht (Einträge früherer Versionen).
  Future<String?> read(String key) async {
    final storage = await _backend();
    final value = await storage.read(key: '$_prefix$key');
    if (value != null) return value;
    try {
      return await _other(storage).read(key: '$_prefix$key');
    } on PlatformException {
      return null;
    }
  }

  Future<void> write(String key, String value) async =>
      (await _backend()).write(key: '$_prefix$key', value: value);

  Future<void> delete(String key) async {
    final storage = await _backend();
    await storage.delete(key: '$_prefix$key');
    try {
      await _other(storage).delete(key: '$_prefix$key');
    } on PlatformException {
      // Im anderen Schlüsselbund gab es nichts zu löschen.
    }
  }

  /// Entfernt alle Einträge dieser App aus beiden Schlüsselbunden (Panik-Knopf).
  Future<void> deleteAll() async {
    for (final storage in [_modern, _classic]) {
      try {
        await storage.deleteAll();
      } on PlatformException {
        // Ohne Berechtigung gibt es dort auch keine Einträge.
      }
    }
  }
}
