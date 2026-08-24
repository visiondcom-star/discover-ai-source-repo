import 'package:flutter/foundation.dart';

import '../models/poi.dart';
import '../services/api_service.dart';

/// POI list state. The API seam is injectable so tests run without network.
class POIProvider extends ChangeNotifier {
  POIProvider({PoisApi? poisApi}) : _api = poisApi ?? ApiService();

  final PoisApi _api;

  List<POI> _items = [];
  bool _isLoading = false;
  String? _error;

  List<POI> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPOIs({
    String? city,
    String? category,
    String? search,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data =
          await _api.getPOIs(city: city, category: category, search: search);
      _items = (data['items'] as List? ?? [])
          .map((e) => POI.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
}