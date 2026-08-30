import 'package:flutter/foundation.dart';

import '../models/promotion.dart';
import '../services/api_service.dart';

/// Home-banner promotion state. The API seam is injectable so tests run
/// without network.
///
/// The backend already returns only active, in-window promotions ordered
/// by priority — this provider never re-filters or re-sorts, it just
/// surfaces loading/error state around what the backend sent.
class PromotionProvider extends ChangeNotifier {
  PromotionProvider({PromotionsApi? promotionsApi})
      : _api = promotionsApi ?? ApiService();

  final PromotionsApi _api;

  List<Promotion> _items = [];
  bool _isLoading = false;
  String? _error;

  List<Promotion> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPromotions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getPromotions();
      _items = (data['items'] as List? ?? [])
          .map((e) => Promotion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // A promo banner is decorative, not essential: fail quietly and let
      // the screen simply omit the banner rather than surface an error UI
      // for something the user didn't ask for.
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
}
