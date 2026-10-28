import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tenant_category.dart';
import '../services/api_service.dart';
import 'safe_notifier.dart';

/// Locale-agnostic failure codes for admin category queue operations.
enum AdminCategoriesError {
  network,
  generic,
}

/// File de validation admin des catégories (proposed / active / rejected).
///
/// Distinct de [TenantProvider.categories], qui ne porte que les catégories
/// `active` visibles par les voyageurs.
class AdminCategoriesProvider extends ChangeNotifier with SafeNotifier {
  AdminCategoriesProvider(this._api, {this.onChanged});

  final AdminCategoriesApi _api;

  /// Appelé après une transition réussie : l'app rafraîchit alors le
  /// catalogue voyageur (TenantProvider) depuis main.dart.
  final VoidCallback? onChanged;

  List<TenantCategory> _categories = const [];
  List<TenantCategory> get categories => _categories;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  AdminCategoriesError? _error;
  AdminCategoriesError? get error => _error;

  final Set<String> _pending = {};
  bool isUpdating(String id) => _pending.contains(id);

  int _loadSeq = 0;

  Future<void> load() async {
    final seq = ++_loadSeq;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.getAllCategories();
      if (disposed || seq != _loadSeq) return;
      _categories = raw.map(TenantCategory.fromJson).toList();
    } on ApiException catch (e) {
      if (disposed || seq != _loadSeq) return;
      _error = e.statusCode == null
          ? AdminCategoriesError.network
          : AdminCategoriesError.generic;
    } on SocketException catch (_) {
      if (disposed || seq != _loadSeq) return;
      _error = AdminCategoriesError.network;
    } on TimeoutException catch (_) {
      if (disposed || seq != _loadSeq) return;
      _error = AdminCategoriesError.network;
    } on http.ClientException catch (_) {
      if (disposed || seq != _loadSeq) return;
      _error = AdminCategoriesError.network;
    } catch (_) {
      if (disposed || seq != _loadSeq) return;
      // On garde la liste précédente : un admin ne doit pas la perdre sur
      // un incident réseau.
      _error = AdminCategoriesError.generic;
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
      if (disposed) return;
      _categories = [
        for (final c in _categories) c.id == updated.id ? updated : c,
      ];
      ok = true;
    } on ApiException catch (e) {
      if (disposed) return;
      _error = e.statusCode == null
          ? AdminCategoriesError.network
          : AdminCategoriesError.generic;
    } on SocketException catch (_) {
      if (disposed) return;
      _error = AdminCategoriesError.network;
    } on TimeoutException catch (_) {
      if (disposed) return;
      _error = AdminCategoriesError.network;
    } on http.ClientException catch (_) {
      if (disposed) return;
      _error = AdminCategoriesError.network;
    } catch (_) {
      if (disposed) return;
      _error = AdminCategoriesError.generic;
    } finally {
      if (!disposed) {
        _pending.remove(category.id);
        notifyListeners();
      }
    }
    if (ok) onChanged?.call();
  }
}
