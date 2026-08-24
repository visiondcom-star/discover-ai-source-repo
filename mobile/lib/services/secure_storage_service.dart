import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage abstraction for the auth token, so providers/tests can inject an
/// in-memory fake instead of the platform channel.
abstract class TokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

/// JWT persistence backed by `flutter_secure_storage`.
///
/// - iOS: Keychain
/// - Android: Keystore-backed encrypted storage
///
/// NEVER swap this for SharedPreferences: those are plain-text files readable
/// by backups and other debuggable processes on rooted devices.
class SecureStorageService implements TokenStore {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'auth_token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}