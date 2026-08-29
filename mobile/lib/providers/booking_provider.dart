import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../services/api_service.dart';

/// Booking state, mirroring the backend consent flow exactly:
/// create → pending → explicit consent (true → confirmed + `EXT-…`
/// reference, false → cancelled) → optional cancel.
/// The API seam is injectable so tests run without network.
class BookingProvider extends ChangeNotifier {
  BookingProvider({BookingsApi? bookingsApi})
      : _api = bookingsApi ?? ApiService();

  final BookingsApi _api;

  List<Booking> _items = [];
  Map<String, Map<String, dynamic>> _adapters = {};
  bool _isLoading = false;
  bool _isActing = false;
  String? _error;
  String? _actionError;

  List<Booking> get items => _items;

  /// Only the adapters the backend advertises — the booking sheet never
  /// invents a fallback list.
  Map<String, Map<String, dynamic>> get adapters => _adapters;
  bool get isLoading => _isLoading;
  bool get isActing => _isActing;
  String? get error => _error;
  String? get actionError => _actionError;

  Future<void> loadBookings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.listBookings();
      _items = data.map(Booking.fromJson).toList();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Mirrors GET /bookings/adapters/available.
  Future<void> loadAdapters() async {
    _error = null;
    notifyListeners();
    try {
      final data = await _api.listAdapters();
      final raw = data['adapters'] as Map? ?? {};
      _adapters = raw.map<String, Map<String, dynamic>>(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  /// Creates a PENDING booking (201). Never confirms it — the caller must
  /// walk the user through [giveConsent] next (principle 5).
  Future<Booking?> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic> bookingData = const {},
  }) async {
    _isActing = true;
    _actionError = null;
    notifyListeners();
    Booking? created;
    try {
      final json = await _api.createBooking(
        poiId: poiId,
        adapterType: adapterType,
        bookingData: bookingData,
      );
      created = Booking.fromJson(json);
      _items = [created, ..._items];
    } catch (e) {
      _actionError = e.toString();
    }
    _isActing = false;
    notifyListeners();
    return created;
  }

  /// Explicit consent step — mirrors POST /bookings/{id}/consent:
  /// true → confirmed + external reference, false → cancelled.
  Future<Booking?> giveConsent(Booking booking, {required bool consent}) async {
    _isActing = true;
    _actionError = null;
    notifyListeners();
    Booking? updated;
    try {
      final json = await _api.giveConsent(booking.id, consent: consent);
      updated = Booking.fromJson(json);
    } catch (e) {
      _actionError = e.toString();
    }
    _isActing = false;
    final u = updated;
    if (u != null) {
      _items = [for (final b in _items) if (b.id == u.id) u else b];
    }
    notifyListeners();
    return updated;
  }

  /// Mirrors POST /bookings/{id}/cancel.
  Future<Booking?> cancelBooking(Booking booking) async {
    _isActing = true;
    _actionError = null;
    notifyListeners();
    Booking? updated;
    try {
      final json = await _api.cancelBooking(booking.id);
      updated = Booking.fromJson(json);
    } catch (e) {
      _actionError = e.toString();
    }
    _isActing = false;
    final u = updated;
    if (u != null) {
      _items = [for (final b in _items) if (b.id == u.id) u else b];
    }
    notifyListeners();
    return updated;
  }
}