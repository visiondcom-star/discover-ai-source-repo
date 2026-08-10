import 'package:flutter/material.dart';
import '../models/tenant.dart';
import '../services/api_service.dart';

class TenantProvider extends ChangeNotifier {
  Tenant? _tenant;
  bool _isLoading = false;
  String? _error;

  Tenant? get tenant => _tenant;
  bool get isLoading => _isLoading;
  String? get error => _error;

  TenantProvider() {
    // Defer load to next frame to avoid notifyListeners during ancestor build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadTenant();
    });
  }

  Future<void> loadTenant() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService().getTenant();
      _tenant = Tenant.fromJson(data);
    } catch (e) {
      _error = e.toString();
      _tenant = null;
    }
    _isLoading = false;
    notifyListeners();
  }
}
