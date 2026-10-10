import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../services/api_service.dart';

/// Human-readable message for a failed booking creation. The 409 case can
/// only happen when an idempotency key was reused with a different payload
/// (e.g. the user switched adapter mid-retry) — the sheet must be reopened
/// with a fresh key. 422 covers `info_only` and the not-yet-supported modes
/// (deposit / online_payment) refused by the backend.
String bookingErrorMessage(ApiException e) {
  switch (e.statusCode) {
    case 409:
      return "Cette demande a déjà été envoyée avec des informations "
          "différentes. Rouvrez la fenêtre et réessayez.";
    case 422:
      return "La réservation n'est pas disponible pour ce lieu.";
    default:
      return "La réservation a échoué. Réessayez dans un instant.";
  }
}

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
  int? _actionStatusCode;

  List<Booking> get items => _items;

  /// Only the adapters the backend advertises — the booking sheet never
  /// invents a fallback list.
  Map<String, Map<String, dynamic>> get adapters => _adapters;
  bool get isLoading => _isLoading;
  bool get isActing => _isActing;
  String? get error => _error;
  String? get actionError => _actionError;

  /// HTTP status of the last failed action (ApiException only) — lets the
  /// booking sheet decide whether an idempotency key is still valid
  /// (409/422 → discard it) or must be kept for the retry (network/5xx).
  int? get actionStatusCode => _actionStatusCode;

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
  ///
  /// [idempotencyKey] is forwarded to the backend's `Idempotency-Key`
  /// header: the same key + same body replays the original booking (200)
  /// instead of creating a duplicate. On a replay, the existing item is
  /// replaced in place rather than inserted twice.
  Future<Booking?> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic> bookingData = const {},
    String? idempotencyKey,
  }) async {
    _isActing = true;
    _actionError = null;
    _actionStatusCode = null;
    notifyListeners();
    Booking? created;
    try {
      final json = await _api.createBooking(
        poiId: poiId,
        adapterType: adapterType,
        bookingData: bookingData,
        idempotencyKey: idempotencyKey,
      );
      created = Booking.fromJson(json);
      // Idempotent replay: same id already known → replace, never duplicate.
      final known = _items.any((b) => b.id == created!.id);
      _items = known
          ? [for (final b in _items) if (b.id == created.id) created else b]
          : [created, ..._items];
    } on ApiException catch (e) {
      _actionStatusCode = e.statusCode;
      _actionError = bookingErrorMessage(e);
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
      _items = [
        for (final b in _items)
          if (b.id == u.id) u else b
      ];
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
      _items = [
        for (final b in _items)
          if (b.id == u.id) u else b
      ];
    }
    notifyListeners();
    return updated;
  }
}
