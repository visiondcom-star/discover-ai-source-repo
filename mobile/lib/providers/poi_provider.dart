import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/poi.dart';
import '../services/api_service.dart';

/// POI list state. The API seam is injectable so tests run without network.
///
/// Search contract (Explorer live search): [updateSearch] debounces
/// keystrokes by [searchDebounce] and every fetch is sequence-guarded so a
/// slow stale response can never overwrite a fresher one — once every pause
/// in typing fires a request, out-of-order responses are guaranteed.
class POIProvider extends ChangeNotifier {
  POIProvider({PoisApi? poisApi}) : _api = poisApi ?? ApiService();

  static const Duration searchDebounce = Duration(milliseconds: 300);

  final PoisApi _api;

  List<POI> _items = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  Timer? _debounce;
  int _seq = 0;

  List<POI> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Currently active search term (empty when showing the full list).
  String get searchQuery => _searchQuery;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Full load — initial fetch, pull-to-refresh, or search reset.
  ///
  /// Cancels any pending debounced search so a queued request can never fire
  /// after an explicit reload. Passing [search] re-applies it (used by
  /// pull-to-refresh to keep the field and the list consistent).
  Future<void> loadPOIs({
    String? city,
    String? category,
    String? search,
  }) {
    _debounce?.cancel();
    _debounce = null;
    _searchQuery = search ?? '';
    return _fetch(city: city, category: category, search: search);
  }

  /// Debounced live search from the Explorer search field.
  ///
  /// An empty query resets to the full list immediately (no debounce) —
  /// clearing the field must feel instant.
  void updateSearch(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchQuery = '';
      _fetch();
      return;
    }
    _searchQuery = trimmed;
    _debounce = Timer(searchDebounce, () {
      _fetch(search: trimmed);
    });
  }

  Future<void> _fetch({
    String? city,
    String? category,
    String? search,
  }) async {
    final seq = ++_seq;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data =
          await _api.getPOIs(city: city, category: category, search: search);
      if (seq != _seq) return; // stale response — discard silently
      _items = (data['items'] as List? ?? [])
          .map((e) => POI.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      if (seq != _seq) return; // stale failure — discard silently
      _error = e.toString();
    }
    if (seq != _seq) return;
    _isLoading = false;
    notifyListeners();
  }
}