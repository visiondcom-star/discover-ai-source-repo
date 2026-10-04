import 'package:flutter/foundation.dart';

import '../models/tenant_category.dart';
import '../services/api_service.dart';

/// File de validation admin des catégories (proposed / active / rejected).
///
/// Distinct de [TenantProvider.categories], qui ne porte que les catégories
/// `active` visibles par les voyageurs.
class AdminCategoriesProvider extends ChangeNotifier {
  AdminCategoriesProvider(this._api, {this.onChanged});

  final AdminCategoriesApi _api;

  /// Appelé après une transition réussie : l'app rafraîchit alors le
  /// catalogue voyageur (TenantProvider) depuis main.dart.
  final VoidCallback? onChanged;

  List<TenantCategory> _categories = const [];
  List<TenantCategory> get categories => _categories;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  final Set<String> _pending = {};
  bool isUpdating(String id) => _pending.contains(id);

  int _loadSeq = 0;
  bool _disposed = false;

  Future<void> load() async {
    final seq = ++_loadSeq;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.getAllCategories();
      if (_disposed || seq != _loadSeq) return;
      _categories = raw.map(TenantCategory.fromJson).toList();
    } catch (_) {
      if (_disposed || seq != _loadSeq) return;
      // On garde la liste précédente : un admin ne doit pas la perdre sur
      // un incident réseau.
      _error = 'Impossible de charger les catégories.';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setStatus(TenantCategory category, String status) async {
    if (!_pending.add(category.id)) return; // anti double-tap
    _error = null;
    notifyListeners();
    var ok = false;
    try {
      final updated = TenantCategory.fromJson(await _api.updateCategoryStatus(
        categoryId: category.id,
        status: status,
      ));
      if (_disposed) return;
      _categories = [
        for (final c in _categories) c.id == updated.id ? updated : c,
      ];
      ok = true;
    } catch (_) {
      if (_disposed) return;
      _error = 'Échec de la mise à jour de la catégorie.';
    } finally {
      if (!_disposed) {
        _pending.remove(category.id);
        notifyListeners();
      }
    }
    if (ok) onChanged?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
