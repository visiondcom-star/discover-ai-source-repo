import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

/// Auth state holder. The JWT lives exclusively in a [TokenStore]
/// (iOS Keychain / Android Keystore via flutter_secure_storage) — never in
/// SharedPreferences.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthApi? api, TokenStore? tokenStore})
      : _api = api ?? ApiService(),
        _store = tokenStore ?? SecureStorageService() {
    _initialized = _restoreSession();
  }

  final AuthApi _api;
  final TokenStore _store;

  late final Future<void> _initialized;

  User? _user;
  String? _token;
  bool _isLoading = true;

  User? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;

  /// Resolves once the initial session restore finished (tests, splash UX).
  Future<void> get initialized => _initialized;

  Future<void> _restoreSession() async {
    _token = await _store.readToken();
    if (_token != null) {
      _api.setToken(_token!);
      try {
        _user = User.fromJson(await _api.getMe());
      } catch (_) {
        // Stale or invalid token: forget it silently.
        _token = null;
        _user = null;
        await _store.deleteToken();
        _api.setToken('');
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await _api.login(email, password);
      _token = data['access_token'] as String?;
      if (_token == null || _token!.isEmpty) return false;
      await _store.writeToken(_token!);
      _api.setToken(_token!);
      _user = User.fromJson(await _api.getMe());
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> register(
    String email,
    String password, {
    String? fullName,
  }) async {
    try {
      await _api.register(email, password, fullName: fullName);
    } catch (_) {
      return false;
    }
    return await login(email, password);
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _store.deleteToken();
    _api.setToken('');
    notifyListeners();
  }
}
