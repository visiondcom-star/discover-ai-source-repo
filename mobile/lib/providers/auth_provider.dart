import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = true;

  User? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    if (_token != null) {
      ApiService().setToken(_token!);
      try {
        final data = await ApiService().getMe();
        _user = User.fromJson(data);
      } catch (e) {
        _token = null;
        _user = null;
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await ApiService().login(email, password);
      _token = data['access_token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      ApiService().setToken(_token!);
      final me = await ApiService().getMe();
      _user = User.fromJson(me);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    ApiService().setToken('');
    notifyListeners();
  }

  Future<bool> register(String email, String password, {String? fullName}) async {
    try {
      await ApiService().register(email, password, fullName: fullName);
      return await login(email, password);
    } catch (e) {
      return false;
    }
  }
}
