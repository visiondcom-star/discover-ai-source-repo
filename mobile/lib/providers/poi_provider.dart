import 'package:flutter/material.dart';
import '../models/poi.dart';
import '../services/api_service.dart';

class POIProvider extends ChangeNotifier {
  List<POI> _pois = [];
  List<POI> _filtered = [];
  bool _isLoading = false;
  String? _error;

  List<POI> get pois => _filtered;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPOIs({String? city, String? category, String? search}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService().getPOIs(city: city, category: category, search: search);
      _pois = (data['items'] as List).map((e) => POI.fromJson(e)).toList();
      _filtered = List.from(_pois);
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  void filter(String query) {
    if (query.isEmpty) {
      _filtered = List.from(_pois);
    } else {
      _filtered = _pois.where((p) =>
        p.name.toLowerCase().contains(query.toLowerCase()) ||
        p.city.toLowerCase().contains(query.toLowerCase())
      ).toList();
    }
    notifyListeners();
  }
}
