import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage abstraction for the user-chosen app locale, so providers/tests can
/// inject an in-memory fake instead of the platform channel.
///
/// Same rationale as [TokenStore] (see secure_storage_service.dart): this is
/// a user setting, not a secret — secure storage is reused simply because it
/// is the only key/value store already vetted in this codebase (no
/// SharedPreferences dependency, nothing new to audit).
abstract class LocaleStore {
  Future<String?> readLocaleCode();
  Future<void> writeLocaleCode(String code);
  Future<void> deleteLocaleCode();
}

/// Locale persistence backed by `flutter_secure_storage` (Keychain/Keystore),
/// same store as the auth token — one dependency, one audit surface.
class SecureLocaleStorage implements LocaleStore {
  SecureLocaleStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _localeKey = 'app_locale';

  @override
  Future<String?> readLocaleCode() => _storage.read(key: _localeKey);

  @override
  Future<void> writeLocaleCode(String code) =>
      _storage.write(key: _localeKey, value: code);

  @override
  Future<void> deleteLocaleCode() => _storage.delete(key: _localeKey);
}
