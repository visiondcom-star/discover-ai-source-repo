import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

/// Locale-agnostic failure codes for the last [AuthProvider.login] attempt.
/// The provider has no `BuildContext`, so it never renders text itself — the
/// screen maps these to localized strings via `AppLocalizations`.
enum AuthError {
  /// 401 / 403 from the backend (wrong email or password).
  invalidCredentials,

  /// Transport-level failure (no HTTP status).
  network,

  /// Any other server error (5xx, unexpected payload shape).
  generic,
}

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
  AuthError? _loginError;

  User? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;

  /// Code for the last failed [login] (null on success). The screen turns it
  /// into a localized message — the provider stays text-free.
  AuthError? get loginError => _loginError;

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
      if (_token == null || _token!.isEmpty) {
        _loginError = AuthError.generic;
        notifyListeners();
        return false;
      }
      await _store.writeToken(_token!);
      _api.setToken(_token!);
      _user = User.fromJson(await _api.getMe());
      _loginError = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _loginError = _mapLoginError(e.statusCode);
      notifyListeners();
      return false;
    } on SocketException catch (_) {
      _loginError = AuthError.network;
      notifyListeners();
      return false;
    } on TimeoutException catch (_) {
      _loginError = AuthError.network;
      notifyListeners();
      return false;
    } on http.ClientException catch (_) {
      _loginError = AuthError.network;
      notifyListeners();
      return false;
    } catch (_) {
      _loginError = AuthError.generic;
      notifyListeners();
      return false;
    }
  }

  /// Maps an HTTP status to a [AuthError]. 401/403 are credential failures;
  /// a null status is a transport failure; everything else is generic.
  AuthError _mapLoginError(int? statusCode) {
    if (statusCode == null) return AuthError.network;
    if (statusCode == 401 || statusCode == 403) {
      return AuthError.invalidCredentials;
    }
    return AuthError.generic;
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
    _loginError = null;
    await _store.deleteToken();
    _api.setToken('');
    notifyListeners();
  }
}
