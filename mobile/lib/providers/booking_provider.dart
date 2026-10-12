import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../models/booking_details.dart';
import '../services/api_service.dart';
import '../utils/idempotency.dart';

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

/// Human-readable message for a failed cancellation. 409 means the booking
/// left the cancellable window (backend: cancel refused from declined /
/// expired / cancelled) — the UI must not offer a retry. Kept separate from
/// [bookingErrorMessage] so the creation cases (409/422) stay untouched.
String cancelErrorMessage(ApiException e) {
  if (e.statusCode == 409) {
    return 'Cette réservation ne peut plus être annulée.';
  }
  return "L'annulation a échoué. Réessayez dans un instant.";
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

  /// Idempotency state of the last create attempt: the key sent and the
  /// content it was bound to. Same signature on the next attempt ⇒ the same
  /// key is replayed (network retry); a different one ⇒ a fresh key, because
  /// the backend answers 409 to a reused key with a different body.
  String? _lastIdempotencyKey;
  String? _lastCreateSignature;

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

  /// [silent] reloads without touching the loading flag / error state —
  /// used on screen open when a 'requested' booking may have changed
  /// server-side (single refresh, no polling).
  Future<void> loadBookings({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final data = await _api.listBookings();
      _items = data.map(Booking.fromJson).toList();
    } catch (e) {
      if (!silent) _error = e.toString();
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
  /// [details] is the traveller's date/guests/notes; it becomes the request's
  /// `booking_data` via `BookingDetails.toBookingData` (only `date`, `guests`
  /// and `notes`, never personal data). When null the body stays exactly the
  /// historical one.
  ///
  /// [idempotencyKey] is forwarded to the backend's `Idempotency-Key`
  /// header: the same key + same body replays the original booking (200)
  /// instead of creating a duplicate. On a replay, the existing item is
  /// replaced in place rather than inserted twice.
  ///
  /// Key ownership, in order of precedence:
  /// 1. an explicit [idempotencyKey] is always sent verbatim;
  /// 2. otherwise the key is kept across attempts while the *content*
  ///    (POI + adapter + details) is unchanged — that is the network-retry
  ///    case, where the backend must replay rather than duplicate;
  /// 3. any change of content mints a new key, because the server would
  ///    answer 409 for the same key with a different body;
  /// 4. the key is dropped after a success, and after a 409/422, which by
  ///    definition starts a new logical attempt (pre-existing rules).
  Future<Booking?> createBooking({
    required String poiId,
    required String adapterType,
    BookingDetails? details,
    String? idempotencyKey,
  }) async {
    _isActing = true;
    _actionError = null;
    _actionStatusCode = null;
    notifyListeners();
    // An explicit key wins; otherwise the key is bound to the content so a
    // retry with unchanged details replays instead of duplicating.
    final content = _contentSignature(poiId, adapterType, details);
    final key = idempotencyKey ??
        (_lastCreateSignature == content ? _lastIdempotencyKey : null) ??
        newIdempotencyKey();
    _lastCreateSignature = content;
    _lastIdempotencyKey = key;
    Booking? created;
    try {
      final json = await _api.createBooking(
        poiId: poiId,
        adapterType: adapterType,
        bookingData: details?.toBookingData(),
        idempotencyKey: key,
      );
      created = Booking.fromJson(json);
      // Idempotent replay: same id already known → replace, never duplicate.
      final known = _items.any((b) => b.id == created!.id);
      _items = known
          ? [for (final b in _items) if (b.id == created.id) created else b]
          : [created, ..._items];
      // The logical attempt is over: forget the key, a later booking is a
      // new one even with identical details.
      _lastIdempotencyKey = null;
      _lastCreateSignature = null;
    } on ApiException catch (e) {
      _actionStatusCode = e.statusCode;
      _actionError = bookingErrorMessage(e);
      // 409/422 means the backend rejected this attempt's key or body: the
      // next try must be a fresh attempt, never the same key again.
      if (e.statusCode == 409 || e.statusCode == 422) {
        _lastIdempotencyKey = null;
        _lastCreateSignature = null;
      }
    } catch (e) {
      _actionError = e.toString();
      // Transport failure: keep the key and its signature so the next tap
      // replays instead of creating a second booking.
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

  /// Mirrors POST /bookings/{id}/cancel. The server response is used as-is
  /// (a 409 from a non-cancellable booking keeps the current status).
  Future<Booking?> cancelBooking(Booking booking) async {
    _isActing = true;
    _actionError = null;
    notifyListeners();
    Booking? updated;
    try {
      final json = await _api.cancelBooking(booking.id);
      updated = Booking.fromJson(json);
    } on ApiException catch (e) {
      _actionError = cancelErrorMessage(e);
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

  /// Content fingerprint of the last create attempt. Two attempts with the
  /// same signature are the same logical request (a retry: the server must
  /// replay); any difference means a different body, which would be answered
  /// 409 under the previous key — so a new key is minted.
  String _contentSignature(
    String poiId,
    String adapterType,
    BookingDetails? details,
  ) {
    final data = details?.toBookingData() ?? const <String, dynamic>{};
    final notes = data['notes'];
    return '$poiId|$adapterType|${data['date']}|${data['guests']}|$notes';
  }
}
