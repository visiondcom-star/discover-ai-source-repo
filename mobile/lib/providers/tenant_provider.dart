import 'package:flutter/foundation.dart';

import '../models/tenant_category.dart';
import '../models/tenant.dart';
import '../services/api_service.dart';

/// Tenant-configuration state (GET /tenants/current). The API seam is
/// injectable so tests run without network.
///
/// The theme is seeded from primary_color/secondary_color. Any failure to
/// fetch the config is non-fatal: the app falls back to the Algeria default
/// theme — branding is decorative, an unreachable API must never block the
/// login screen.
class TenantProvider extends ChangeNotifier {
  TenantProvider({TenantsApi? tenantsApi}) : _api = tenantsApi ?? ApiService();

  final TenantsApi _api;

  Tenant? _tenant;
  List<TenantCategory> _categories = [];
  bool _isLoading = false;
  String? _error;

  Tenant? get tenant => _tenant;
  List<TenantCategory> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetches the tenant config; falls back to [Tenant] defaults on error
  /// (the model already defaults primary_color to '#006233').
  Future<void> loadTenant() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getCurrentTenant();
      _tenant = Tenant.fromJson(data);
    } catch (e) {
      _error = e.toString();
      // Fallback to Algeria defaults (hardcoded in Tenant model).
      _tenant = Tenant.fromJson({});
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Fetches tenant-specific POI categories. Silent failure (empty list)
  /// so POI filtering UI remains functional even when the API is unreachable.
  Future<void> loadCategories() async {
    try {
      final raw = await _api.getTenantCategories();
      _categories = raw.map((json) => TenantCategory.fromJson(json)).toList();
      notifyListeners();
    } catch (_) {
      // Silent fallback: keep previous state or empty list.
      _categories = [];
      notifyListeners();
    }
  }
}
